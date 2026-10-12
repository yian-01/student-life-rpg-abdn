/// 学术模块的日期解析与格式化工具。
///
/// 契约第 4.1 节规定：日期字段在 Dart 中使用本地午夜 [DateTime]，
/// 在 JSON 中使用 `YYYY-MM-DD`。解码必须拒绝非法日期以及会被
/// [DateTime] 自动归一化的输入，例如 `2026-02-29`、`2026-10-32`。
///
/// 本文件只依赖 dart:core，便于独立分析和测试。
library;

/// `YYYY-MM-DD` 形式的严格日期字符串。
final RegExp _datePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// 把本地午夜 [DateTime] 格式化为 `YYYY-MM-DD`。
///
/// 传入值必须是本地时间且时间部分为零；否则抛出 [ArgumentError]。
String formatLocalDate(DateTime value) {
  if (value.isUtc) {
    throw ArgumentError.value(value, 'value', 'Must be a local DateTime.');
  }
  if (value.hour != 0 ||
      value.minute != 0 ||
      value.second != 0 ||
      value.millisecond != 0 ||
      value.microsecond != 0) {
    throw ArgumentError.value(
      value,
      'value',
      'Date fields must be local midnight.',
    );
  }
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

/// 解析 `YYYY-MM-DD` 为本地午夜 [DateTime]。
///
/// 非法格式、非法日历日期或 UTC 输入抛出 [FormatException]。
DateTime parseLocalDate(Object? value, {String field = 'date'}) {
  if (value is! String) {
    throw FormatException('$field must be a YYYY-MM-DD string.');
  }
  final match = _datePattern.firstMatch(value);
  if (match == null) {
    throw FormatException('$field must use the YYYY-MM-DD format: $value');
  }

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);

  final DateTime parsed;
  try {
    parsed = DateTime(year, month, day);
  } on Object {
    throw FormatException('$field is not a valid calendar date: $value');
  }

  // DateTime 会把 2026-02-29 归一化成 2026-03-01，这里逐字段比对拒绝它。
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    throw FormatException('$field is not a valid calendar date: $value');
  }
  return parsed;
}

/// 本地 ISO 时间字符串，不含 `Z` 或时区偏移，秒为必填，小数最多 6 位。
///
/// 与公共 `TimeRange` 使用的规则保持一致。
final RegExp _localTimePattern = RegExp(
  r'^([+-]\d{6}|\d{4})-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?$',
);

/// 解析本地 ISO 时间为 [DateTime]。
///
/// 契约第 4.1 节：JSON 使用本地 ISO 格式，不含 `Z` 或时区偏移，
/// 保留秒、毫秒和微秒精度，并拒绝 `2026-02-29`、`24:00:00`、
/// 分钟 60 这类会被 [DateTime] 自动归一化的非法输入。
DateTime parseLocalDateTime(Object? value, {String field = 'time'}) {
  if (value is! String || !_localTimePattern.hasMatch(value)) {
    throw FormatException(
      '$field must be a local ISO time without timezone: $value',
    );
  }

  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      parsed.isUtc ||
      _withMicroseconds(parsed.toIso8601String()) != _withMicroseconds(value)) {
    throw FormatException('$field is not a valid local calendar time: $value');
  }
  return parsed;
}

/// 把 ISO 字符串的小数部分补齐为 6 位，用于比对自动归一化。
String _withMicroseconds(String value) {
  final parts = value.split('.');
  final fraction = parts.length == 2 ? parts[1] : '';
  return '${parts[0]}.${fraction.padRight(6, '0')}';
}

/// 断言 [value] 为本地午夜日期，否则抛出 [ArgumentError]。
///
/// 用于模型构造器，保证构造->JSON->构造往返不丢时间信息。
void validateLocalMidnight(DateTime value, String name) {
  if (value.year < 0 || value.year > 9999) {
    throw ArgumentError.value(value, name, 'Year must fit YYYY-MM-DD.');
  }
  if (value.isUtc) {
    throw ArgumentError.value(value, name, 'Must be a local DateTime.');
  }
  if (value.hour != 0 ||
      value.minute != 0 ||
      value.second != 0 ||
      value.millisecond != 0 ||
      value.microsecond != 0) {
    throw ArgumentError.value(value, name, 'Must be local midnight.');
  }
}
