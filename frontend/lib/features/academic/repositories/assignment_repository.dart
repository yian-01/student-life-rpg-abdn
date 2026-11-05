import '../../../app/data/campus_store.dart';
import '../models/assignment.dart';

/// 作业仓库（持久化契约 v2 的 assignments 表）。
///
/// 引用保护由 CampusStore 全量校验保证：`courseId` 必须引用已存在课程；
/// 删除仍被作业/考试引用的课程会被拒绝（StateError）。
class AssignmentRepository extends CampusRepository<Assignment> {
  AssignmentRepository(CampusStore store)
    : super(store, 'assignments', Assignment.fromJson, (v) => v.toJson());

  /// 返回指定课程的作业，按 `dueAt` 升序（截止时间早的在前）。
  ///
  /// 排序放在仓库层：多个消费方都需要同一顺序，避免各自实现导致展示不一致。
  /// `dueAt` 在模型中非空，因此无需处理“无截止时间”的边界。
  Future<List<Assignment>> listForCourse(String courseId) async {
    final items = (await list()).where((a) => a.courseId == courseId).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return List.unmodifiable(items);
  }
}
