import '../models/task.dart';
import 'task_repository.dart';

/// 内存版任务仓库：用于开发与单元测试；应用退出后数据不保留。
class InMemoryTaskRepository implements TaskRepository {
  final Map<String, Task> _byId = <String, Task>{};

  @override
  Future<List<Task>> list() async {
    return List<Task>.unmodifiable(_byId.values.toList(growable: false));
  }

  @override
  Future<Task?> getById(String id) async {
    _requireId(id, 'id');
    return _byId[id];
  }

  @override
  Future<void> insert(Task entity) async {
    _requireId(entity.id, 'entity.id');
    if (_byId.containsKey(entity.id)) {
      throw StateError('Task already exists: ${entity.id}');
    }
    _byId[entity.id] = entity;
  }

  @override
  Future<void> update(Task entity) async {
    _requireId(entity.id, 'entity.id');
    if (!_byId.containsKey(entity.id)) {
      throw StateError('Task does not exist: ${entity.id}');
    }
    _byId[entity.id] = entity;
  }

  @override
  Future<bool> remove(String id) async {
    _requireId(id, 'id');
    return _byId.remove(id) != null;
  }

  @override
  Future<void> setCompleted(String id, bool isCompleted) async {
    _requireId(id, 'id');
    final current = _byId[id];
    if (current == null) {
      throw StateError('Task does not exist: $id');
    }
    if (current.isCompleted == isCompleted) {
      return;
    }
    _byId[id] = current.copyWith(isCompleted: isCompleted);
  }
}

void _requireId(String id, String field) {
  if (id.trim().isEmpty) {
    throw ArgumentError.value(id, field, 'must not be empty');
  }
}
