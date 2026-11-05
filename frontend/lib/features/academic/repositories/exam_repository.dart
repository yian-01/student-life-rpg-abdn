import '../../../app/data/campus_store.dart';
import '../../../shared/repositories/entity_repository.dart';
import '../models/exam.dart';

/// 考试仓库。
///
/// 正式应用由组合根注入持久化实现。
abstract interface class ExamRepository implements EntityRepository<Exam> {
  /// 该课程下的考试，按 [Exam.range] 起点升序。
  Future<List<Exam>> listForCourse(String courseId);
}

/// 内存实现，用于界面联调与单元测试。
///
/// 明确标注：**不落盘**，进程结束后数据丢失。正式演示前必须替换为
/// 共享持久化实现（#30），不得把本实现当作持久化证据。
class InMemoryExamRepository implements ExamRepository {
  final Map<String, Exam> _byId = <String, Exam>{};

  @override
  Future<List<Exam>> list() async => List<Exam>.unmodifiable(_byId.values);

  @override
  Future<Exam?> getById(String id) async {
    _validateId(id);
    return _byId[id];
  }

  @override
  Future<void> insert(Exam entity) async {
    _validateId(entity.id);
    if (_byId.containsKey(entity.id)) {
      throw StateError('Exam "${entity.id}" already exists.');
    }
    _byId[entity.id] = entity;
  }

  @override
  Future<void> update(Exam entity) async {
    _validateId(entity.id);
    if (!_byId.containsKey(entity.id)) {
      throw StateError('Exam "${entity.id}" does not exist.');
    }
    _byId[entity.id] = entity;
  }

  @override
  Future<bool> remove(String id) async {
    _validateId(id);
    return _byId.remove(id) != null;
  }

  @override
  Future<List<Exam>> listForCourse(String courseId) async {
    _validateId(courseId);
    final rows = _byId.values.where((row) => row.courseId == courseId).toList()
      ..sort((a, b) => a.range.start.compareTo(b.range.start));
    return List<Exam>.unmodifiable(rows);
  }

  void _validateId(String id) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be blank.');
    }
  }
}

/// Persistent implementation shared by application pages and services.
class StoredExamRepository extends CampusRepository<Exam>
    implements ExamRepository {
  StoredExamRepository(CampusStore store)
    : super(store, 'exams', Exam.fromJson, (v) => v.toJson());
  @override
  Future<List<Exam>> listForCourse(String courseId) async {
    if (courseId.trim().isEmpty) {
      throw ArgumentError.value(courseId, 'courseId');
    }
    final rows =
        (await list()).where((row) => row.courseId == courseId).toList()
          ..sort((a, b) {
            final byTime = a.range.start.compareTo(b.range.start);
            return byTime != 0 ? byTime : a.id.compareTo(b.id);
          });
    return List.unmodifiable(rows);
  }
}
