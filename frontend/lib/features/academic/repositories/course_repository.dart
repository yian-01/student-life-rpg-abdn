import '../../../../shared/repositories/entity_repository.dart';
import '../models/course.dart';

/// 课程仓库。
///
/// 契约第 5 节：创建 Course 时 `semesterId` 必须引用已存在学期。
abstract interface class CourseRepository implements EntityRepository<Course> {
  /// 该学期下是否已有课程，供学期仓库做删除保护。
  Future<bool> hasCoursesForSemester(String semesterId);

  /// 返回指定学期的课程，按插入顺序。
  Future<List<Course>> listForSemester(String semesterId);
}

/// 内存课程仓库。
///
/// 行为遵循公共契约：
/// - `list` 返回不可变副本。
/// - `getById` 不存在返回 null。
/// - `insert` 重复 ID 抛 [StateError]；学期不存在抛 [StateError]。
/// - `update` 未知 ID 抛 [StateError]；不得改到不存在的学期。
/// - `remove` 未知 ID 返回 false。
/// - ID 参数空白抛 [ArgumentError]；ID 保留原值，不做 trim。
class InMemoryCourseRepository implements CourseRepository {
  InMemoryCourseRepository({required this.semesterExists});

  /// 学期存在性检查，由组合根注入学期仓库的查询。
  ///
  /// 必须显式注入，生产构造不能跳过引用校验。
  final Future<bool> Function(String semesterId) semesterExists;

  final Map<String, Course> _byId = <String, Course>{};

  @override
  Future<List<Course>> list() async => List<Course>.unmodifiable(_byId.values);

  @override
  Future<Course?> getById(String id) async {
    _validateId(id);
    return _byId[id];
  }

  @override
  Future<void> insert(Course entity) async {
    _validateId(entity.id);
    if (_byId.containsKey(entity.id)) {
      throw StateError('Course "${entity.id}" already exists.');
    }
    await _requireSemester(entity.semesterId);
    if (_byId.containsKey(entity.id)) {
      throw StateError('Course "${entity.id}" already exists.');
    }
    _byId[entity.id] = entity;
  }

  @override
  Future<void> update(Course entity) async {
    _validateId(entity.id);
    if (!_byId.containsKey(entity.id)) {
      throw StateError('Course "${entity.id}" does not exist.');
    }
    await _requireSemester(entity.semesterId);
    if (!_byId.containsKey(entity.id)) {
      throw StateError('Course "${entity.id}" does not exist.');
    }
    // 实体没有 copyWith，ID 不可改：只替换同 ID 记录。
    _byId[entity.id] = entity;
  }

  @override
  Future<bool> remove(String id) async {
    _validateId(id);
    return _byId.remove(id) != null;
  }

  @override
  Future<bool> hasCoursesForSemester(String semesterId) async {
    _validateId(semesterId);
    return _byId.values.any((course) => course.semesterId == semesterId);
  }

  @override
  Future<List<Course>> listForSemester(String semesterId) async {
    _validateId(semesterId);
    return List<Course>.unmodifiable(
      _byId.values.where((course) => course.semesterId == semesterId),
    );
  }

  Future<void> _requireSemester(String semesterId) async {
    if (!await semesterExists(semesterId)) {
      throw StateError('Semester "$semesterId" does not exist.');
    }
  }

  void _validateId(String id) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be blank.');
    }
  }
}
