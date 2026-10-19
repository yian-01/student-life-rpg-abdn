import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/finance/models/finance_record.dart';
import 'package:student_life_rpg/features/finance/models/finance_type.dart';
import 'package:student_life_rpg/features/finance/models/money.dart';
import 'package:student_life_rpg/features/finance/services/finance_calculator.dart';

void main() {
  final calculator = FinanceCalculator();

  FinanceRecord rec({
    required String id,
    required FinanceType type,
    required int amount,
    DateTime? at,
    String categoryId = 'food',
  }) {
    return FinanceRecord(
      id: id,
      categoryId: categoryId,
      type: type,
      amountMinor: amount,
      occurredAt: at ?? DateTime(2026, 10, 10),
    );
  }

  test('income, expense, balance and category sort do not mutate input', () {
    final records = [
      rec(id: 'i1', type: FinanceType.income, amount: 1000),
      rec(id: 'e1', type: FinanceType.expense, amount: 300, categoryId: 'b'),
      rec(id: 'e2', type: FinanceType.expense, amount: 300, categoryId: 'a'),
      rec(id: 'e3', type: FinanceType.expense, amount: 400, categoryId: 'c'),
      rec(
        id: 'other-month',
        type: FinanceType.expense,
        amount: 50,
        at: DateTime(2026, 11, 1),
        categoryId: 'c',
      ),
    ];
    final snapshot = List<FinanceRecord>.from(records);

    final totals = calculator.calculate(records, budgetMinor: 800);
    expect(totals.incomeMinor, 1000);
    expect(totals.expenseMinor, 1050);
    expect(totals.balanceMinor, -50);
    expect(totals.remainingBudgetMinor, -250);

    final grouped = calculator.aggregateExpenses(
      records,
      resolveName: (id) => 'name-$id',
    );
    expect(grouped.map((item) => item.categoryId), ['c', 'a', 'b']);
    expect(grouped.map((item) => item.amountMinor), [450, 300, 300]);
    expect(
      grouped.fold<int>(0, (sum, item) => sum + item.amountMinor),
      totals.expenseMinor,
    );
    expect(records, snapshot);
  });

  test('null budget, zero budget and over-budget are distinct', () {
    final records = [rec(id: 'e1', type: FinanceType.expense, amount: 100)];
    final noBudget = calculator.calculate(records);
    expect(noBudget.budgetMinor, isNull);
    expect(noBudget.remainingBudgetMinor, isNull);

    final zeroBudget = calculator.calculate(records, budgetMinor: 0);
    expect(zeroBudget.budgetMinor, 0);
    expect(zeroBudget.remainingBudgetMinor, -100);

    final within = calculator.calculate(records, budgetMinor: 500);
    expect(within.remainingBudgetMinor, 400);
  });

  test('aggregation overflow is rejected', () {
    expect(
      () => calculator.calculate([
        rec(id: 'a', type: FinanceType.expense, amount: maxAmountMinor),
        rec(id: 'b', type: FinanceType.expense, amount: 1),
      ]),
      throwsArgumentError,
    );
  });
}
