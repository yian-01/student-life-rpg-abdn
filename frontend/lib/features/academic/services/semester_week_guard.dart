import '../models/course.dart';
import '../models/semester.dart';

/// 返回在 [semester] 合法周次范围之外仍有上课时段的课程名称。
///
/// 用于"缩短学期""改第 1 周锚点""把课程换到更短的学期"这类变更前的校验：
/// 只要有任何课程时段的周次超过 [Semester.lastValidWeek]，就把课程报告出来，
/// 由调用方阻止保存。这里**不修改、不截断、不删除**任何数据。
///
/// 只统计 `semesterId == semester.id` 的课程；返回值保持传入顺序，便于点名。
List<String> coursesOutsideSemesterWeeks(
  Semester semester,
  Iterable<Course> courses,
) {
  final maxWeek = semester.lastValidWeek;
  final affected = <String>[];
  for (final course in courses) {
    if (course.semesterId != semester.id) {
      continue;
    }
    final outOfRange = course.slots.any(
      (slot) => slot.weeks.any((week) => week > maxWeek),
    );
    if (outOfRange) {
      affected.add(course.name);
    }
  }
  return affected;
}
