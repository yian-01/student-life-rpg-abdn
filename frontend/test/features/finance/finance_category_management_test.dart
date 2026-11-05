import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/finance/controllers/finance_controller.dart';
import 'package:student_life_rpg/features/finance/models/budget.dart';
import 'package:student_life_rpg/features/finance/models/finance_category.dart';
import 'package:student_life_rpg/features/finance/models/finance_record.dart';
import 'package:student_life_rpg/features/finance/models/finance_type.dart';
import 'package:student_life_rpg/features/finance/repositories/budget_repository.dart';
import 'package:student_life_rpg/features/finance/repositories/in_memory_finance_repositories.dart';
import 'package:student_life_rpg/features/finance/services/finance_summary_service.dart';

void main() {
  late InMemoryFinanceCategoryRepository categories;
  late InMemoryFinanceRecordRepository records;
  late InMemoryBudgetRepository budgets;
  late FinanceController controller;

  setUp(() async {
    final recordsHolder = <InMemoryFinanceRecordRepository?>[null];
    final budgetHolder = <InMemoryBudgetRepository?>[null];
    categories = InMemoryFinanceCategoryRepository(
      referencedCategoryIds: () =>
          recordsHolder[0]?.referencedCategoryIds() ?? <String>{},
      budgetReferencedCategoryIds: () =>
          budgetHolder[0]?.referencedCategoryIds() ?? <String>{},
    );
    records = InMemoryFinanceRecordRepository(categories: categories);
    recordsHolder[0] = records;
    budgets = InMemoryBudgetRepository(categories: categories);
    budgetHolder[0] = budgets;

    controller = FinanceController(
      records: records,
      categories: categories,
      service: _FakeSummaryService(records, categories),
      clock: () => DateTime(2026, 11, 4, 15),
    );
    await controller.load();
    await categories.insert(
      FinanceCategory(id: 'food', name: '餐饮', type: FinanceType.expense),
    );
    await categories.insert(
      FinanceCategory(id: 'pay', name: '生活费', type: FinanceType.income),
    );
    await controller.load();
  });

  tearDown(() => controller.dispose());

  test('addCategory creates a category and refreshes the list', () async {
    expect(
      await controller.addCategory(name: '交通', type: FinanceType.expense),
      isTrue,
    );
    expect(controller.availableCategories.map((c) => c.name), contains('交通'));
  });

  test('blank category name is rejected', () async {
    expect(
      await controller.addCategory(name: '   ', type: FinanceType.expense),
      isFalse,
    );
    expect(controller.error, isArgumentError);
    expect(await categories.list(), hasLength(2));
  });

  test('duplicate name within the same type is rejected', () async {
    expect(
      await controller.addCategory(name: '餐饮', type: FinanceType.expense),
      isFalse,
    );
    expect(controller.error, isStateError);
    expect((controller.error as StateError).message, contains('同类型下已存在同名分类'));
    expect(
      await categories.list().then((list) => list.where((c) => c.name == '餐饮')),
      hasLength(1),
    );
  });

  test('same name in a different type is allowed', () async {
    expect(
      await controller.addCategory(name: '餐饮', type: FinanceType.income),
      isTrue,
    );
    expect(
      controller.availableCategories.where(
        (c) => c.name == '餐饮' && c.type == FinanceType.income,
      ),
      hasLength(1),
    );
  });

  test('rename updates name and refreshes available categories', () async {
    expect(
      await controller.editCategory(
        'food',
        name: '餐饮（改名）',
        type: FinanceType.expense,
      ),
      isTrue,
    );
    expect(
      controller.availableCategories.firstWhere((c) => c.id == 'food').name,
      '餐饮（改名）',
    );
  });

  test('rename to a duplicate name is rejected', () async {
    await categories.insert(
      FinanceCategory(id: 'transport', name: '交通', type: FinanceType.expense),
    );
    await controller.load();
    expect(
      await controller.editCategory(
        'food',
        name: '交通',
        type: FinanceType.expense,
      ),
      isFalse,
    );
    expect(controller.error, isStateError);
    expect((controller.error as StateError).message, contains('同类型下已存在同名分类'));
  });

  test('type change is blocked when referenced by a record', () async {
    await records.insert(_record('rec-1', 'food', FinanceType.expense));
    await controller.load();
    expect(
      await controller.editCategory(
        'food',
        name: '餐饮',
        type: FinanceType.income,
      ),
      isFalse,
    );
    expect(controller.error, isStateError);
    expect(
      (controller.error as StateError).message,
      contains('被收支记录引用，无法修改类型'),
    );
    expect((await categories.getById('food'))!.type, FinanceType.expense);
  });

  test('type change is blocked when referenced by a budget', () async {
    await budgets.put(_budget('food', DateTime(2026, 11), 100));
    expect(
      await controller.editCategory(
        'food',
        name: '餐饮',
        type: FinanceType.income,
      ),
      isFalse,
    );
    expect(controller.error, isStateError);
    expect((controller.error as StateError).message, contains('被预算引用，无法修改类型'));
  });

  test('delete is blocked when referenced by a record', () async {
    await records.insert(_record('rec-1', 'food', FinanceType.expense));
    await controller.load();
    expect(await controller.deleteCategory('food'), isFalse);
    expect(controller.error, isStateError);
    expect((controller.error as StateError).message, contains('被收支记录引用，无法删除'));
    expect(await categories.getById('food'), isNotNull);
  });

  test('delete is blocked when referenced by a budget', () async {
    await budgets.put(_budget('food', DateTime(2026, 11), 100));
    expect(await controller.deleteCategory('food'), isFalse);
    expect(controller.error, isStateError);
    expect((controller.error as StateError).message, contains('被预算引用，无法删除'));
    expect(await categories.getById('food'), isNotNull);
  });

  test('delete succeeds when unreferenced', () async {
    expect(await controller.deleteCategory('food'), isTrue);
    expect(await categories.getById('food'), isNull);
  });

  test('editing an unknown category fails', () async {
    expect(
      await controller.editCategory(
        'ghost',
        name: 'X',
        type: FinanceType.expense,
      ),
      isFalse,
    );
    expect(controller.error, isStateError);
  });

  test('deleting an unknown category fails', () async {
    expect(await controller.deleteCategory('ghost'), isFalse);
    expect(controller.error, isStateError);
  });
}

FinanceRecord _record(String id, String categoryId, FinanceType type) {
  return FinanceRecord(
    id: id,
    categoryId: categoryId,
    type: type,
    amountMinor: 100,
    occurredAt: DateTime(2026, 11, 4, 12),
  );
}

Budget _budget(String categoryId, DateTime month, int amount) {
  return Budget(categoryId: categoryId, month: month, amountMinor: amount);
}

class _FakeSummaryService extends FinanceSummaryService {
  _FakeSummaryService(
    InMemoryFinanceRecordRepository records,
    InMemoryFinanceCategoryRepository categories,
  ) : super(
        records: records,
        categories: categories,
        loadBudget: (_) async => null,
      );
}
