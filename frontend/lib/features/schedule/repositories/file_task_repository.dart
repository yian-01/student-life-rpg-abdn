import 'dart:convert';
import 'dart:io';

import '../../../shared/storage/json_document_store.dart';
import '../models/local_datetime_json.dart';
import '../models/task.dart';
import 'task_repository.dart';

/// 基于 [JsonDocumentStore] 的 Task 仓库实现。
///
/// 职责：
/// - JSON 解析与 schemaVersion / entityType / records 完整校验（Store 只负责原始读写）。
/// - 串行队列覆盖读取、校验、持久化与内存提交全过程。
/// - 写盘成功后才更新内存；写盘失败保留旧内存状态，后续请求仍可继续。
/// - 主文件损坏时，尝试从 `.bak` 恢复；恢复前对备份做完整 Task 文档校验，
///   损坏原件独立归档为 `.corrupt`（已有归档时使用后缀），有效备份保留。
///
/// 错误类型遵循冻结契约第 3 节：
/// - JSON 结构 / schemaVersion / entityType / records 错误 → [FormatException]
/// - 文件 I/O 故障 → 保留原始 [FileSystemException]
/// - 重复 ID / 未知更新 → [StateError]
/// - 空白 ID 参数 → [ArgumentError]
class FileTaskRepository implements TaskRepository {
  FileTaskRepository(this._store, this._path);

  final JsonDocumentStore _store;
  final String _path;
  static const int _schemaVersion = 1;
  static const String _entityType = 'Task';
  static const Set<String> _documentKeys = <String>{
    'schemaVersion',
    'entityType',
    'records',
  };

  List<Task>? _tasks;
  Future<void> _last = Future.value();

  Future<T> _queued<T>(Future<T> Function() action) {
    final result = _last.then((_) => action());
    _last = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// 解析并校验完整 Task 文档：JSON 结构、schemaVersion、entityType、records、
  /// Task 字段及重复 ID。失败抛出 [FormatException]。
  List<Task> _decodeTasks(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('Task 文档不是合法 JSON');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Task 文档根节点必须是 JSON 对象');
    }

    // 顶层拒绝未知字段：契约第 4.2 节要求顶层、模型和嵌套对象均拒绝未知字段。
    rejectUnknownKeys(decoded, _documentKeys, 'Task document');

    if (decoded['schemaVersion'] != _schemaVersion) {
      throw FormatException('不支持的 schemaVersion: ${decoded['schemaVersion']}');
    }
    if (decoded['entityType'] != _entityType) {
      throw FormatException('entityType 必须是 "$_entityType"');
    }

    final records = decoded['records'];
    if (records is! List) {
      throw const FormatException('records 必须是数组');
    }

    final tasks = <Task>[];
    final seenIds = <String>{};
    for (final item in records) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('records 中的条目必须是 JSON 对象');
      }
      final task = Task.fromJson(item);
      if (!seenIds.add(task.id)) {
        throw FormatException('records 中存在重复 ID: ${task.id}');
      }
      tasks.add(task);
    }
    return tasks;
  }

  /// 将损坏的主文件归档为 `.corrupt`，避免常规覆盖时顶掉有效 `.bak`。
  /// 已有归档保留，后续使用递增后缀。
  Future<void> _archiveCorruptMain() async {
    final file = File(_path);
    if (!await file.exists()) return;
    var archivePath = '$_path.corrupt';
    var suffix = 1;
    while (await FileSystemEntity.type(archivePath) !=
        FileSystemEntityType.notFound) {
      archivePath = '$_path.corrupt.${suffix++}';
    }
    await file.rename(archivePath);
  }

  Future<List<Task>> _load() async {
    if (_tasks != null) return _tasks!;

    final raw = await _store.readDocument(_path);
    if (raw == null) {
      // 主文件不存在：可能是首次运行，也可能是主文件丢失（如替换失败）。
      // 仅当 .bak 存在时尝试恢复；否则视为首次，返回空列表。
      final backupRaw = await _store.readDocument('$_path.bak');
      if (backupRaw == null) {
        _tasks = const [];
        return _tasks!;
      }
      final backupTasks = _decodeTasks(backupRaw);
      // 先归档（主文件即使不存在也无害），再写回，确保 .bak 不被覆盖。
      await _archiveCorruptMain();
      await _store.writeDocument(_path, backupRaw);
      // 恢复成功后明确提示；失败时异常自然上抛，不输出成功提示。
      // ignore: avoid_print
      print('WARNING: 主文件 $_path 不存在，已从 .bak 恢复');
      _tasks = backupTasks;
      return _tasks!;
    }

    try {
      _tasks = _decodeTasks(raw);
      return _tasks!;
    } on FormatException {
      // 主文件损坏：尝试从 .bak 恢复
      final backupRaw = await _store.readDocument('$_path.bak');
      if (backupRaw == null) {
        throw FormatException('主文件损坏且无备份，拒绝加载: $_path');
      }

      final backupTasks = _decodeTasks(backupRaw);
      // 先归档损坏原件，再写回；这样 writeDocument 不会触碰到有效 .bak。
      await _archiveCorruptMain();
      await _store.writeDocument(_path, backupRaw);
      // 恢复成功后明确提示。
      // ignore: avoid_print
      print(
        'WARNING: 主文件 $_path 损坏，已从 .bak 恢复；损坏原件已归档至 $_path.corrupt（已有归档时使用后缀）',
      );
      _tasks = backupTasks;
      return _tasks!;
    }
  }

  Future<void> _save(List<Task> next) async {
    // A normal mutation must not implicitly recover or overwrite corrupt data.
    // Leave the damaged document and the last valid backup untouched. The caller
    // can explicitly recover, then retry the rejected mutation.
    final diskRaw = await _store.readDocument(_path);
    if (diskRaw != null) _decodeTasks(diskRaw);
    final content = jsonEncode({
      'schemaVersion': _schemaVersion,
      'entityType': _entityType,
      'records': [for (final task in next) task.toJson()],
    });
    // 先成功写盘，再更新内存；写盘失败时内存保持旧值
    await _store.writeDocument(_path, content);
    _tasks = next;
  }

  /// Explicitly reload disk data, using a validated backup when necessary.
  /// A failed recovery leaves the existing in-memory state unchanged. Callers
  /// must await success before retrying a mutation rejected for corruption.
  Future<void> recoverFromBackup() {
    return _queued(() async {
      final previous = _tasks;
      _tasks = null;
      try {
        await _load();
      } catch (_) {
        _tasks = previous;
        rethrow;
      }
    });
  }

  static void _requireId(String id, String field) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, field, 'must not be empty');
    }
  }

  @override
  Future<List<Task>> list() {
    return _queued(() async {
      final items = await _load();
      return List.unmodifiable(items);
    });
  }

  @override
  Future<Task?> getById(String id) {
    return _queued(() async {
      _requireId(id, 'id');
      final items = await _load();
      for (final task in items) {
        if (task.id == id) return task;
      }
      return null;
    });
  }

  @override
  Future<void> insert(Task entity) {
    return _queued(() async {
      _requireId(entity.id, 'entity.id');
      final items = await _load();
      if (items.any((task) => task.id == entity.id)) {
        throw StateError('Task with id ${entity.id} already exists');
      }
      await _save([...items, entity]);
    });
  }

  @override
  Future<void> update(Task entity) {
    return _queued(() async {
      _requireId(entity.id, 'entity.id');
      final items = await _load();
      final index = items.indexWhere((task) => task.id == entity.id);
      if (index == -1) {
        throw StateError('Task with id ${entity.id} does not exist');
      }
      final next = [...items];
      next[index] = entity;
      await _save(next);
    });
  }

  @override
  Future<bool> remove(String id) {
    return _queued(() async {
      _requireId(id, 'id');
      final items = await _load();
      final index = items.indexWhere((task) => task.id == id);
      if (index == -1) return false;
      final next = [...items]..removeAt(index);
      await _save(next);
      return true;
    });
  }

  @override
  Future<void> setCompleted(String id, bool isCompleted) {
    return _queued(() async {
      _requireId(id, 'id');
      final items = await _load();
      final index = items.indexWhere((task) => task.id == id);
      if (index == -1) {
        throw StateError('Task with id $id does not exist');
      }
      final current = items[index];
      if (current.isCompleted == isCompleted) return;
      final next = [...items];
      next[index] = current.copyWith(isCompleted: isCompleted);
      await _save(next);
    });
  }
}
