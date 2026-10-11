import '../../../shared/repositories/entity_repository.dart';
import '../models/event.dart';

/// 内存版事件仓库：用于开发与单元测试；应用退出后数据不保留。
class InMemoryEventRepository implements EntityRepository<Event> {
  final Map<String, Event> _byId = <String, Event>{};

  @override
  Future<List<Event>> list() async {
    return List<Event>.unmodifiable(_byId.values.toList(growable: false));
  }

  @override
  Future<Event?> getById(String id) async {
    _requireId(id, 'id');
    return _byId[id];
  }

  @override
  Future<void> insert(Event entity) async {
    _requireId(entity.id, 'entity.id');
    if (_byId.containsKey(entity.id)) {
      throw StateError('Event already exists: ${entity.id}');
    }
    _byId[entity.id] = entity;
  }

  @override
  Future<void> update(Event entity) async {
    _requireId(entity.id, 'entity.id');
    if (!_byId.containsKey(entity.id)) {
      throw StateError('Event does not exist: ${entity.id}');
    }
    _byId[entity.id] = entity;
  }

  @override
  Future<bool> remove(String id) async {
    _requireId(id, 'id');
    return _byId.remove(id) != null;
  }
}

void _requireId(String id, String field) {
  if (id.trim().isEmpty) {
    throw ArgumentError.value(id, field, 'must not be empty');
  }
}
