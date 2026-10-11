/// 学术模块 JSON 解码的公共辅助。
///
/// 契约第 3 节规定错误类型：
/// - 模型构造或纯函数收到非法参数 -> [ArgumentError]
/// - JSON 缺字段、错误类型、错误枚举、错误版本或错误实体类型 -> [FormatException]
/// - JSON 中领域值非法 -> [FormatException]，由解码层转换构造校验错误
///
/// 因此解码层统一用本文件的两类辅助：先做类型检查抛 [FormatException]，
/// 再把构造器抛出的 [ArgumentError] 转换为 [FormatException]。
library;

/// 读取必填非空字符串字段。
String readRequiredString(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('Missing required field "$key".');
  }
  final value = json[key];
  if (value is! String) {
    throw FormatException('Field "$key" must be a string.');
  }
  return value;
}

/// 读取可空字符串字段，缺键按 null 处理。
String? readNullableString(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] == null) {
    return null;
  }
  final value = json[key];
  if (value is! String) {
    throw FormatException('Field "$key" must be a string or null.');
  }
  return value;
}

/// 读取必填整数字段。
int readRequiredInt(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('Missing required field "$key".');
  }
  final value = json[key];
  if (value is! int) {
    throw FormatException('Field "$key" must be an int.');
  }
  return value;
}

/// 读取必填数值字段（JSON 整数与小数均可）。
double readRequiredDouble(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('Missing required field "$key".');
  }
  return readDoubleValue(json[key], key);
}

/// 读取可空数值字段，缺键按 null 处理。
double? readNullableDouble(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] == null) {
    return null;
  }
  return readDoubleValue(json[key], key);
}

/// 把 JSON 值转换为 double，拒绝字符串、布尔、null 与非有限数。
double readDoubleValue(Object? value, String key) {
  if (value is int) {
    return value.toDouble();
  }
  if (value is double) {
    if (!value.isFinite) {
      throw FormatException('Field "$key" must be finite.');
    }
    return value;
  }
  throw FormatException('Field "$key" must be a number.');
}

/// 读取必填对象字段。
Map<String, dynamic> readRequiredObject(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('Missing required field "$key".');
  }
  final value = json[key];
  if (value is! Map<String, dynamic>) {
    throw FormatException('Field "$key" must be an object.');
  }
  return value;
}

/// 读取必填对象数组字段，每项必须是 JSON 对象。
List<Map<String, dynamic>> readRequiredObjectList(
  Map<String, dynamic> json,
  String key,
) {
  if (!json.containsKey(key)) {
    throw FormatException('Missing required field "$key".');
  }
  final value = json[key];
  if (value is! List) {
    throw FormatException('Field "$key" must be an array.');
  }
  return value
      .map((item) {
        if (item is! Map<String, dynamic>) {
          throw FormatException('Every item of "$key" must be an object.');
        }
        return item;
      })
      .toList(growable: false);
}

/// 读取必填整数数组字段。
List<int> readRequiredIntList(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('Missing required field "$key".');
  }
  final value = json[key];
  if (value is! List) {
    throw FormatException('Field "$key" must be an array.');
  }
  return value
      .map((item) {
        if (item is! int) {
          throw FormatException('Every item of "$key" must be an int.');
        }
        return item;
      })
      .toList(growable: false);
}

/// 拒绝未知键：`json` 的键集合必须与 [allowed] 完全一致。
///
/// 契约第 4.2 节要求顶层、模型和嵌套对象均拒绝未知字段。
void rejectUnknownKeys(
  Map<String, dynamic> json,
  Set<String> allowed, {
  required String context,
}) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('Unknown field "$key" in $context.');
    }
  }
}

/// 把构造器抛出的 [ArgumentError] 转换为 [FormatException]。
///
/// 契约要求“JSON 中领域值非法 -> FormatException，解码层转换构造校验错误”。
/// 已经是 [FormatException] 的异常原样透出，避免重复包装丢失信息。
T decodeWithArgumentErrors<T>(T Function() build) {
  try {
    return build();
  } on ArgumentError catch (error) {
    throw FormatException('Invalid value in JSON: ${error.message}');
  }
}

/// 校验非空字符串，返回 [ArgumentError] 而非 [FormatException]。
///
/// ID 与标题不得为空或全为空白；ID 保留原值，不通过 trim 改变身份。
void validateNotBlank(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be blank.');
  }
}
