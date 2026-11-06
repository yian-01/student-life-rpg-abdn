import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/finance/controllers/finance_controller.dart';
import 'package:student_life_rpg/features/finance/finance_file_scope.dart';
import 'package:student_life_rpg/features/finance/models/finance_category.dart';
import 'package:student_life_rpg/features/finance/models/finance_type.dart';
import 'package:student_life_rpg/features/finance/repositories/file_finance_repositories.dart';
import 'package:student_life_rpg/features/finance/services/finance_summary_service.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('finance_persist_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<FinanceFileScope> openScope() => FinanceFileScope.open(
    directory: tempDir.path,
    clock: () => DateTime(2026, 11, 4, 15),
    initialMonth: DateTime(2026, 11),
  );

  test('records, categories and budgets survive restart', () async {
    var scope = await openScope();
    await scope.controller.load();
    await scope.controller.addCategory(
      name: '餐饮',
      type: FinanceType.expense,
    );
    await scope.controller.load();
    final foodId = scope.controller.availableCategories
        .firstWhere((c) => c.name == '餐饮')
        .id;
    await scope.controller.addRecord(categoryId: foodId, amountText: '12.30');
    await scope.budgetController.load();
    await scope.budgetController.setBudget(
      categoryId: foodId,
      amountText: '100',
    );
    expect(scope.controller.monthRecords, hasLength(1));
    scope.dispose();

    // 重新打开同一目录（模拟退出重开）。
    scope = await openScope();
    await scope.controller.load();
    await scope.budgetController.load();

    expect(
      scope.controller.availableCategories.map((c) => c.name),
      contains('餐饮'),
    );
    expect(scope.controller.monthRecords, hasLength(1));
    expect(scope.controller.monthRecords.single.amountMinor, 1230);
    expect(scope.controller.summary!.expenseMinor, 1230);
    expect(scope.budgetController.budgetFor(foodId), 10000);
    scope.dispose();
  });

  test('editing a record across months keeps both summaries correct', () async {
    final scope = await openScope();
    await scope.controller.load();
    await scope.controller.addCategory(name: '餐饮', type: FinanceType.expense);
    await scope.controller.load();
    final foodId = scope.controller.availableCategories.first.id;
    await scope.controller.addRecord(categoryId: foodId, amountText: '50');
    final recordId = scope.controller.monthRecords.single.id;

    // 从 11 月移动到 12 月。
    expect(
      await scope.controller.updateRecord(
        recordId,
        categoryId: foodId,
        amountText: '50',
        occurredAt: DateTime(2026, 12, 5, 12),
      ),
      isTrue,
    );

    await scope.controller.load(month: DateTime(2026, 11));
    expect(scope.controller.monthRecords, isEmpty);
    expect(scope.controller.summary!.expenseMinor, 0);

    await scope.controller.load(month: DateTime(2026, 12));
    expect(scope.controller.monthRecords, hasLength(1));
    expect(scope.controller.summary!.expenseMinor, 5000);
    scope.dispose();
  });

  test('editing a record across categories refreshes category summary', () async {
    final scope = await openScope();
    await scope.controller.load();
    await scope.controller.addCategory(name: '餐饮', type: FinanceType.expense);
    await scope.controller.addCategory(name: '交通', type: FinanceType.expense);
    await scope.controller.load();
    final foodId = scope.controller.availableCategories
        .firstWhere((c) => c.name == '餐饮')
        .id;
    final transportId = scope.controller.availableCategories
        .firstWhere((c) => c.name == '交通')
        .id;
    await scope.controller.addRecord(categoryId: foodId, amountText: '30');
    final recordId = scope.controller.monthRecords.single.id;

    expect(
      await scope.controller.updateRecord(
        recordId,
        categoryId: transportId,
        amountText: '30',
        occurredAt: DateTime(2026, 11, 4, 15),
      ),
      isTrue,
    );

    await scope.controller.load(month: DateTime(2026, 11));
    final summary = scope.controller.summary!;
    expect(summary.expenseMinor, 3000);
    final names = summary.expenseByCategory.map((c) => c.categoryName);
    expect(names, contains('交通'));
    expect(names, isNot(contains('餐饮')));
    scope.dispose();
  });

  test('rapid double submit inserts a single record', () async {
    final scope = await openScope();
    await scope.controller.load();
    await scope.controller.addCategory(name: '餐饮', type: FinanceType.expense);
    await scope.controller.load();
    final foodId = scope.controller.availableCategories.first.id;

    final results = await Future.wait([
      scope.controller.addRecord(categoryId: foodId, amountText: '1'),
      scope.controller.addRecord(categoryId: foodId, amountText: '2'),
    ]);

    expect(results.where((ok) => ok), hasLength(1));
    expect(await scope.records.list(), hasLength(1));
    scope.dispose();
  });

  test('cannot delete a category referenced by a persisted record', () async {
    final scope = await openScope();
    await scope.controller.load();
    await scope.controller.addCategory(name: '餐饮', type: FinanceType.expense);
    await scope.controller.load();
    final foodId = scope.controller.availableCategories.first.id;
    await scope.controller.addRecord(categoryId: foodId, amountText: '9');

    expect(await scope.controller.deleteCategory(foodId), isFalse);
    expect(scope.controller.error, isStateError);
    expect(await scope.categories.getById(foodId), isNotNull);
    scope.dispose();
  });

  test('commit succeeds even when the refresh fails, without re-insert', () async {
    const store = FileJsonDocumentStore();
    final sep = Platform.pathSeparator;
    late final FileFinanceRecordRepository records;
    late final FileFinanceBudgetRepository budgets;
    final categories = FileFinanceCategoryRepository(
      store: store,
      path: '${tempDir.path}${sep}finance_categories.json',
      recordCategoryIds: () => records.referencedCategoryIds(),
      budgetCategoryIds: () => budgets.referencedCategoryIdsAsync(),
    );
    records = FileFinanceRecordRepository(
      store: store,
      path: '${tempDir.path}${sep}finance_records.json',
      categories: categories,
    );
    budgets = FileFinanceBudgetRepository(
      store: store,
      path: '${tempDir.path}${sep}finance_budgets.json',
      categories: categories,
    );
    await categories.insert(
      FinanceCategory(id: 'food', name: '餐饮', type: FinanceType.expense),
    );

    final controller = FinanceController(
      records: records,
      categories: categories,
      service: FinanceSummaryService(
        records: records,
        categories: categories,
        loadBudget: (_) async => throw const FormatException('refresh boom'),
      ),
      clock: () => DateTime(2026, 11, 4, 15),
    );
    addTearDown(controller.dispose);

    expect(
      await controller.addRecord(categoryId: 'food', amountText: '8.80'),
      isTrue,
    );
    // 刷新失败被展示为错误，但提交仍成功且只写入一次。
    expect(controller.error, isFormatException);
    expect(await records.list(), hasLength(1));
    expect((await records.list()).single.amountMinor, 880);
  });

  test('illegal amount text is rejected and stores nothing', () async {
    final scope = await openScope();
    await scope.controller.load();
    await scope.controller.addCategory(name: '餐饮', type: FinanceType.expense);
    await scope.controller.load();
    final foodId = scope.controller.availableCategories.first.id;

    for (final bad in ['', 'abc', '0', '-1', '1.234', '21474836.48']) {
      expect(
        await scope.controller.addRecord(categoryId: foodId, amountText: bad),
        isFalse,
        reason: bad,
      );
    }
    expect(await scope.records.list(), isEmpty);
    scope.dispose();
  });
}
