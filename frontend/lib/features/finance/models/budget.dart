import 'json_map.dart';
import 'local_date_time_json.dart';
import 'money.dart';

/// 分类月度预算（V1.0 增量，Issue #29）。
///
/// 契约：`Budget(categoryId, month, amountMinor)`。
/// - 唯一性：同一支出类别 + 本地年月仅一项，由 [key]/[budgetKey] 标识。
/// - 金额以整数“分”表示；`0` 是有效预算，与“未设置”（无对应预算项）不同。
class Budget {
  Budget({
    required this.categoryId,
    required DateTime month,
    required this.amountMinor,
  }) : month = _normalizeMonth(month) {
    if (categoryId.trim().isEmpty) {
      throw ArgumentError.value(categoryId, 'categoryId', 'Must not be blank.');
    }
    if (amountMinor < 0 || amountMinor > maxAmountMinor) {
      throw ArgumentError.value(
        amountMinor,
        'amountMinor',
        'Must be 0 to $maxAmountMinor.',
      );
    }
  }

  /// 支出类别 ID，保留原值，不以 trim 改变身份。
  final String categoryId;

  /// 已归一化为本地月首（当月 1 日 00:00）的时间。
  final DateTime month;

  /// 以“分”为单位的月预算金额；`0` 为有效预算。
  final int amountMinor;

  /// 唯一键：同一支出类别 + 本地年月。
  String get key => budgetKey(categoryId, month);

  /// 只允许修改金额；类别与月份构成身份，不可通过 copyWith 变更。
  Budget copyWith({int? amountMinor}) => Budget(
    categoryId: categoryId,
    month: month,
    amountMinor: amountMinor ?? this.amountMinor,
  );

  Map<String, dynamic> toJson() => {
    'categoryId': categoryId,
    'month': _formatMonth(month),
    'amountMinor': amountMinor,
  };

  factory Budget.fromJson(Map<String, dynamic> json) {
    requireExactJsonKeys(
      json,
      requiredKeys: const {'categoryId', 'month', 'amountMinor'},
    );
    try {
      return Budget(
        categoryId: readRequiredString(json, 'categoryId'),
        month: _parseMonth(readRequiredString(json, 'month')),
        amountMinor: readRequiredInt(json, 'amountMinor'),
      );
    } on ArgumentError {
      throw const FormatException('Invalid Budget values.');
    }
  }
}

/// 唯一键：同一支出类别 + 本地年月。
String budgetKey(String categoryId, DateTime month) {
  final normalized = _normalizeMonth(month);
  final year = normalized.year.toString().padLeft(4, '0');
  final monthText = normalized.month.toString().padLeft(2, '0');
  return '$categoryId@$year-$monthText';
}

DateTime _normalizeMonth(DateTime month) {
  requireLocalDateTime(month, 'month');
  return DateTime(month.year, month.month);
}

String _formatMonth(DateTime month) {
  final year = month.year.toString().padLeft(4, '0');
  final monthText = month.month.toString().padLeft(2, '0');
  return '$year-$monthText-01';
}

DateTime _parseMonth(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    throw const FormatException('Month must be YYYY-MM-DD.');
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    throw const FormatException('Invalid calendar date.');
  }
  if (day != 1) {
    throw const FormatException('Budget month must be the first day.');
  }
  return parsed;
}
