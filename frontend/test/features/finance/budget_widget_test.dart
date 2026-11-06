import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/finance/controllers/budget_controller.dart';
import 'package:student_life_rpg/features/finance/models/finance_category.dart';
import 'package:student_life_rpg/features/finance/models/finance_type.dart';
import 'package:student_life_rpg/features/finance/presentation/budget_editor.dart';
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
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> pumpSection(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: BudgetSection(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists expense categories with unset state', (tester) async {
    await pumpSection(tester);
    expect(find.textContaining('分类月度预算'), findsOneWidget);
    expect(find.text('餐饮'), findsOneWidget);
    expect(find.text('交通'), findsOneWidget);
    expect(find.text('生活费'), findsNothing);
    expect(find.text('未设置'), findsNWidgets(2));
  });

  testWidgets('setting a budget through the dialog updates the list', (
    tester,
  ) async {
    await pumpSection(tester);

    await tester.tap(find.text('设置预算'));
    await tester.pumpAndSettle();
    expect(find.text('设置分类月度预算'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('budget-amount')), '123.45');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('设置分类月度预算'), findsNothing);
    expect(controller.budgetFor('food'), 12345);
    expect(find.text('123.45 元'), findsOneWidget);
    expect(find.text('已设置'), findsOneWidget);
  });

  testWidgets('zero is a valid budget and shows as set', (tester) async {
    await pumpSection(tester);

    await tester.tap(find.text('设置预算'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('budget-amount')), '0');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(controller.isBudgetSet('food'), isTrue);
    expect(controller.budgetFor('food'), 0);
    expect(find.text('0.00 元'), findsOneWidget);
    expect(find.text('已设置'), findsOneWidget);
  });

  testWidgets('invalid amount keeps the dialog open with feedback', (
    tester,
  ) async {
    await pumpSection(tester);

    await tester.tap(find.text('设置预算'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('budget-amount')), '-1');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('设置分类月度预算'), findsOneWidget);
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(controller.budgetFor('food'), isNull);
  });

  testWidgets('clear button removes an existing budget', (tester) async {
    await controller.load();
    await controller.setBudget(categoryId: 'food', amountText: '50');
    await pumpSection(tester);

    expect(find.text('50.00 元'), findsOneWidget);
    await tester.tap(find.byTooltip('清除').first);
    await tester.pumpAndSettle();

    expect(controller.isBudgetSet('food'), isFalse);
    expect(find.text('未设置'), findsNWidgets(2));
  });
}
