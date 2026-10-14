void requireExactJsonKeys(
  Map<String, dynamic> json, {
  required Set<String> requiredKeys,
  Set<String> optionalKeys = const {},
}) {
  final allowed = {...requiredKeys, ...optionalKeys};
  if (json.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('Unknown JSON key.');
  }
  for (final key in requiredKeys) {
    if (!json.containsKey(key)) {
      throw FormatException('Missing JSON key: $key.');
    }
  }
}

String readRequiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('$key must be a string.');
  }
  return value;
}

int readRequiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw FormatException('$key must be an integer.');
  }
  return value;
}

String? readOptionalString(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] == null) {
    return null;
  }
  final value = json[key];
  if (value is! String) {
    throw FormatException('$key must be a string or null.');
  }
  return value;
}
