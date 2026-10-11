import 'academic_json.dart';
import 'local_date.dart';

/// 学期。
///
/// 契约第 5 节字段：`String id、name；DateTime startDate、endDate、week1Monday`。
///
/// 校验规则：
/// - 起止日期包含首尾，`startDate` 不晚于 `endDate`。
/// - `week1Monday` 必须是周一，作为第一周计算锚点。
/// - 日期字段为本地午夜，JSON 使用 `YYYY-MM-DD`。
class Semester {
  Semester({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.week1Monday,
  }) {
    validateNotBlank(id, 'id');
    validateNotBlank(name, 'name');
    validateLocalMidnight(startDate, 'startDate');
    validateLocalMidnight(endDate, 'endDate');
    validateLocalMidnight(week1Monday, 'week1Monday');

    if (startDate.isAfter(endDate)) {
      throw ArgumentError.value(
        startDate,
        'startDate',
        'Must not be after endDate.',
      );
    }
    if (week1Monday.weekday != DateTime.monday) {
      throw ArgumentError.value(
        week1Monday,
        'week1Monday',
        'Must be a Monday.',
      );
    }
  }

  static const Set<String> jsonKeys = {
    'id',
    'name',
    'startDate',
    'endDate',
    'week1Monday',
  };

  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime week1Monday;

  /// 判断 [date] 是否落在学期内（包含首尾）。
  ///
  /// 只比较本地日期，忽略传入值的时间部分。
  bool containsDate(DateTime date) {
    if (date.isUtc) {
      throw ArgumentError.value(date, 'date', 'Must be local time.');
    }
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(startDate) && !day.isAfter(endDate);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'startDate': formatLocalDate(startDate),
    'endDate': formatLocalDate(endDate),
    'week1Monday': formatLocalDate(week1Monday),
  };

  factory Semester.fromJson(Map<String, dynamic> json) {
    rejectUnknownKeys(json, jsonKeys, context: 'Semester');
    final id = readRequiredString(json, 'id');
    final name = readRequiredString(json, 'name');
    final startDate = parseLocalDate(json['startDate'], field: 'startDate');
    final endDate = parseLocalDate(json['endDate'], field: 'endDate');
    final week1Monday = parseLocalDate(
      json['week1Monday'],
      field: 'week1Monday',
    );

    return decodeWithArgumentErrors(
      () => Semester(
        id: id,
        name: name,
        startDate: startDate,
        endDate: endDate,
        week1Monday: week1Monday,
      ),
    );
  }
}
