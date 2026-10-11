import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/finance/finance_memory_scope.dart';
import 'package:student_life_rpg/features/finance/presentation/finance_page.dart';

void main() {
  late FinanceMemoryScope scope;

  setUp(() {
    scope = FinanceMemoryScope(
      clock: () => DateTime(2026, 10, 11, 12),
      initialMonth: DateTime(2026, 10),
    );
  });

  tearDown(scope.dispose);

  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(800, 1200),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(home: FinancePage(controller: scope.controller)),
    );
    await tester.pumpAndSettle();
  }

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

  testWidgets('narrow window does not overflow', (tester) async {
    await pumpPage(tester, size: const Size(240, 320));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('演示数据'), findsOneWidget);
    await tester.tap(find.text('添加记录'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
