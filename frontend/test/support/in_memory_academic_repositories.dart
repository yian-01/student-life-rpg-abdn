import 'package:student_life_rpg/features/academic/models/assignment.dart';
import 'package:student_life_rpg/features/academic/models/exam.dart';
import 'package:student_life_rpg/features/academic/repositories/assignment_repository.dart';
import 'package:student_life_rpg/features/academic/repositories/exam_repository.dart';

/// 测试专用的内存仓库。
///
/// 生产页面一律使用 `data.assignments` / `data.exams`（落盘实现）；
/// 这里只服务于不关心存储细节的单元与界面测试。
/// 明确标注：**不落盘**，进程结束后数据丢失，不能作为持久化证据。
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

/// 测试专用的内存仓库，见 [InMemoryAssignmentRepository] 的说明。
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
