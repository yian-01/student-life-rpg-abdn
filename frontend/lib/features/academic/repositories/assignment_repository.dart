import '../../../app/data/campus_store.dart';
import '../models/assignment.dart';

/// 作业仓库（持久化契约 v2 的 assignments 表）。
///
/// 引用保护由 CampusStore 全量校验保证：`courseId` 必须引用已存在课程；
/// 删除仍被作业/考试引用的课程会被拒绝（StateError）。
class AssignmentRepository extends CampusRepository<Assignment> {
  AssignmentRepository(CampusStore store)
    : super(store, 'assignments', Assignment.fromJson, (v) => v.toJson());

  /// 返回指定课程的作业，按插入顺序。
  Future<List<Assignment>> listForCourse(String courseId) async =>
      List.unmodifiable((await list()).where((a) => a.courseId == courseId));
}
