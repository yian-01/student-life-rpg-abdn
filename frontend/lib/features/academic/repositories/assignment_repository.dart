import '../../../app/data/campus_store.dart';
import '../../../shared/repositories/entity_repository.dart';
import '../models/assignment.dart';

/// 作业仓库。
///
/// 正式应用由组合根注入持久化实现（`StoredAssignmentRepository`），
/// 业务代码只依赖本接口，不直接读写文件或 CampusStore。
abstract interface class AssignmentRepository
    implements EntityRepository<Assignment> {
  /// 该课程下的作业，按 [Assignment.dueAt] 升序（同时间按 id 稳定排序）。
  Future<List<Assignment>> listForCourse(String courseId);
}

/// Persistent implementation shared by application pages and services.
class StoredAssignmentRepository extends CampusRepository<Assignment>
    implements AssignmentRepository {
  StoredAssignmentRepository(CampusStore store)
    : super(store, 'assignments', Assignment.fromJson, (v) => v.toJson());
  @override
  Future<List<Assignment>> listForCourse(String courseId) async {
    if (courseId.trim().isEmpty) {
      throw ArgumentError.value(courseId, 'courseId');
    }
    final rows =
        (await list()).where((row) => row.courseId == courseId).toList()
          ..sort((a, b) {
            final byTime = a.dueAt.compareTo(b.dueAt);
            return byTime != 0 ? byTime : a.id.compareTo(b.id);
          });
    return List.unmodifiable(rows);
  }
}
