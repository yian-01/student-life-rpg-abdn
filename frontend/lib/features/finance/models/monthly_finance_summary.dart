import 'category_expense.dart';

class MonthlyFinanceSummary {
  MonthlyFinanceSummary({
    required this.month,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.balanceMinor,
    this.budgetMinor,
    this.remainingBudgetMinor,
    required List<CategoryExpense> expenseByCategory,
  }) : expenseByCategory = List<CategoryExpense>.unmodifiable(
         expenseByCategory,
       ) {
    if (month.isUtc) {
      throw ArgumentError.value(month, 'month', 'Must be a local DateTime.');
    }
    if (month.day != 1 ||
        month.hour != 0 ||
        month.minute != 0 ||
        month.second != 0 ||
        month.millisecond != 0 ||
        month.microsecond != 0) {
      throw ArgumentError.value(month, 'month', 'Must be local month start.');
    }
  }

  final DateTime month;
  final int incomeMinor;
  final int expenseMinor;
  final int balanceMinor;
  final int? budgetMinor;
  final int? remainingBudgetMinor;
  final List<CategoryExpense> expenseByCategory;
}
