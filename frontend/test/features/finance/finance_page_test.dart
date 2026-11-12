import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/finance/controllers/budget_controller.dart';
import 'package:student_life_rpg/features/finance/finance_memory_scope.dart';
import 'package:student_life_rpg/features/finance/models/finance_record.dart';
import 'package:student_life_rpg/features/finance/models/finance_type.dart';
import 'package:student_life_rpg/features/finance/presentation/finance_page.dart';

void main() {
  late FinanceMemoryScope scope;

  setUp(() {
    scope = FinanceMemoryScope(
      clock: () => DateTime(2026, 10, 11, 12),
      initialMonth: DateTime(2026, 10),
    );
  });

  tearDown(() => scope.dispose());

  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(800, 1200),
    BudgetController? budgetController,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: FinancePage(
          controller: scope.controller,
          budgetController: budgetController,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'inline income and expense categories are selected for new records',
    (tester) async {
      await pumpPage(tester);
      final create = find.byKey(const Key('finance-add-category-inline'));
      for (final (type, name) in [('支出', '打印装订'), ('收入', '助教津贴')]) {
        await tester.ensureVisible(find.widgetWithText(ChoiceChip, type));
        await tester.tap(find.widgetWithText(ChoiceChip, type));
        await tester.pumpAndSettle();
        await tester.ensureVisible(create);
        await tester.tap(create);
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('category-name')), name);
        await tester.tap(find.widgetWithText(FilledButton, '保存'));
        await tester.pumpAndSettle();
        final category = (await scope.controller.listCategories()).singleWhere(
          (row) => row.name == name,
        );
        await tester.enterText(find.byType(TextField).first, '12.50');
        await tester.ensureVisible(find.text('添加记录'));
        await tester.tap(find.text('添加记录'));
        await tester.pumpAndSettle();
        expect(
          (await scope.records.list()).any(
            (row) => row.categoryId == category.id && row.type == category.type,
          ),
          isTrue,
        );
      }
    },
  );

  testWidgets('weekly chart can filter the ledger to the selected day', (
    tester,
  ) async {
    final category = (await scope.controller.listCategories()).first;
    await scope.controller.addRecord(
      categoryId: category.id,
      amountText: '3.50',
      occurredAt: DateTime(2026, 10, 5, 12),
      note: '周一测试账目',
    );
    await pumpPage(tester, size: const Size(380, 700));
    final openChart = find.text('每周收支趋势');
    await tester.ensureVisible(openChart);
    await tester.tap(openChart);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('weekly-finance-line-chart')), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '一'));
    await tester.pumpAndSettle();
    expect(find.text('10 月 5 日 · 1 笔'), findsOneWidget);
    final details = find.text('看明细');
    await tester.ensureVisible(details);
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.text('筛选结果 · 1 笔'), findsOneWidget);
    expect(find.textContaining('周一测试账目'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'copy a ledger record creates a fresh entry with today and no inherited status',
    (tester) async {
      final category = (await scope.controller.listCategories()).firstWhere(
        (item) => item.type == FinanceType.expense,
      );
      await scope.controller.addRecord(
        categoryId: category.id,
        amountText: '12.34',
        occurredAt: DateTime(2026, 10, 10, 12),
        note: '实验打印',
        reimbursement: ReimbursementStatus.reimbursed,
      );
      final original = (await scope.records.list()).single;
      await pumpPage(tester);
      final menu = find.byKey(Key('finance-actions-${original.id}'));
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制记账'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      final entries = await scope.records.list();
      final copy = entries.singleWhere((row) => row.id != original.id);
      expect(copy.categoryId, original.categoryId);
      expect(copy.note, '实验打印');
      expect(copy.amountMinor, 1234);
      expect(copy.occurredAt, scope.controller.now);
      expect(copy.reimbursement, ReimbursementStatus.none);
      expect(
        entries.singleWhere((row) => row.id == original.id).reimbursement,
        ReimbursementStatus.reimbursed,
      );
    },
  );

  testWidgets('adding a valid expense refreshes the list and summary', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.text('暂无记录'), findsOneWidget);
    expect(find.textContaining('收入 0.00 元'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '3.50');
    await tester.tap(find.text('添加记录'));
    await tester.pumpAndSettle();

    expect(find.textContaining('支出 3.50 元'), findsWidgets);
    expect(find.text('暂无记录'), findsNothing);
    expect(find.textContaining('余额 -3.50 元'), findsOneWidget);
    expect(find.textContaining('预算剩余 996.50 元'), findsOneWidget);
  });

  testWidgets('illegal amount shows feedback and does not add a record', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.enterText(find.byType(TextField).first, '-1');
    await tester.tap(find.text('添加记录'));
    await tester.pumpAndSettle();

    expect(find.textContaining('错误：'), findsOneWidget);
    expect(find.text('暂无记录'), findsOneWidget);
  });

  testWidgets('new record defaults to the injected today', (tester) async {
    await pumpPage(tester);
    expect(find.text('2026-10-11'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '3.50');
    await tester.tap(find.text('添加记录'));
    await tester.pumpAndSettle();

    expect(
      (await scope.records.list()).single.occurredAt,
      DateTime(2026, 10, 11, 12),
    );
  });

  testWidgets('month navigation moves the new-record date with it', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.byTooltip('上个月'));
    await tester.pumpAndSettle();
    expect(find.text('2026-09'), findsOneWidget);
    expect(find.text('2026-09-11'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '12');
    await tester.tap(find.text('添加记录'));
    await tester.pumpAndSettle();

    expect(scope.controller.month, DateTime(2026, 9));
    expect(
      (await scope.records.list()).single.occurredAt,
      DateTime(2026, 9, 11, 12),
    );
  });

  testWidgets('saving a previous-month date switches the list to that month', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.text('2026-10-11'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('保存后将切换到 2026-09'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '8');
    await tester.tap(find.text('添加记录'));
    await tester.pumpAndSettle();

    expect(find.text('2026-09'), findsOneWidget);
    expect(find.text('暂无记录'), findsNothing);
    expect(find.textContaining('支出 8.00 元'), findsWidgets);
  });

  testWidgets('per-category budget shows used and remaining in the summary', (
    tester,
  ) async {
    await scope.budgetController.load(month: DateTime(2026, 10));
    await scope.budgetController.setBudget(
      categoryId: 'demo-food',
      amountText: '100',
    );
    await scope.controller.addRecord(
      categoryId: 'demo-food',
      amountText: '35.50',
      occurredAt: DateTime(2026, 10, 11, 12),
    );

    await pumpPage(tester, budgetController: scope.budgetController);

    expect(find.text('已用 35.50 元 · 剩余 64.50 元'), findsOneWidget);
    expect(find.textContaining('预算剩余 64.50 元'), findsOneWidget);
    expect(find.textContaining('月预算 100.00 元'), findsOneWidget);
  });

  testWidgets('editing a budget refreshes the monthly total', (tester) async {
    await scope.budgetController.load(month: DateTime(2026, 10));
    await scope.budgetController.setBudget(
      categoryId: 'demo-food',
      amountText: '100',
    );
    await scope.controller.addRecord(
      categoryId: 'demo-food',
      amountText: '35.50',
      occurredAt: DateTime(2026, 10, 11, 12),
    );

    await pumpPage(tester, budgetController: scope.budgetController);
    await tester.tap(find.byTooltip('设置').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('budget-amount')), '200');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('已用 35.50 元 · 剩余 164.50 元'), findsOneWidget);
    expect(find.textContaining('预算剩余 164.50 元'), findsOneWidget);
  });

  testWidgets('narrow window does not overflow', (tester) async {
    await pumpPage(tester, size: const Size(240, 320));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('演示数据'), findsOneWidget);
    final addRecord = find.text('添加记录');
    await tester.ensureVisible(addRecord);
    await tester.pumpAndSettle();
    await tester.tap(addRecord);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
