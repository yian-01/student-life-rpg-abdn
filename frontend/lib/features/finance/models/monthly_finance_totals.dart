class MonthlyFinanceTotals {
  const MonthlyFinanceTotals({
    required this.incomeMinor,
    required this.expenseMinor,
    required this.balanceMinor,
    this.budgetMinor,
    this.remainingBudgetMinor,
  });

  final int incomeMinor;
  final int expenseMinor;
  final int balanceMinor;
  final int? budgetMinor;
  final int? remainingBudgetMinor;
}
