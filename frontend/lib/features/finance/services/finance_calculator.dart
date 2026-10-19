import '../models/category_expense.dart';
import '../models/finance_record.dart';
import '../models/finance_type.dart';
import '../models/money.dart';
import '../models/monthly_finance_totals.dart';

class FinanceCalculator {
  const FinanceCalculator();

  MonthlyFinanceTotals calculate(
    List<FinanceRecord> records, {
    int? budgetMinor,
  }) {
    if (budgetMinor != null &&
        (budgetMinor < 0 || budgetMinor > maxAmountMinor)) {
      throw ArgumentError.value(
        budgetMinor,
        'budgetMinor',
        'Must be null or 0 to $maxAmountMinor.',
      );
    }

    var incomeMinor = 0;
    var expenseMinor = 0;
    for (final record in records) {
      switch (record.type) {
        case FinanceType.income:
          incomeMinor = addAmountMinor(incomeMinor, record.amountMinor);
        case FinanceType.expense:
          expenseMinor = addAmountMinor(expenseMinor, record.amountMinor);
      }
    }

    return MonthlyFinanceTotals(
      incomeMinor: incomeMinor,
      expenseMinor: expenseMinor,
      balanceMinor: incomeMinor - expenseMinor,
      budgetMinor: budgetMinor,
      remainingBudgetMinor: budgetMinor == null
          ? null
          : budgetMinor - expenseMinor,
    );
  }

  List<CategoryExpense> aggregateExpenses(
    List<FinanceRecord> records, {
    required String Function(String categoryId) resolveName,
  }) {
    final totals = <String, int>{};
    for (final record in records) {
      if (record.type != FinanceType.expense) {
        continue;
      }
      totals[record.categoryId] = addAmountMinor(
        totals[record.categoryId] ?? 0,
        record.amountMinor,
      );
    }

    final categories =
        totals.entries
            .map(
              (entry) => CategoryExpense(
                categoryId: entry.key,
                categoryName: resolveName(entry.key),
                amountMinor: entry.value,
              ),
            )
            .toList()
          ..sort((a, b) {
            final byAmount = b.amountMinor.compareTo(a.amountMinor);
            if (byAmount != 0) {
              return byAmount;
            }
            return a.categoryId.compareTo(b.categoryId);
          });

    return List<CategoryExpense>.unmodifiable(categories);
  }
}
