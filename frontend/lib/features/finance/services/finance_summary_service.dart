// ignore_for_file: prefer_initializing_formals

import '../../../shared/repositories/entity_repository.dart';
import '../models/finance_category.dart';
import '../models/finance_record.dart';
import '../models/local_date_time_json.dart';
import '../models/monthly_finance_summary.dart';
import 'finance_calculator.dart';

class FinanceSummaryService {
  FinanceSummaryService({
    required EntityRepository<FinanceRecord> records,
    required EntityRepository<FinanceCategory> categories,
    required Future<int?> Function(DateTime month) loadBudget,
    FinanceCalculator calculator = const FinanceCalculator(),
  }) : _records = records,
       _categories = categories,
       _loadBudget = loadBudget,
       _calculator = calculator;

  final EntityRepository<FinanceRecord> _records;
  final EntityRepository<FinanceCategory> _categories;
  final Future<int?> Function(DateTime month) _loadBudget;
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
    final budgetMinor = await _loadBudget(start);
    final totals = _calculator.calculate(
      monthRecords,
      budgetMinor: budgetMinor,
    );
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

    return MonthlyFinanceSummary(
      month: start,
      incomeMinor: totals.incomeMinor,
      expenseMinor: totals.expenseMinor,
      balanceMinor: totals.balanceMinor,
      budgetMinor: totals.budgetMinor,
      remainingBudgetMinor: totals.remainingBudgetMinor,
      expenseByCategory: expenseByCategory,
    );
  }
}
