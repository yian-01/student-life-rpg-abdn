import 'dart:convert';

import '../../../storage/json_document_store.dart';
import '../models/task.dart';
import 'task_repository.dart';

/// 基于 JsonDocumentStore 的 Task 仓库实现。
///
/// 串行队列保证所有操作按顺序执行。
/// 写入失败时保留旧内存，避免内存与磁盘状态不一致。
class FileTaskRepository implements TaskRepository {
  final JsonDocumentStore _store;
  final String _path;
  final int _schemaVersion = 1;
  final String _entityType = 'task';

  List<Task>? _tasks;
  Future<void> _last = Future.value();

  FileTaskRepository(this._store, this._path);

  Future<T> _queued<T>(Future<T> Function() action) {
    final result = _last.then((_) => action());
    _last = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<List<Task>> _load() async {
    if (_tasks != null) return _tasks!;

    final raw = await _store.readDocument(_path);
    if (raw == null) {
      _tasks = [];
      return _tasks!;
    }

    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw JsonDocumentStoreIOException('Task 文档不是合法 JSON');
    }

    if (decoded is! Map<String, dynamic>) {
      throw JsonDocumentStoreIOException('Task 文档根节点必须是 JSON 对象');
    }

    if (decoded['schemaVersion'] != _schemaVersion) {
      throw JsonDocumentStoreIOException(
        '不支持的 schemaVersion: ${decoded['schemaVersion']}',
      );
    }
    if (decoded['entityType'] != _entityType) {
      throw JsonDocumentStoreIOException('entityType 必须是 "$_entityType"');
    }

    final records = decoded['records'];
    if (records is! List) {
      throw JsonDocumentStoreIOException('records 必须是数组');
    }

    final tasks = <Task>[];
    for (final item in records) {
      if (item is! Map<String, dynamic>) {
        throw JsonDocumentStoreIOException('records 中的条目必须是 JSON 对象');
      }
      tasks.add(Task.fromJson(item));
    }

    _tasks = tasks;
    return _tasks!;
  }

  Future<void> _save(List<Task> next) async {
    final content = jsonEncode({
      'schemaVersion': _schemaVersion,
      'entityType': _entityType,
      'records': [for (final task in next) task.toJson()],
    });
    // 先成功写盘，再更新内存；写盘失败时内存保持旧值
    await _store.writeDocument(_path, content);
    _tasks = next;
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
