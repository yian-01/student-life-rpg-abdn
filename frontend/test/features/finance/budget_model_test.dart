import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/finance/models/budget.dart';
import 'package:student_life_rpg/features/finance/models/money.dart';

void main() {
  test('zero amount is a valid budget distinct from absence', () {
    final budget = Budget(
      categoryId: 'food',
      month: DateTime(2026, 11),
      amountMinor: 0,
    );
    expect(budget.amountMinor, 0);
    expect(budget.month, DateTime(2026, 11));
  });

  test('month is normalized to local month start and UTC is rejected', () {
    final budget = Budget(
      categoryId: 'food',
      month: DateTime(2026, 11, 23, 18, 45),
      amountMinor: 500,
    );
    expect(budget.month, DateTime(2026, 11));
    expect(budget.month.day, 1);
    expect(budget.month.isUtc, isFalse);

    expect(
      () => Budget(
        categoryId: 'food',
        month: DateTime.utc(2026, 11),
        amountMinor: 1,
      ),
      throwsArgumentError,
    );
  });

  test('rejects blank category and out-of-range amounts', () {
    expect(
      () => Budget(categoryId: '  ', month: DateTime(2026, 11), amountMinor: 0),
      throwsArgumentError,
    );
    expect(
      () => Budget(
        categoryId: 'food',
        month: DateTime(2026, 11),
        amountMinor: -1,
      ),
      throwsArgumentError,
    );
    expect(
      () => Budget(
        categoryId: 'food',
        month: DateTime(2026, 11),
        amountMinor: maxAmountMinor + 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => Budget(
        categoryId: 'food',
        month: DateTime(2026, 11),
        amountMinor: maxAmountMinor,
      ),
      returnsNormally,
    );
  });

  test('category ID keeps original value without trimming', () {
    final budget = Budget(
      categoryId: ' cat ',
      month: DateTime(2026, 11),
      amountMinor: 1,
    );
    expect(budget.categoryId, ' cat ');
  });

  test('key is unique per category + local month regardless of day', () {
    final early = Budget(
      categoryId: 'food',
      month: DateTime(2026, 11, 3),
      amountMinor: 1,
    );
    final late = Budget(
      categoryId: 'food',
      month: DateTime(2026, 11, 28),
      amountMinor: 9,
    );
    expect(early.key, late.key);
    expect(
      budgetKey('food', DateTime(2026, 11, 15)),
      budgetKey('food', DateTime(2026, 11)),
    );
    expect(early.key, isNot(budgetKey('food', DateTime(2026, 12))));
    expect(early.key, isNot(budgetKey('transport', DateTime(2026, 11))));
  });

  test('copyWith only changes amount and keeps category/month identity', () {
    final budget = Budget(
      categoryId: 'food',
      month: DateTime(2026, 11),
      amountMinor: 500,
    );
    final updated = budget.copyWith(amountMinor: 0);
    expect(updated.categoryId, 'food');
    expect(updated.month, DateTime(2026, 11));
    expect(updated.amountMinor, 0);
    expect(budget.copyWith().amountMinor, 500);
  });

  test('JSON round trip keeps category, month and amount', () {
    final budget = Budget(
      categoryId: 'food',
      month: DateTime(2026, 11, 20),
      amountMinor: 0,
    );
    final json = budget.toJson();
    expect(json['month'], '2026-11-01');
    final restored = Budget.fromJson(json);
    expect(restored.categoryId, 'food');
    expect(restored.month, DateTime(2026, 11));
    expect(restored.amountMinor, 0);
  });

  test('fromJson rejects unknown keys, bad dates and invalid values', () {
    final valid = Budget(
      categoryId: 'food',
      month: DateTime(2026, 11),
      amountMinor: 1,
    ).toJson();

    expect(
      () => Budget.fromJson({...valid, 'extra': true}),
      throwsFormatException,
    );
    expect(
      () => Budget.fromJson({...valid}..remove('amountMinor')),
      throwsFormatException,
    );
    expect(
      () => Budget.fromJson({...valid, 'month': '2026-11-15'}),
      throwsFormatException,
    );
    expect(
      () => Budget.fromJson({...valid, 'month': '2026-02-30'}),
      throwsFormatException,
    );
    expect(
      () => Budget.fromJson({...valid, 'month': '2026-11'}),
      throwsFormatException,
    );
    expect(
      () => Budget.fromJson({...valid, 'categoryId': '  '}),
      throwsFormatException,
    );
    expect(
      () => Budget.fromJson({...valid, 'amountMinor': -1}),
      throwsFormatException,
    );
  });
}
