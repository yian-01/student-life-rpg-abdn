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

  /// 最近一次从磁盘读到（或成功写入）的原始内容，用于检测外部变更。
  /// 主文件被其他写入方改动后，用它拒绝以旧内存状态覆盖新数据。
  String? _lastDiskRaw;

  /// 内存状态是否来自一份真实存在的磁盘文档。
  /// 首次运行时为 false，允许直接创建主文件；一旦加载过真实文档，
  /// 之后主文件消失就视为外部故障，必须先显式恢复再保存。
  bool _loadedFromDisk = false;

  /// 上一次保存是否失败。失败时主文件可能暂时缺失（替换阶段中断），
  /// 这属于本实例自己的故障，允许按内存状态重试；而外部删除主文件
  /// 必须显式恢复，不能把旧内存写回去。
  bool _lastWriteFailed = false;

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
    _lastDiskRaw = raw;
    _loadedFromDisk = true;
    return _tasks!;
  }

  Future<void> _save(List<Task> next) async {
    // A normal mutation must not implicitly recover, resurrect or overwrite data
    // that changed outside this instance. The caller can explicitly recover or
    // rebuild the repository, then retry the rejected mutation.
    final diskRaw = await _store.readDocument(_path);
    if (diskRaw == null) {
      // 内存来自真实文档，但主文件已消失（外部删除或替换失败）：
      // 拒绝用旧内存写回，否则会把已被移除的数据复活成新的主文件。
      if (_loadedFromDisk && !_lastWriteFailed) {
        throw const FormatException('主文件已在外部丢失，需显式恢复后才能保存');
      }
      // 真实首次运行：允许创建主文件。
    } else {
      // 主文件损坏时不覆盖（保留原件与有效 .bak）。
      _decodeTasks(diskRaw);
      // 主文件在缓存之后被其他写入方创建或改动：拒绝用旧内存状态覆盖。
      if (diskRaw != _lastDiskRaw) {
        throw StateError('主文件已被外部修改，拒绝以旧内存状态覆盖: $_path');
      }
    }
    final content = jsonEncode({
      'schemaVersion': _schemaVersion,
      'entityType': _entityType,
      'records': [for (final task in next) task.toJson()],
    });
    // 先成功写盘，再更新内存；写盘失败时内存保持旧值
    try {
      await _store.writeDocument(_path, content);
    } catch (_) {
      // 只有主文件确实缺失（替换阶段中断）才允许按内存状态重试；
      // 临时文件或备份阶段失败时主文件完好，之后的主文件消失属于外部删除。
      var mainMissing = false;
      try {
        mainMissing = await _store.readDocument(_path) == null;
      } on FileSystemException {
        mainMissing = true;
      }
      _lastWriteFailed = mainMissing;
      rethrow;
    }
    _lastWriteFailed = false;
    _tasks = next;
    _lastDiskRaw = content;
    _loadedFromDisk = true;
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
            _lastDiskRaw = raw;
            _loadedFromDisk = true;
            _lastWriteFailed = false;
            return;
          } on FormatException {
            // 主文件损坏：继续尝试显式备份恢复。
          }
        }
        // 主文件缺失或损坏：走显式恢复流程。
        _tasks = await _restoreFromBackupDocument();
        _lastWriteFailed = false;
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
    _lastDiskRaw = backupRaw;
    _loadedFromDisk = true;
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
