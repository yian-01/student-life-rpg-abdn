import '../../../storage/json_document_store.dart';
import '../models/task.dart';
import 'task_repository.dart';

/// 基于文件系统与 [JsonDocumentStore] 的任务仓库持久化实现。
/// 所有操作通过串行队列执行，保证读取、校验、持久化和内存提交的原子性。
class FileTaskRepository implements TaskRepository {
  static const int _schemaVersion = 1;
  static const String _entityType = 'task';

  final JsonDocumentStore _store;
  final String _filePath;

  List<Task> _cache = [];
  bool _loaded = false;

  // 串行队列：确保同一时间只有一个文件操作在执行
  Future<void> _queue = Future.value();

  FileTaskRepository({required this._store, required this._filePath});

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = _queue.then((_) => action());
    _queue = completer.then((_) {}, onError: (_) {});
    return completer;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final decoded = await _store.read(_filePath);
    _cache = _decodeDocument(decoded);
    _loaded = true;
  }

  List<Task> _decodeDocument(Map<String, dynamic> decoded) {
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

    return records.map((e) {
      if (e is! Map<String, dynamic>) {
        throw const FormatException('records 中的每条记录必须是对象');
      }
      return Task.fromJson(e);
    }).toList();
  }

  Map<String, dynamic> _encodeDocument(List<Task> tasks) {
    return {
      'schemaVersion': _schemaVersion,
      'entityType': _entityType,
      'records': tasks.map((t) => t.toJson()).toList(),
    };
  }

  Future<void> _persistAndCommit(List<Task> next) async {
    await _store.write(_filePath, _encodeDocument(next));
    _cache = next;
  }

  @override
  Future<List<Task>> list() => _enqueue(() async {
    await _ensureLoaded();
    return List.unmodifiable(_cache);
  });

  @override
  Future<Task?> getById(String id) => _enqueue(() async {
    await _ensureLoaded();
    for (final task in _cache) {
      if (task.id == id) return task;
    }
    return null;
  });

  @override
  Future<void> insert(Task task) => _enqueue(() async {
    await _ensureLoaded();
    if (_cache.any((t) => t.id == task.id)) {
      throw StateError('Task id "${task.id}" 已存在，不能重复插入');
    }
    final next = [..._cache, task];
    await _persistAndCommit(next);
  });

  @override
  Future<void> update(Task task) => _enqueue(() async {
    await _ensureLoaded();
    final index = _cache.indexWhere((t) => t.id == task.id);
    if (index == -1) {
      throw StateError('Task id "${task.id}" 不存在，无法更新');
    }
    final next = [..._cache]..[index] = task;
    await _persistAndCommit(next);
  });

  @override
  Future<bool> remove(String id) => _enqueue(() async {
    await _ensureLoaded();
    if (!_cache.any((t) => t.id == id)) {
      throw StateError('Task id "$id" 不存在，无法删除');
    }
    final next = _cache.where((t) => t.id != id).toList();
    await _persistAndCommit(next);
    return true;
  });

  @override
  Future<void> setCompleted(String id, bool isCompleted) => _enqueue(() async {
    await _ensureLoaded();
    final index = _cache.indexWhere((t) => t.id == id);
    if (index == -1) {
      throw StateError('Task id "$id" 不存在，无法设置完成状态');
    }
    final current = _cache[index];
    if (current.isCompleted == isCompleted) {
      return;
    }
    final updated = current.copyWith(isCompleted: isCompleted);
    final next = [..._cache]..[index] = updated;
    await _persistAndCommit(next);
  });
}
