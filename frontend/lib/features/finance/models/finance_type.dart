enum FinanceType { income, expense }

FinanceType financeTypeFromJson(Object? value) {
  if (value is! String) {
    throw const FormatException('FinanceType must be a string.');
  }
  return switch (value) {
    'income' => FinanceType.income,
    'expense' => FinanceType.expense,
    _ => throw const FormatException('Unknown FinanceType.'),
  };
}

String financeTypeToJson(FinanceType type) => type.name;
