import '../repositories/assignment_repository.dart';
import '../repositories/exam_repository.dart';

/// 课程被作业或考试引用时的删除保护。
///
/// 规则（#31 验收）：
/// - 任一非空 → 抛 [StateError]；
/// - **不删除任何数据**，不级联、不置空、不静默跳过；
/// - 错误信息指出具体数量，供界面直接展示原因。
///
/// 本轮不做跨文件自动级联（Issue 明确不要求）。
Future<void> ensureCourseDeletable({
  required String courseId,
  required String courseName,
  required AssignmentRepository assignments,
  required ExamRepository exams,
}) async {
  final assignmentRows = await assignments.listForCourse(courseId);
  final examRows = await exams.listForCourse(courseId);
  if (assignmentRows.isEmpty && examRows.isEmpty) {
    return;
  }

  final parts = <String>[];
  if (assignmentRows.isNotEmpty) {
    parts.add('${assignmentRows.length} 条作业');
  }
  if (examRows.isNotEmpty) {
    parts.add('${examRows.length} 场考试');
  }
  throw StateError('课程「$courseName」仍有 ${parts.join('、')}引用，请先删除相关记录。');
}
