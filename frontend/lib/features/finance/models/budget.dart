import 'json_map.dart';
import 'money.dart';

/// 分类月度预算（契约第 5 节持久化契约 v2）。
///
/// - `categoryId` 必须引用已存在且 type=expense 的分类（引用保护在 CampusStore 全量校验中强制执行）。
/// - `(categoryId, month)` 组合唯一；`month` 格式为 `YYYY-MM`。
/// - `limitMinor` 为预算上限，最小货币单位，与账目的 `amountMinor` 一致。
class Budget {
  Budget({
    required this.id,
    required this.categoryId,
    required this.month,
    required this.limitMinor,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be blank.');
    }
    if (categoryId.trim().isEmpty) {
      throw ArgumentError.value(categoryId, 'categoryId', 'Must not be blank.');
    }
    if (!_monthPattern.hasMatch(month)) {
      throw ArgumentError.value(month, 'month', 'Must match YYYY-MM.');
    }
    final m = int.parse(month.substring(5, 7));
    if (m < 1 || m > 12) {
      throw ArgumentError.value(month, 'month', 'Month must be 01-12.');
    }
    if (limitMinor <= 0 || limitMinor > maxAmountMinor) {
      throw ArgumentError.value(
        limitMinor,
        'limitMinor',
        'Must be > 0 and <= $maxAmountMinor.',
      );
    }
  }

  static final RegExp _monthPattern = RegExp(r'^\d{4}-\d{2}$');

  final String id;
  final String categoryId;

  /// 预算月份，格式 `YYYY-MM`。
  final String month;

  /// 预算上限（最小货币单位）。
  final int limitMinor;

  Map<String, dynamic> toJson() => {
    'id': id,
    'categoryId': categoryId,
    'month': month,
    'limitMinor': limitMinor,
  };

  factory Budget.fromJson(Map<String, dynamic> json) {
    requireExactJsonKeys(
      json,
      requiredKeys: const {'id', 'categoryId', 'month', 'limitMinor'},
    );
    try {
      return Budget(
        id: readRequiredString(json, 'id'),
        categoryId: readRequiredString(json, 'categoryId'),
        month: readRequiredString(json, 'month'),
        limitMinor: readRequiredInt(json, 'limitMinor'),
      );
    } on ArgumentError {
      throw const FormatException('Invalid Budget values.');
    }
  }
}
