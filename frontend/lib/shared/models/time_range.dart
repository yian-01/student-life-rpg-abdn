/// 本地时间范围，采用半开区间 [start, end)。
class TimeRange {
  TimeRange({required this.start, required this.end}) {
    if (start.isUtc || end.isUtc) {
      throw ArgumentError('TimeRange requires local DateTime values.');
    }
    if (!start.isBefore(end)) {
      throw ArgumentError('start must be before end.');
    }
  }

  final DateTime start;
  final DateTime end;

  Map<String, dynamic> toJson() => {
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
  };

  factory TimeRange.fromJson(Map<String, dynamic> json) {
    if (json.length != 2 ||
        !json.containsKey('start') ||
        !json.containsKey('end')) {
      throw const FormatException('TimeRange requires only start and end.');
    }

    final start = _readLocalTime(json['start']);
    final end = _readLocalTime(json['end']);

    try {
      return TimeRange(start: start, end: end);
    } on ArgumentError {
      throw const FormatException('Invalid TimeRange values.');
    }
  }

  static DateTime _readLocalTime(Object? value) {
    if (value is! String ||
        !RegExp(
          r'^([+-]\d{6}|\d{4})-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?$',
        ).hasMatch(value)) {
      throw const FormatException('Expected local ISO time without timezone.');
    }

    final parsed = DateTime.tryParse(value);
    if (parsed == null ||
        parsed.isUtc ||
        _withMicroseconds(parsed.toIso8601String()) !=
            _withMicroseconds(value)) {
      throw const FormatException('Invalid calendar date or time.');
    }
    return parsed;
  }

  static String _withMicroseconds(String value) {
    final parts = value.split('.');
    final fraction = parts.length == 2 ? parts[1] : '';
    return '${parts[0]}.${fraction.padRight(6, '0')}';
  }
}
