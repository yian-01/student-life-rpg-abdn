import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/finance/controllers/budget_controller.dart';
import 'package:student_life_rpg/features/finance/models/budget.dart';
import 'package:student_life_rpg/features/finance/models/finance_category.dart';
import 'package:student_life_rpg/features/finance/models/finance_type.dart';
import 'package:student_life_rpg/features/finance/repositories/budget_repository.dart';
import 'package:student_life_rpg/features/finance/repositories/in_memory_finance_repositories.dart';

void main() {
  late InMemoryFinanceCategoryRepository categories;
  late InMemoryBudgetRepository budgets;
  late BudgetController controller;

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
    controller = BudgetController(
      budgets: budgets,
      categories: categories,
      clock: () => DateTime(2026, 11, 4, 15),
    );
    await controller.load();
  });

  tearDown(() => controller.dispose());

  test('loads only expense categories and current-month budgets', () async {
    await budgets.put(
      Budget(categoryId: 'food', month: DateTime(2026, 11), amountMinor: 0),
    );
    await budgets.put(
      Budget(
        categoryId: 'transport',
        month: DateTime(2026, 10),
        amountMinor: 500,
      ),
    );
    await controller.load();

    expect(controller.month, DateTime(2026, 11));
    expect(controller.expenseCategories.map((c) => c.id), [
      'food',
      'transport',
    ]);
    expect(controller.isBudgetSet('food'), isTrue);
    expect(controller.budgetFor('food'), 0);
    expect(controller.isBudgetSet('transport'), isFalse);
    expect(controller.budgetFor('transport'), isNull);
    expect(controller.budgets, hasLength(1));
  });

  test(
    'setBudget parses integer minor units, allows zero and refreshes',
    () async {
      expect(
        await controller.setBudget(categoryId: 'food', amountText: '12.34'),
        isTrue,
      );
      expect(controller.budgetFor('food'), 1234);
      expect(controller.error, isNull);

      expect(
        await controller.setBudget(categoryId: 'food', amountText: '0'),
        isTrue,
      );
      expect(controller.isBudgetSet('food'), isTrue);
      expect(controller.budgetFor('food'), 0);
      expect(await budgets.list(), hasLength(1));
    },
  );

  test('removeBudget clears set zero and distinguishes not set', () async {
    await controller.setBudget(categoryId: 'food', amountText: '0');
    expect(controller.isBudgetSet('food'), isTrue);
    expect(await controller.removeBudget('food'), isTrue);
    expect(controller.isBudgetSet('food'), isFalse);
    expect(controller.budgetFor('food'), isNull);

    expect(await controller.removeBudget('food'), isFalse);
    expect(controller.error, isStateError);
  });

  test(
    'invalid amount and income category surface errors without saving',
    () async {
      expect(
        await controller.setBudget(categoryId: 'food', amountText: '-1'),
        isFalse,
      );
      expect(controller.error, isFormatException);
      expect(await budgets.list(), isEmpty);

      expect(
        await controller.setBudget(categoryId: 'pay', amountText: '10'),
        isFalse,
      );
      expect(controller.error, isStateError);
      expect(await budgets.list(), isEmpty);
    },
  );

  test('unknown category failure is surfaced', () async {
    expect(
      await controller.setBudget(categoryId: 'ghost', amountText: '1'),
      isFalse,
    );
    expect(controller.error, isStateError);
    expect(await budgets.list(), isEmpty);
  });

  test('month change selects a separate unique budget', () async {
    await controller.setBudget(categoryId: 'food', amountText: '10');
    await controller.load(month: DateTime(2026, 12, 31));
    expect(controller.month, DateTime(2026, 12));
    expect(controller.isBudgetSet('food'), isFalse);

    await controller.setBudget(categoryId: 'food', amountText: '20');
    expect(await budgets.list(), hasLength(2));
    expect(
      (await budgets.getForCategoryMonth(
        'food',
        DateTime(2026, 11),
      ))!.amountMinor,
      1000,
    );
    expect(controller.budgetFor('food'), 2000);
  });

  test(
    'saving lifecycle notifies listeners and blocks concurrent writes',
    () async {
      final states = <bool>[];
      controller.addListener(() => states.add(controller.isSaving));
      expect(
        await controller.setBudget(categoryId: 'food', amountText: '1'),
        isTrue,
      );
      expect(states.first, isTrue);
      expect(states.last, isFalse);
    },
  );

  test('exposed lists are immutable', () async {
    expect(() => controller.expenseCategories.clear(), throwsUnsupportedError);
    expect(
      () => controller.budgets.add(
        Budget(categoryId: 'food', month: DateTime(2026, 11), amountMinor: 1),
      ),
      throwsUnsupportedError,
    );
  });
}
