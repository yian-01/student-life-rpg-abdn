import '../../../../shared/repositories/entity_repository.dart';
import '../models/semester.dart';

/// 学期仓库：在公共 [EntityRepository] 语义上增加课程引用保护。
///
/// 契约第 5 节：创建 Course 时 `semesterId` 必须引用已存在学期；
/// 有课程引用的学期禁止删除（删除保护由 [StateError] 表达）。
abstract interface class SemesterRepository
    implements EntityRepository<Semester> {
  /// 学期是否存在，供课程仓库做引用校验。
  Future<bool> exists(String id);
}

/// 内存学期仓库。
///
/// 行为遵循公共契约：
/// - `list` 返回不可变副本。
/// - `getById` 不存在返回 null。
/// - `insert` 重复 ID 抛 [StateError]。
/// - `update` 未知 ID 抛 [StateError]。
/// - `remove` 未知 ID 返回 false，被课程引用时抛 [StateError]。
/// - ID 参数空白抛 [ArgumentError]；ID 保留原值，不做 trim。
class InMemorySemesterRepository implements SemesterRepository {
  InMemorySemesterRepository({required this.isReferenced});

  /// 引用检查回调，由组合根注入课程仓库的查询。
  ///
  /// 必须显式注入，生产构造不能跳过引用保护。
  final Future<bool> Function(String semesterId) isReferenced;

  final Map<String, Semester> _byId = <String, Semester>{};

  @override
  Future<List<Semester>> list() async =>
      List<Semester>.unmodifiable(_byId.values);

  @override
  Future<Semester?> getById(String id) async {
    _validateId(id);
    return _byId[id];
  }

  @override
  Future<bool> exists(String id) async {
    _validateId(id);
    return _byId.containsKey(id);
  }

  @override
  Future<void> insert(Semester entity) async {
    _validateId(entity.id);
    if (_byId.containsKey(entity.id)) {
      throw StateError('Semester "${entity.id}" already exists.');
    }
    _byId[entity.id] = entity;
  }

  @override
  Future<void> update(Semester entity) async {
    _validateId(entity.id);
    if (!_byId.containsKey(entity.id)) {
      throw StateError('Semester "${entity.id}" does not exist.');
    }
    // 实体没有 copyWith，ID 不可改：只替换同 ID 记录。
    _byId[entity.id] = entity;
  }

  @override
  Future<bool> remove(String id) async {
    _validateId(id);
    if (!_byId.containsKey(id)) {
      return false;
    }
    if (await isReferenced(id)) {
      throw StateError('Semester "$id" is referenced by existing courses.');
    }
    return _byId.remove(id) != null;
  }

  void _validateId(String id) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be blank.');
    }
  }
}
