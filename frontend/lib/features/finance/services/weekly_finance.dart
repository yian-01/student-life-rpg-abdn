import '../models/finance_record.dart';
import '../models/finance_type.dart';
import 'finance_calculator.dart';

DateTime financeWeekStart(DateTime date) =>
    DateTime(date.year, date.month, date.day + 1 - date.weekday);

DateTime financeDayOffset(DateTime day, int offset) =>
    DateTime(day.year, day.month, day.day + offset);

typedef FinanceDay = ({DateTime date, int income, int expense, int count});
typedef FinanceWeek = ({
  List<FinanceDay> days,
  int income,
  int expense,
  int previousExpense,
  List<({String id, int amount})> categories,
});

FinanceWeek weeklyFinance(Iterable<FinanceRecord> records, DateTime date) {
  final start = financeWeekStart(date);
  final end = financeDayOffset(start, 7);
  final previousStart = financeDayOffset(start, -7);
  final byDay = List.generate(7, (_) => <FinanceRecord>[]);
  final categories = <String, int>{};
  var previousExpense = 0;

  for (final record in records) {
    final time = record.occurredAt;
    final expense = record.type == FinanceType.expense;
    if (time.isBefore(start)) {
      if (expense && !time.isBefore(previousStart)) {
        previousExpense += record.amountMinor;
      }
    } else if (time.isBefore(end)) {
      byDay[time.weekday - 1].add(record);
      if (expense) {
        categories.update(
          record.categoryId,
          (amount) => amount + record.amountMinor,
          ifAbsent: () => record.amountMinor,
        );
      }
    }
  }

  final days = [
    for (final (index, rows) in byDay.indexed)
      _dayTotals(financeDayOffset(start, index), rows),
  ];
  final sortedCategories =
      [
        for (final category in categories.entries)
          (id: category.key, amount: category.value),
      ]..sort((a, b) {
        final byAmount = b.amount.compareTo(a.amount);
        return byAmount == 0 ? a.id.compareTo(b.id) : byAmount;
      });
  return (
    days: List.unmodifiable(days),
    income: days.fold(0, (sum, day) => sum + day.income),
    expense: days.fold(0, (sum, day) => sum + day.expense),
    previousExpense: previousExpense,
    categories: List.unmodifiable(sortedCategories),
  );
}

FinanceDay _dayTotals(DateTime date, List<FinanceRecord> rows) {
  final totals = const FinanceCalculator().calculate(rows, limitTotals: false);
  return (
    date: date,
    income: totals.incomeMinor,
    expense: totals.expenseMinor,
    count: rows.length,
  );
}
