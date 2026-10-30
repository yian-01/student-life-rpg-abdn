import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/finance/models/finance_category.dart';
import 'package:student_life_rpg/features/finance/models/finance_record.dart';
import 'package:student_life_rpg/features/finance/models/finance_type.dart';
import 'package:student_life_rpg/features/finance/services/finance_summary_service.dart';
import 'package:student_life_rpg/shared/repositories/entity_repository.dart';

class MemoryRepo<T> implements EntityRepository<T> {
  MemoryRepo(this._items, this._idOf);

  final List<T> _items;
  final String Function(T entity) _idOf;

  @override
  Future<List<T>> list() async => List<T>.unmodifiable(_items);

  @override
  Future<T?> getById(String id) async {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id');
    }
    for (final item in _items) {
      if (_idOf(item) == id) {
        return item;
      }
    }
    return null;
  }

  @override
  Future<void> insert(T entity) async => _items.add(entity);

  @override
  Future<void> update(T entity) async {}

  @override
  Future<bool> remove(String id) async => false;
}

void main() {
  test(
    'loadMonth normalizes to local month start and filters half-open',
    () async {
      final categories = MemoryRepo<FinanceCategory>([
        FinanceCategory(id: 'food', name: '餐饮', type: FinanceType.expense),
        FinanceCategory(id: 'pay', name: '生活费', type: FinanceType.income),
      ], (item) => item.id);
      final records = MemoryRepo<FinanceRecord>([
        FinanceRecord(
          id: 'in',
          categoryId: 'pay',
          type: FinanceType.income,
          amountMinor: 5000,
          occurredAt: DateTime(2026, 10, 2),
        ),
        FinanceRecord(
          id: 'out',
          categoryId: 'food',
          type: FinanceType.expense,
          amountMinor: 1200,
          occurredAt: DateTime(2026, 10, 31, 23, 59, 59),
        ),
        FinanceRecord(
          id: 'next',
          categoryId: 'food',
          type: FinanceType.expense,
          amountMinor: 700,
          occurredAt: DateTime(2026, 11, 1),
        ),
      ], (item) => item.id);

      final service = FinanceSummaryService(
        records: records,
        categories: categories,
        loadBudget: (month) async {
          expect(month, DateTime(2026, 10));
          return 2000;
        },
      );

      final summary = await service.loadMonth(DateTime(2026, 10, 18, 15, 30));
      expect(summary.month, DateTime(2026, 10));
      expect(summary.incomeMinor, 5000);
      expect(summary.expenseMinor, 1200);
      expect(summary.balanceMinor, 3800);
      expect(summary.budgetMinor, 2000);
      expect(summary.remainingBudgetMinor, 800);
      expect(summary.expenseByCategory.single.categoryName, '餐饮');
    },
  );

  test('missing category name becomes 未分类 and records a diagnostic', () async {
    final service = FinanceSummaryService(
      records: MemoryRepo<FinanceRecord>([
        FinanceRecord(
          id: 'orphan',
          categoryId: 'gone',
          type: FinanceType.expense,
          amountMinor: 50,
          occurredAt: DateTime(2026, 10, 5),
        ),
      ], (item) => item.id),
      categories: MemoryRepo<FinanceCategory>([], (item) => item.id),
      loadBudget: (_) async => null,
    );

    final summary = await service.loadMonth(DateTime(2026, 10));
    expect(summary.expenseByCategory.single.categoryName, '未分类');
    expect(summary.expenseByCategory.single.amountMinor, 50);
    expect(service.diagnostics, isNotEmpty);
    expect(summary.budgetMinor, isNull);
    expect(summary.remainingBudgetMinor, isNull);
  });
}
