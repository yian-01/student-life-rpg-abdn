import '../../../app/data/campus_store.dart';
import '../models/exam.dart';

/// 考试仓库（持久化契约 v2 的 exams 表）。
///
/// 引用保护由 CampusStore 全量校验保证：`courseId` 必须引用已存在课程；
/// 删除仍被作业/考试引用的课程会被拒绝（StateError）。
class ExamRepository extends CampusRepository<Exam> {
  ExamRepository(CampusStore store)
    : super(store, 'exams', Exam.fromJson, (v) => v.toJson());

  /// 返回指定课程的考试，按 `range.start` 升序（开始时间早的在前）。
  ///
  /// 排序放在仓库层：多个消费方都需要同一顺序，避免各自实现导致展示不一致。
  /// `range` 在模型中非空，因此无需处理“无时间”的边界。
  Future<List<Exam>> listForCourse(String courseId) async {
    final items = (await list()).where((e) => e.courseId == courseId).toList()
      ..sort((a, b) => a.range.start.compareTo(b.range.start));
    return List.unmodifiable(items);
  }
}
