import '../models/course.dart';
import '../models/course_slot.dart';
import 'period_time_table.dart';

/// 课程性质标记：`*` 理论、`&` 实验、`#` 实践。
enum CourseNature { theory, lab, practice }

/// 从课表文本中解析出的一个上课时段。
class ParsedSlot {
  const ParsedSlot({
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    required this.weeks,
    this.location,
  });

  final int weekday;
  final int startMinute;
  final int endMinute;
  final List<int> weeks;

  /// 上课地点。当前冻结的 [CourseSlot] 没有地点字段，仅用于预览展示。
  final String? location;
}

/// 从课表文本中解析出的一门课程。
class ParsedCourse {
  ParsedCourse({
    required this.name,
    required this.classCode,
    required this.slots,
    this.credits,
    this.teacher,
    this.adjusted = false,
  });

  /// 课程名（已去掉 `*`/`&`/`#` 与 `【调】`）。
  final String name;

  /// 教学班标识；实验班（末尾 A）与理论班共用同一个键。
  final String classCode;

  final List<ParsedSlot> slots;

  /// 学分；教务系统未给出时为 null（**不默填 1**）。
  final double? credits;

  final String? teacher;

  /// 是否带 `【调】` 调课标记。
  final bool adjusted;
}

/// 解析过程中发现的问题，用于在预览页提示，不吞掉。
class TimetableIssue {
  const TimetableIssue(this.line, this.message);
  final int line;
  final String message;

  @override
  String toString() => '第 $line 行：$message';
}

class TimetableParseResult {
  const TimetableParseResult({required this.courses, required this.issues});
  final List<ParsedCourse> courses;
  final List<TimetableIssue> issues;
}

// 课程行里的字段标签。注意原始数据里 `校区:` 用半角冒号、
// `教师 ：` 在冒号前有空格，照原样匹配。
const _fieldLabels = <String>[
  '周数：',
  '校区:',
  '上课地点：',
  '教师 ：',
  '教学班：',
  '教学班组成：',
  '考核方式：',
  '选课备注：',
  '课程学时组成：',
  '周学时：',
  '总学时：',
  '学分：',
];

final _labelPattern = RegExp(
  '(?:${_fieldLabels.map(RegExp.escape).join('|')})',
);

final _weekdayPattern = RegExp(r'^星期([一二三四五六日天])$');
final _periodRangePattern = RegExp(r'^(\d{1,2})\s*[-–]\s*(\d{1,2})$');
const _weekdayMap = <String, int>{
  '一': 1,
  '二': 2,
  '三': 3,
  '四': 4,
  '五': 5,
  '六': 6,
  '日': 7,
  '天': 7,
};

/// 解析从教务系统课表页面复制出来的文本。
///
/// 只做"文本 → 领域对象"的映射，不写盘、不访问网络。
/// 节次到时刻的换算依赖 [periods]，未定义的节次会记入 [issues] 而不是猜测。
TimetableParseResult parseTimetableText(
  String text, {
  PeriodTimeTable periods = PeriodTimeTable.scnuNanhai,
}) {
  final issues = <TimetableIssue>[];
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');

  // 先收集"其他课程"表格（无固定上课时间的课程）。
  final otherCourses = <ParsedCourse>[];
  var otherHeader = -1;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].contains('课程名称') && lines[i].contains('学分')) {
      otherHeader = i;
      break;
    }
  }
  if (otherHeader >= 0) {
    for (var i = otherHeader + 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) break;
      final cells = line.split('\t');
      if (cells.length < 4) break;
      final name = cells[0].trim();
      if (name.isEmpty) break;
      final credits = double.tryParse(cells[2].trim());
      if (credits == null) {
        issues.add(TimetableIssue(i + 1, '其他课程「$name」缺少可解析的学分，已跳过'));
        continue;
      }
      otherCourses.add(
        ParsedCourse(
          name: name,
          classCode: 'other:$name',
          slots: const [],
          credits: credits,
          teacher: cells[1].trim().isEmpty ? null : cells[1].trim(),
        ),
      );
      if (cells.length > 4 && cells[4].trim().isEmpty) {
        issues.add(TimetableIssue(i + 1, '其他课程「$name」没有固定上课时间，仅导入学分'));
      }
    }
  }

  // 主课表：星期 → 节次 → 课程行。
  final rows = <_RawRow>[];
  var weekday = 0;
  var periodFrom = 0;
  var periodTo = 0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;

    final dayMatch = _weekdayPattern.firstMatch(line);
    if (dayMatch != null) {
      weekday = _weekdayMap[dayMatch.group(1)!]!;
      continue;
    }
    final periodMatch = _periodRangePattern.firstMatch(line);
    if (periodMatch != null) {
      periodFrom = int.parse(periodMatch.group(1)!);
      periodTo = int.parse(periodMatch.group(2)!);
      continue;
    }
    if (!line.contains('学分：') || !line.contains('周数：')) continue;
    if (weekday == 0 || periodFrom == 0) {
      issues.add(TimetableIssue(i + 1, '课程行缺少星期或节次上下文，已跳过'));
      continue;
    }

    final parsed = _parseCourseLine(line);
    if (parsed == null) {
      issues.add(TimetableIssue(i + 1, '无法识别这一行的课程信息，已跳过'));
      continue;
    }
    final weeks = _parseWeeks(parsed.weeksText);
    if (weeks.isEmpty) {
      issues.add(
        TimetableIssue(i + 1, '「${parsed.name}」的周数无法解析：${parsed.weeksText}'),
      );
      continue;
    }
    final range = periods.rangeFor(periodFrom, periodTo);
    if (range == null) {
      issues.add(
        TimetableIssue(
          i + 1,
          '「${parsed.name}」的节次 $periodFrom-$periodTo 不在节次时刻表内，已跳过',
        ),
      );
      continue;
    }

    rows.add(
      _RawRow(
        weekday: weekday,
        startMinute: range.$1,
        endMinute: range.$2,
        weeks: weeks,
        name: parsed.name,
        nature: parsed.nature,
        classCode: parsed.classCode,
        credits: parsed.credits,
        teacher: parsed.teacher,
        location: parsed.location,
        adjusted: parsed.adjusted,
      ),
    );
  }

  final courses = _groupCourses(rows);
  // 其他课程若未在主课表出现，则作为独立课程加入。
  final names = courses.map((course) => course.name).toSet();
  for (final other in otherCourses) {
    if (names.contains(other.name)) continue;
    courses.add(other);
  }
  return TimetableParseResult(courses: courses, issues: issues);
}

class _RawRow {
  const _RawRow({
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    required this.weeks,
    required this.name,
    required this.nature,
    required this.classCode,
    required this.credits,
    required this.teacher,
    required this.location,
    required this.adjusted,
  });

  final int weekday;
  final int startMinute;
  final int endMinute;
  final List<int> weeks;
  final String name;
  final CourseNature nature;
  final String classCode;
  final double? credits;
  final String? teacher;
  final String? location;
  final bool adjusted;
}

class _CourseLine {
  const _CourseLine({
    required this.name,
    required this.nature,
    required this.classCode,
    required this.weeksText,
    required this.credits,
    required this.teacher,
    required this.location,
    required this.adjusted,
  });

  final String name;
  final CourseNature nature;
  final String classCode;
  final String weeksText;
  final double? credits;
  final String? teacher;
  final String? location;
  final bool adjusted;
}

_CourseLine? _parseCourseLine(String line) {
  final matches = _labelPattern.allMatches(line).toList();
  if (matches.isEmpty) return null;

  final head = line.substring(0, matches.first.start).trim();
  final fields = <String, String>{};
  for (var i = 0; i < matches.length; i++) {
    final label = matches[i].group(0)!;
    final start = matches[i].end;
    final end = i + 1 < matches.length ? matches[i + 1].start : line.length;
    fields[label] = line.substring(start, end).trim();
  }

  var adjusted = false;
  var title = head;
  if (title.startsWith('【调】')) {
    adjusted = true;
    title = title.substring(3).trim();
  }
  if (title.isEmpty) return null;

  var nature = CourseNature.theory;
  final last = title[title.length - 1];
  if (last == '*') {
    nature = CourseNature.theory;
    title = title.substring(0, title.length - 1).trim();
  } else if (last == '&') {
    nature = CourseNature.lab;
    title = title.substring(0, title.length - 1).trim();
  } else if (last == '#') {
    nature = CourseNature.practice;
    title = title.substring(0, title.length - 1).trim();
  }
  if (title.isEmpty) return null;

  final classCode = _baseClassCode(fields['教学班：'] ?? '');
  final weeksText = fields['周数：'] ?? '';
  final credits = double.tryParse((fields['学分：'] ?? '').trim());
  final location = fields['上课地点：']?.trim();
  final teacher = fields['教师 ：']?.trim();

  return _CourseLine(
    name: title,
    nature: nature,
    classCode: classCode.isEmpty ? 'name:$title' : classCode,
    weeksText: weeksText,
    credits: credits,
    teacher: teacher == null || teacher.isEmpty ? null : teacher,
    location: location == null || location.isEmpty ? null : location,
    adjusted: adjusted,
  );
}

/// 实验班的教学班号比理论班多一个结尾 `A`（如 `...-CS0202A`），
/// 归一到基号后，理论课与实验课会合并为同一门课程，避免学分重复计算。
String _baseClassCode(String raw) {
  final code = raw.trim();
  if (code.length < 2) return code;
  if (!code.endsWith('A')) return code;
  final beforeA = code[code.length - 2];
  if (beforeA.codeUnitAt(0) >= 0x30 && beforeA.codeUnitAt(0) <= 0x39) {
    return code.substring(0, code.length - 1);
  }
  return code;
}

/// 解析周数文本：`1-16周`、`1-4周,6-12周`、`4周,8周,12周`。
List<int> _parseWeeks(String text) {
  final weeks = <int>{};
  for (final rawPart in text.split(',')) {
    final part = rawPart.trim();
    if (part.isEmpty) continue;
    final single = RegExp(r'^(\d{1,3})周(?:\((单|双)\))?$').firstMatch(part);
    if (single != null) {
      weeks.add(int.parse(single.group(1)!));
      continue;
    }
    final range = RegExp(
      r'^(\d{1,3})\s*[-–]\s*(\d{1,3})周(?:\((单|双)\))?$',
    ).firstMatch(part);
    if (range == null) return const [];
    final from = int.parse(range.group(1)!);
    final to = int.parse(range.group(2)!);
    if (from > to) return const [];
    final parity = range.group(3);
    for (var week = from; week <= to; week++) {
      if (parity == '单' && week.isEven) continue;
      if (parity == '双' && week.isOdd) continue;
      weeks.add(week);
    }
  }
  final sorted = weeks.toList()..sort();
  return sorted;
}

/// 按教学班基号分组；同一门课同一时段的多个记录（如调课换地点）
/// 合并周次，因为冻结模型 [CourseSlot] 不保存地点。
List<ParsedCourse> _groupCourses(List<_RawRow> rows) {
  final byKey = <String, List<_RawRow>>{};
  for (final row in rows) {
    byKey.putIfAbsent(row.classCode, () => <_RawRow>[]).add(row);
  }

  final courses = <ParsedCourse>[];
  for (final entry in byKey.entries) {
    final group = entry.value;
    final slotWeeks = <String, Set<int>>{};
    final slotMeta = <String, _RawRow>{};
    for (final row in group) {
      final key = '${row.weekday}:${row.startMinute}:${row.endMinute}';
      slotWeeks.putIfAbsent(key, () => <int>{}).addAll(row.weeks);
      slotMeta.putIfAbsent(key, () => row);
    }
    final slots = <ParsedSlot>[];
    for (final key in slotMeta.keys) {
      final meta = slotMeta[key]!;
      final weeks = slotWeeks[key]!.toList()..sort();
      slots.add(
        ParsedSlot(
          weekday: meta.weekday,
          startMinute: meta.startMinute,
          endMinute: meta.endMinute,
          weeks: weeks,
          location: meta.location,
        ),
      );
    }
    slots.sort((a, b) {
      final day = a.weekday.compareTo(b.weekday);
      if (day != 0) return day;
      return a.startMinute.compareTo(b.startMinute);
    });

    final credits = group
        .map((row) => row.credits)
        .firstWhere((value) => value != null, orElse: () => null);
    final teacher = group
        .map((row) => row.teacher)
        .firstWhere((value) => value != null, orElse: () => null);
    courses.add(
      ParsedCourse(
        name: group.first.name,
        classCode: entry.key,
        slots: slots,
        credits: credits,
        teacher: teacher,
        adjusted: group.any((row) => row.adjusted),
      ),
    );
  }

  // 理论课优先作为课程名代表：同名时把实验/实践的同班合并已由基号完成，
  // 这里只保证输出顺序稳定（按首次出现顺序）。
  return courses;
}

/// 把解析结果写成 [Course]，用于导入落库。
///
/// [creditsFallback] 为 null 时，缺学分的课程会返回 null 表示无法导入——
/// 刻意不默填 1 学分（Issue #31 要求）。
List<Course> toCourses({
  required List<ParsedCourse> parsed,
  required String semesterId,
  required double scoreScaleMax,
  String idPrefix = 'imported',
}) {
  final courses = <Course>[];
  for (var i = 0; i < parsed.length; i++) {
    final item = parsed[i];
    final credits = item.credits;
    if (credits == null) continue;
    final slots = [
      for (final slot in item.slots)
        CourseSlot(
          weekday: slot.weekday,
          startMinute: slot.startMinute,
          endMinute: slot.endMinute,
          weeks: slot.weeks,
        ),
    ];
    courses.add(
      Course(
        id: '$idPrefix-${i + 1}-${item.classCode.hashCode.abs()}',
        semesterId: semesterId,
        name: item.name,
        credits: credits,
        gradePoint: null,
        slots: slots,
        scoreScaleMax: scoreScaleMax,
      ),
    );
  }
  return courses;
}
