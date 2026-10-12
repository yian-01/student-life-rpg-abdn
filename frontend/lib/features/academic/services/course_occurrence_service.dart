import '../../../../shared/models/schedule_item.dart';
import '../../../../shared/models/time_range.dart';
import '../models/course.dart';
import '../models/semester.dart';

/// 把课程在 [date] 当天的所有课次展开为展示用 [ScheduleItem]。
///
/// 契约第 5 节行为：
/// - 输入日期归一到本地日期。
/// - `course.semesterId` 与 `semester.id` 不一致时拒绝（抛 [ArgumentError]）。
/// - 日期在学期外、星期不匹配、周次不在 `slot.weeks` 时返回空列表。
/// - 根据日期与 `week1Monday` 的日历差计算周次，不使用 UTC 秒差。
/// - 0 分钟合法；1440 分钟表示次日 00:00。
/// - 输出 `sourceType = course`，`sourceId` 保留课程原始 ID。
/// - ID 格式为 `course:<Uri.encodeComponent(courseId)>:<slotIndex>:YYYYMMDD`。
/// - `slotIndex` 使用课程 `slots` 列表中的索引，因此 slots 变更后可重新生成。
/// - 不修改输入。
List<ScheduleItem> occurrencesForDate(
  Course course,
  Semester semester,
  DateTime date,
) {
  if (date.isUtc) {
    throw ArgumentError.value(date, 'date', 'Must be local time.');
  }
  if (course.semesterId != semester.id) {
    throw ArgumentError.value(
      course.semesterId,
      'course.semesterId',
      'Must match semester.id "${semester.id}".',
    );
  }

  // 归一本地日期，忽略传入值的时间部分。
  final day = DateTime(date.year, date.month, date.day);
  if (!semester.containsDate(day)) {
    return const <ScheduleItem>[];
  }

  final weekNumber = _weekNumberFor(semester.week1Monday, day);
  if (weekNumber == null || weekNumber < 1) {
    return const <ScheduleItem>[];
  }

  final dayStart = day;
  final dateToken = _dateToken(day);
  final encodedCourseId = Uri.encodeComponent(course.id);

  final items = <ScheduleItem>[];
  for (var slotIndex = 0; slotIndex < course.slots.length; slotIndex++) {
    final slot = course.slots[slotIndex];
    if (slot.weekday != day.weekday) {
      continue;
    }
    // weeks 严格递增，contains 足够；保持 O(n) 不引入额外结构。
    if (!slot.weeks.contains(weekNumber)) {
      continue;
    }

    final range = TimeRange(
      start: DateTime(
        dayStart.year,
        dayStart.month,
        dayStart.day,
        slot.startMinute ~/ 60,
        slot.startMinute % 60,
      ),
      end: DateTime(
        dayStart.year,
        dayStart.month,
        dayStart.day,
        slot.endMinute ~/ 60,
        slot.endMinute % 60,
      ),
    );
    items.add(
      ScheduleItem(
        id: 'course:$encodedCourseId:$slotIndex:$dateToken',
        sourceId: course.id,
        sourceType: ScheduleSourceType.course,
        title: course.name,
        range: range,
      ),
    );
  }
  return List<ScheduleItem>.unmodifiable(items);
}

/// 计算 [date] 相对 [week1Monday] 的周次，第一周为 1。
///
/// 使用日历差而非 UTC 秒差，避免夏令时/时区偏移影响周次。
int? _weekNumberFor(DateTime week1Monday, DateTime date) {
  // Gregorian day ordinals count civil dates independently of timezone/DST.
  final days = _dayOrdinal(date) - _dayOrdinal(week1Monday);
  if (days < 0) {
    return null;
  }
  return days ~/ 7 + 1;
}

int _dayOrdinal(DateTime date) {
  final year = date.year - (date.month <= 2 ? 1 : 0);
  final era = (year / 400).floor();
  final yearOfEra = year - era * 400;
  final month = date.month + (date.month > 2 ? -3 : 9);
  return era * 146097 +
      yearOfEra * 365 +
      yearOfEra ~/ 4 -
      yearOfEra ~/ 100 +
      (153 * month + 2) ~/ 5 +
      date.day -
      1;
}

/// `YYYYMMDD` 日期片段，用于派生课次 ID。
String _dateToken(DateTime day) {
  final year = day.year.toString().padLeft(4, '0');
  final month = day.month.toString().padLeft(2, '0');
  final dayOfMonth = day.day.toString().padLeft(2, '0');
  return '$year$month$dayOfMonth';
}
