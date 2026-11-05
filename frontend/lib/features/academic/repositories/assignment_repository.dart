import '../../../app/data/campus_store.dart';
import '../../../shared/repositories/entity_repository.dart';
import '../models/assignment.dart';

/// 作业仓库。
///
/// 正式应用由组合根注入持久化实现，
/// 业务代码只依赖本接口，不直接读写文件或 CampusStore。
abstract interface class AssignmentRepository
    implements EntityRepository<Assignment> {
  /// 该课程下的作业，按 [Assignment.dueAt] 升序。
  Future<List<Assignment>> listForCourse(String courseId);
}

/// 内存实现，用于界面联调与单元测试。
///
/// 明确标注：**不落盘**，进程结束后数据丢失。正式演示前必须替换为
/// 共享持久化实现（#30），不得把本实现当作持久化证据。
class InMemoryAssignmentRepository implements AssignmentRepository {
  final Map<String, Assignment> _byId = <String, Assignment>{};

  @override
  Future<List<Assignment>> list() async =>
      List<Assignment>.unmodifiable(_byId.values);

  @override
  Future<Assignment?> getById(String id) async {
    _validateId(id);
    return _byId[id];
  }

  @override
  Future<void> insert(Assignment entity) async {
    _validateId(entity.id);
    if (_byId.containsKey(entity.id)) {
      throw StateError('Assignment "${entity.id}" already exists.');
    }
    _byId[entity.id] = entity;
  }

  @override
  Future<void> update(Assignment entity) async {
    _validateId(entity.id);
    if (!_byId.containsKey(entity.id)) {
      throw StateError('Assignment "${entity.id}" does not exist.');
    }
    _byId[entity.id] = entity;
  }

  @override
  Future<bool> remove(String id) async {
    _validateId(id);
    return _byId.remove(id) != null;
  }

  @override
  Future<List<Assignment>> listForCourse(String courseId) async {
    _validateId(courseId);
    final rows = _byId.values.where((row) => row.courseId == courseId).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return List<Assignment>.unmodifiable(rows);
  }

  void _validateId(String id) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be blank.');
    }
  }
}

/// Persistent implementation shared by application pages and services.
class StoredAssignmentRepository extends CampusRepository<Assignment> implements AssignmentRepository {
  StoredAssignmentRepository(CampusStore store) : super(store, 'assignments', Assignment.fromJson, (v) => v.toJson());
  @override
  Future<List<Assignment>> listForCourse(String courseId) async {
    if (courseId.trim().isEmpty) throw ArgumentError.value(courseId, 'courseId');
    final rows = (await list()).where((row) => row.courseId == courseId).toList()
      ..sort((a,b) { final byTime = a.dueAt.compareTo(b.dueAt); return byTime != 0 ? byTime : a.id.compareTo(b.id); });
    return List.unmodifiable(rows);
  }
}
