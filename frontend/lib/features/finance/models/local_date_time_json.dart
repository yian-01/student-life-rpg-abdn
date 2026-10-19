DateTime readLocalDateTime(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^([+-]\d{6}|\d{4})-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?$',
      ).hasMatch(value)) {
    throw const FormatException('Expected local ISO time without timezone.');
  }

  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      parsed.isUtc ||
      _withMicroseconds(parsed.toIso8601String()) != _withMicroseconds(value)) {
    throw const FormatException('Invalid calendar date or time.');
  }
  return parsed;
}

void requireLocalDateTime(DateTime value, String name) {
  if (value.isUtc) {
    throw ArgumentError.value(value, name, 'Must be a local DateTime.');
  }
}

String _withMicroseconds(String value) {
  final parts = value.split('.');
  final fraction = parts.length == 2 ? parts[1] : '';
  return '${parts[0]}.${fraction.padRight(6, '0')}';
}
