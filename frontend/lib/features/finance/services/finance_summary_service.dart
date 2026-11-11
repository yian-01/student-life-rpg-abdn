// ignore_for_file: prefer_initializing_formals

import '../../../shared/repositories/entity_repository.dart';
import '../models/budget.dart';
import '../models/finance_category.dart';
import '../models/finance_record.dart';
import '../models/local_date_time_json.dart';
import '../models/monthly_finance_summary.dart';
import '../models/money.dart';
import '../repositories/budget_repository.dart';
import 'finance_calculator.dart';

class FinanceSummaryService {
  FinanceSummaryService({
    required EntityRepository<FinanceRecord> records,
    required EntityRepository<FinanceCategory> categories,
    Future<int?> Function(DateTime month)? loadBudget,
    BudgetRepository? categoryBudgets,
    FinanceCalculator calculator = const FinanceCalculator(),
  }) : _records = records,
       _categories = categories,
       _loadBudget = loadBudget,
       _categoryBudgets = categoryBudgets,
       _calculator = calculator;

  final EntityRepository<FinanceRecord> _records;
  final EntityRepository<FinanceCategory> _categories;
  final Future<int?> Function(DateTime month)? _loadBudget;
  final BudgetRepository? _categoryBudgets;
  final FinanceCalculator _calculator;

  final List<String> _diagnostics = [];

  List<String> get diagnostics => List<String>.unmodifiable(_diagnostics);

  Future<MonthlyFinanceSummary> loadMonth(DateTime month) async {
    requireLocalDateTime(month, 'month');
    final start = DateTime(month.year, month.month);
    final end = DateTime(start.year, start.month + 1);
    _diagnostics.clear();

    final monthRecords = (await _records.list())
        .where(
          (record) =>
              !record.occurredAt.isBefore(start) &&
              record.occurredAt.isBefore(end),
        )
        .toList();

    final categoriesById = {
      for (final category in await _categories.list()) category.id: category,
    };
    final expenseByCategory = _calculator.aggregateExpenses(
      monthRecords,
      resolveName: (categoryId) {
        final category = categoriesById[categoryId];
        if (category == null || category.name.trim().isEmpty) {
          _diagnostics.add('Missing finance category name for $categoryId');
          return '未分类';
        }
        return category.name;
      },
    );

    final budgets = {
      for (final budget in await _categoryBudgets?.list() ?? const <Budget>[])
        if (budget.month == start) budget.categoryId: budget.amountMinor,
    };
    final totals = _calculator.calculate(
      monthRecords,
      budgetMinor: budgets.isEmpty ? await _loadBudget?.call(start) : null,
    );
    var budgetMinor = totals.budgetMinor;
    var remainingBudgetMinor = totals.remainingBudgetMinor;
    if (budgets.isNotEmpty) {
      var budgetTotal = 0;
      var coveredExpenses = 0;
      for (final amount in budgets.values) {
        budgetTotal = addAmountMinor(budgetTotal, amount);
      }
      for (final expense in expenseByCategory) {
        if (budgets.containsKey(expense.categoryId)) {
          coveredExpenses = addAmountMinor(
            coveredExpenses,
            expense.amountMinor,
          );
        }
      }
      budgetMinor = budgetTotal;
      remainingBudgetMinor = budgetTotal - coveredExpenses;
    }

    return MonthlyFinanceSummary(
      month: start,
      incomeMinor: totals.incomeMinor,
      expenseMinor: totals.expenseMinor,
      balanceMinor: totals.balanceMinor,
      budgetMinor: budgetMinor,
      remainingBudgetMinor: remainingBudgetMinor,
      expenseByCategory: expenseByCategory,
    );
  }
}
