import '../../gpa/services/scnu_timetable_reader.dart';
import 'period_time_table.dart';
import 'timetable_import.dart';

/// HTML only, no URL fetching, login or writes. Explicit semester bound required.
TimetableParseResult parseScnuHtml(
  String html, {
  required int maxWeek,
  PeriodTimeTable periods = PeriodTimeTable.scnuNanhai,
}) {
  final issues = <TimetableIssue>[];
  final rows = ScnuTimetableReader().read(
    html,
    maxWeek: maxWeek,
    periods: {
      for (final entry in periods.periods.entries)
        entry.key: (start: entry.value.$1, end: entry.value.$2),
    },
    allowOtherCoursesForPreview: true,
  );
  final groups = <String, List<ScnuTimetableRow>>{};
  final theory = {
    for (final row in rows)
      if (row.name.endsWith('*'))
        Uri.decodeComponent(row.sourceId.substring(5)): row,
  };
  for (final row in rows) {
    var code = Uri.decodeComponent(row.sourceId.substring(5));
    final name = row.name
        .replaceFirst('【调】', '')
        .replaceFirst(RegExp(r'[*&#]$'), '')
        .trim();
    // Only match an observed lab to an observed theory of the same name/credits.
    if (row.name.endsWith('&') && code.endsWith('A')) {
      final parent = theory[code.substring(0, code.length - 1)];
      if (parent != null &&
          parent.name.replaceFirst(RegExp(r'[*&#]$'), '').trim() == name &&
          parent.credits == row.credits) {
        code = code.substring(0, code.length - 1);
      }
    }
    groups.putIfAbsent(code, () => []).add(row);
  }
  final courses = <ParsedCourse>[];
  for (final group in groups.entries) {
    final first = group.value.first;
    final credits = group.value.map((r) => r.credits).toSet();
    if (credits.length > 1) {
      issues.add(TimetableIssue(0, '教学班 ${group.key} 学分不一致，需修正'));
    }
    courses.add(
      ParsedCourse(
        name: first.name
            .replaceFirst('【调】', '')
            .replaceFirst(RegExp(r'[*&#]$'), '')
            .trim(),
        classCode: group.key,
        credits: credits.length == 1 ? first.credits : null,
        teacher: group.value
            .map((r) => r.teacher)
            .whereType<String>()
            .toSet()
            .join('；'),
        adjusted: group.value.any((r) => r.name.contains('【调】')),
        slots: List.unmodifiable(
          group.value.map(
            (r) => ParsedSlot(
              weekday: r.weekday,
              startMinute: r.startMinute,
              endMinute: r.endMinute,
              weeks: r.weeks,
              location: r.location,
            ),
          ),
        ),
      ),
    );
  }
  // Source has no dependable class identity or credits for these rows.
  // Expose as issues; never silently drop or invent identity/credits.
  if (html.contains('其它课程') || html.contains('其他课程')) {
    issues.add(
      const TimetableIssue(0, '课表含无固定时段的其它课程，缺少可用的教学班标识，本次未导入，请手动添加。'),
    );
  }
  return TimetableParseResult(
    courses: List.unmodifiable(courses),
    issues: List.unmodifiable(issues),
  );
}
