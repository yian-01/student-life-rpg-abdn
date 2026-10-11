import 'academic_json.dart';

/// 课程的一个上课时间段。
///
/// 契约第 5 节字段：`int weekday、startMinute、endMinute；List<int> weeks`。
///
/// 校验规则：
/// - `weekday` 为 1 至 7（周一为 1，周日为 7）。
/// - `0 <= startMinute < endMinute <= 1440`。
/// - `weeks` 非空，元素为严格递增的正整数。
/// - 重复或未排序的 `weeks` 拒绝。
///
/// 分钟按当天 00:00 起算；`1440` 表示次日 00:00，是合法上界。
class CourseSlot {
  CourseSlot({
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    required List<int> weeks,
  }) : weeks = List<int>.unmodifiable(weeks) {
    if (weekday < 1 || weekday > 7) {
      throw ArgumentError.value(weekday, 'weekday', 'Must be between 1 and 7.');
    }
    if (startMinute < 0) {
      throw ArgumentError.value(
        startMinute,
        'startMinute',
        'Must not be negative.',
      );
    }
    if (endMinute > 1440) {
      throw ArgumentError.value(
        endMinute,
        'endMinute',
        'Must not be greater than 1440.',
      );
    }
    if (startMinute >= endMinute) {
      throw ArgumentError.value(
        startMinute,
        'startMinute',
        'Must be less than endMinute.',
      );
    }
    if (this.weeks.isEmpty) {
      throw ArgumentError.value(weeks, 'weeks', 'Must not be empty.');
    }
    for (var index = 0; index < this.weeks.length; index++) {
      final week = this.weeks[index];
      if (week <= 0) {
        throw ArgumentError.value(week, 'weeks', 'Must be a positive integer.');
      }
      if (index > 0 && week <= this.weeks[index - 1]) {
        throw ArgumentError.value(
          weeks,
          'weeks',
          'Must be strictly increasing without duplicates.',
        );
      }
    }
  }

  static const Set<String> jsonKeys = {
    'weekday',
    'startMinute',
    'endMinute',
    'weeks',
  };

  final int weekday;
  final int startMinute;
  final int endMinute;

  /// 该时间段生效的周次，严格递增，构造时已复制为不可变列表。
  final List<int> weeks;

  Map<String, dynamic> toJson() => {
    'weekday': weekday,
    'startMinute': startMinute,
    'endMinute': endMinute,
    'weeks': List<int>.unmodifiable(weeks),
  };

  factory CourseSlot.fromJson(Map<String, dynamic> json) {
    rejectUnknownKeys(json, jsonKeys, context: 'CourseSlot');
    final weekday = readRequiredInt(json, 'weekday');
    final startMinute = readRequiredInt(json, 'startMinute');
    final endMinute = readRequiredInt(json, 'endMinute');
    final weeks = readRequiredIntList(json, 'weeks');

    return decodeWithArgumentErrors(
      () => CourseSlot(
        weekday: weekday,
        startMinute: startMinute,
        endMinute: endMinute,
        weeks: weeks,
      ),
    );
  }
}
