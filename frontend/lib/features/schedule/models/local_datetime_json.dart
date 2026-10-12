import '../../../shared/models/time_range.dart';

final RegExp _localIsoPattern = RegExp(
  r'^([+-]\d{6}|\d{4})-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?$',
);

/// 把本地民用时间编码为无 `Z`、无偏移的 ISO-8601 字符串。
///
/// 传入 UTC 时间抛出 [ArgumentError]，避免把时区语义悄悄写进 JSON。
String encodeLocalDateTime(DateTime value, String field) {
  if (value.isUtc) {
    throw ArgumentError.value(value, field, 'must be local civil time');
  }
  return value.toIso8601String();
}

/// 解析本地 ISO-8601 字符串，拒绝 `Z`、偏移和归一化后的非法日历值。
///
/// 契约要求：JSON 层的时间错误统一为 [FormatException]。
DateTime decodeLocalDateTime(Object? value, String field) {
  if (value is! String || !_localIsoPattern.hasMatch(value)) {
    throw FormatException(
      '$field must be a local ISO-8601 string without timezone',
    );
  }

  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      parsed.isUtc ||
      _withMicroseconds(parsed.toIso8601String()) != _withMicroseconds(value)) {
    throw FormatException('$field is not a valid local date-time: $value');
  }
  return parsed;
}

/// 读取 JSON 对象，并确保所有键都是 `String`。
///
/// 非 `String` 键直接拒绝，不做 `toString()` 转换，避免不同键静默碰撞。
Map<String, dynamic> readJsonMap(Object? value, String field) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw FormatException('$field must use String keys');
      }
      result[key] = entry.value;
    }
    return result;
  }
  throw FormatException('$field must be a JSON object');
}

/// 拒绝 JSON 对象中的未知字段，符合契约“模型与嵌套对象拒绝未知字段”。
void rejectUnknownKeys(
  Map<String, dynamic> json,
  Set<String> allowed,
  String field,
) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('$field contains an unknown field: $key');
    }
  }
}

/// 使用共享 [TimeRange] 解码嵌套时间区间，并把结构错误归一到 [FormatException]。
TimeRange decodeTimeRange(Object? value, String field) {
  final json = readJsonMap(value, field);
  try {
    return TimeRange.fromJson(json);
  } on FormatException {
    rethrow;
  } on ArgumentError catch (error) {
    throw FormatException('$field is invalid: ${error.message}');
  }
}

String _withMicroseconds(String value) {
  final parts = value.split('.');
  final fraction = parts.length == 2 ? parts[1] : '';
  return '${parts[0]}.${fraction.padRight(6, '0')}';
}
