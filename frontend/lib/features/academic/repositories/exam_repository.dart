import '../../../app/data/campus_store.dart';
import '../models/exam.dart';

/// 考试仓库（持久化契约 v2 的 exams 表）。
///
/// 引用保护由 CampusStore 全量校验保证：`courseId` 必须引用已存在课程；
/// 删除仍被作业/考试引用的课程会被拒绝（StateError）。
class ExamRepository extends CampusRepository<Exam> {
  ExamRepository(CampusStore store)
    : super(store, 'exams', Exam.fromJson, (v) => v.toJson());

  /// 返回指定课程的考试，按插入顺序。
  Future<List<Exam>> listForCourse(String courseId) async =>
      List.unmodifiable((await list()).where((e) => e.courseId == courseId));
}
