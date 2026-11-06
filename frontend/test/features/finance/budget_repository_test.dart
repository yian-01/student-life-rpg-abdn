import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/finance/models/budget.dart';
import 'package:student_life_rpg/features/finance/models/finance_category.dart';
import 'package:student_life_rpg/features/finance/models/finance_type.dart';
import 'package:student_life_rpg/features/finance/repositories/budget_repository.dart';
import 'package:student_life_rpg/features/finance/repositories/in_memory_finance_repositories.dart';

void main() {
  late InMemoryFinanceCategoryRepository categories;
  late InMemoryBudgetRepository budgets;

  setUp(() async {
    categories = InMemoryFinanceCategoryRepository(
      referencedCategoryIds: () => <String>{},
    );
    budgets = InMemoryBudgetRepository(categories: categories);
    await categories.insert(
      FinanceCategory(id: 'food', name: '餐饮', type: FinanceType.expense),
    );
    await categories.insert(
      FinanceCategory(id: 'transport', name: '交通', type: FinanceType.expense),
    );
    await categories.insert(
      FinanceCategory(id: 'pay', name: '生活费', type: FinanceType.income),
    );
  });

  test('put then getForCategoryMonth returns the stored budget', () async {
    await budgets.put(
      Budget(categoryId: 'food', month: DateTime(2026, 11), amountMinor: 500),
    );
    final stored = await budgets.getForCategoryMonth(
      'food',
      DateTime(2026, 11, 20),
    );
    expect(stored?.amountMinor, 500);
    expect(stored?.month, DateTime(2026, 11));
  });

  test('absence returns null and zero is stored as a real budget', () async {
    expect(
      await budgets.getForCategoryMonth('food', DateTime(2026, 11)),
      isNull,
    );

    await budgets.put(
      Budget(categoryId: 'food', month: DateTime(2026, 11), amountMinor: 0),
    );
    final stored = await budgets.getForCategoryMonth(
      'food',
      DateTime(2026, 11),
    );
    expect(stored, isNotNull);
    expect(stored!.amountMinor, 0);
  });

  test('same category + month is unique: put updates a single entry', () async {
    await budgets.put(
      Budget(categoryId: 'food', month: DateTime(2026, 11), amountMinor: 500),
    );
    await budgets.put(
      Budget(
        categoryId: 'food',
        month: DateTime(2026, 11, 28),
        amountMinor: 800,
      ),
    );

    final all = await budgets.list();
    expect(all.where((b) => b.categoryId == 'food'), hasLength(1));
    expect(
      (await budgets.getForCategoryMonth(
        'food',
        DateTime(2026, 11),
      ))!.amountMinor,
      800,
    );
  });

  test('different categories and months are separate entries', () async {
    await budgets.put(
      Budget(categoryId: 'food', month: DateTime(2026, 11), amountMinor: 500),
    );
    await budgets.put(
      Budget(
        categoryId: 'transport',
        month: DateTime(2026, 11),
        amountMinor: 300,
      ),
    );
    await budgets.put(
      Budget(categoryId: 'food', month: DateTime(2026, 12), amountMinor: 600),
    );

    expect(await budgets.list(), hasLength(3));
    expect(
      (await budgets.getForCategoryMonth(
        'food',
        DateTime(2026, 12),
      ))!.amountMinor,
      600,
    );
  });

  test('removeForCategoryMonth returns true/false appropriately', () async {
    await budgets.put(
      Budget(categoryId: 'food', month: DateTime(2026, 11), amountMinor: 500),
    );
    expect(
      await budgets.removeForCategoryMonth('food', DateTime(2026, 11)),
      isTrue,
    );
    expect(
      await budgets.removeForCategoryMonth('food', DateTime(2026, 11)),
      isFalse,
    );
    expect(await budgets.list(), isEmpty);
  });

  test('put rejects unknown and income categories', () async {
    await expectLater(
      budgets.put(
        Budget(categoryId: 'ghost', month: DateTime(2026, 11), amountMinor: 1),
      ),
      throwsStateError,
    );
    await expectLater(
      budgets.put(
        Budget(categoryId: 'pay', month: DateTime(2026, 11), amountMinor: 1),
      ),
      throwsStateError,
    );
    expect(await budgets.list(), isEmpty);
  });

  test('blank category and UTC month are rejected', () async {
    expect(
      () => budgets.getForCategoryMonth('  ', DateTime(2026, 11)),
      throwsArgumentError,
    );
    expect(
      () => budgets.removeForCategoryMonth('  ', DateTime(2026, 11)),
      throwsArgumentError,
    );
    expect(
      () => budgets.getForCategoryMonth('food', DateTime.utc(2026, 11)),
      throwsArgumentError,
    );
  });

  test(
    'list is a defensive immutable copy sorted by month then category',
    () async {
      await budgets.put(
        Budget(
          categoryId: 'transport',
          month: DateTime(2026, 11),
          amountMinor: 1,
        ),
      );
      await budgets.put(
        Budget(categoryId: 'food', month: DateTime(2026, 11), amountMinor: 2),
      );
      await budgets.put(
        Budget(categoryId: 'food', month: DateTime(2026, 10), amountMinor: 3),
      );

      final all = await budgets.list();
      expect(all.map((b) => b.key), [
        budgetKey('food', DateTime(2026, 10)),
        budgetKey('food', DateTime(2026, 11)),
        budgetKey('transport', DateTime(2026, 11)),
      ]);
      expect(() => all.add(all.first), throwsUnsupportedError);
    },
  );
}
