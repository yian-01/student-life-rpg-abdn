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
/// - 普通读取只校验、不写盘：主文件损坏或缺失（即使 `.bak` 存在）都直接报错，
///   绝不静默恢复旧数据，由用户显式调用 [recoverFromBackup] 触发恢复。
/// - 显式恢复先完整校验备份，再归档损坏原件为 `.corrupt`（已有归档时使用后缀），
///   写回成功后才提交内存；失败时保留原件、有效备份与旧内存状态。
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
      // 主文件缺失时不能当作首次运行：只要存在备份，就必须显式恢复。
      // 普通读取保持只读，不写主文件、不复活旧数据。
      final backupRaw = await _store.readDocument('$_path.bak');
      if (backupRaw != null) {
        throw const FormatException('主文件缺失但备份存在，需要显式恢复后才能读取');
      }
      _tasks = const [];
      return _tasks!;
    }

    // 主文件损坏时直接报错，不做任何静默恢复或磁盘写入。
    _tasks = _decodeTasks(raw);
    return _tasks!;
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

  /// 显式恢复：仅在用户确认后调用。
  ///
  /// 顺序保证：先完整校验备份，再归档损坏原件，最后写回主文件；
  /// 只有写盘成功后才提交内存。任一步失败都保留损坏原件（归档后仍在磁盘上）
  /// 与有效 `.bak`，内存保持调用前的状态，待故障排除后可再次恢复。
  Future<void> recoverFromBackup() {
    return _queued(() async {
      final previous = _tasks;
      try {
        final raw = await _store.readDocument(_path);
        if (raw != null) {
          try {
            _tasks = _decodeTasks(raw);
            return;
          } on FormatException {
            // 主文件损坏：继续尝试显式备份恢复。
          }
        }
        // 主文件缺失或损坏：走显式恢复流程。
        _tasks = await _restoreFromBackupDocument();
      } catch (_) {
        _tasks = previous;
        rethrow;
      }
    });
  }

  /// 校验备份 → 归档损坏原件 → 写回主文件 → 返回已校验的备份数据。
  /// 校验或写盘失败时向上抛出，此时原件与 `.bak` 均未被覆盖。
  Future<List<Task>> _restoreFromBackupDocument() async {
    final backupRaw = await _store.readDocument('$_path.bak');
    if (backupRaw == null) {
      throw FormatException('主文件损坏或缺失，且无备份可恢复: $_path');
    }
    final backupTasks = _decodeTasks(backupRaw);
    await _archiveCorruptMain();
    await _store.writeDocument(_path, backupRaw);
    return backupTasks;
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
