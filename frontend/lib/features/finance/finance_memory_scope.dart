import '../../shared/repositories/entity_repository.dart';
import 'controllers/finance_controller.dart';
import 'models/finance_category.dart';
import 'models/finance_type.dart';
import 'repositories/in_memory_finance_repositories.dart';
import 'services/finance_summary_service.dart';

/// In-memory finance graph for this round. Restart does not keep records.
/// A can replace this scope with the same repositories at the composition root.
class FinanceMemoryScope {
  FinanceMemoryScope({
    Future<int?> Function(DateTime month)? loadBudget,
    DateTime Function()? clock,
    DateTime? initialMonth,
    bool seedDemoCategories = true,
  }) {
    final recordsHolder = <InMemoryFinanceRecordRepository?>[null];
    categories = InMemoryFinanceCategoryRepository(
      referencedCategoryIds: () =>
          recordsHolder[0]?.referencedCategoryIds() ?? <String>{},
    );
    records = InMemoryFinanceRecordRepository(categories: categories);
    recordsHolder[0] = records;
    loadBudgetMinor = loadBudget ?? _demoBudget;
    service = FinanceSummaryService(
      records: records,
      categories: categories,
      loadBudget: loadBudgetMinor,
    );
    controller = FinanceController(
      records: records,
      categories: categories,
      service: service,
      clock: clock,
      initialMonth: initialMonth,
    );
    if (seedDemoCategories) {
      for (final category in [
        FinanceCategory(
          id: 'demo-food',
          name: '餐饮（演示）',
          type: FinanceType.expense,
        ),
        FinanceCategory(
          id: 'demo-transport',
          name: '交通（演示）',
          type: FinanceType.expense,
        ),
        FinanceCategory(
          id: 'demo-allowance',
          name: '生活费（演示）',
          type: FinanceType.income,
        ),
      ]) {
        // insert has no await; the memory map is updated before the Future returns.
        categories.insert(category);
      }
    }
  }

  static FinanceMemoryScope? _shared;

  static FinanceMemoryScope get shared => _shared ??= FinanceMemoryScope();

  static void resetShared() {
    _shared?.controller.dispose();
    _shared = null;
  }

  late final InMemoryFinanceCategoryRepository categories;
  late final InMemoryFinanceRecordRepository records;
  late final Future<int?> Function(DateTime month) loadBudgetMinor;
  late final FinanceSummaryService service;
  late final FinanceController controller;

  EntityRepository<FinanceCategory> get categoryRepository => categories;
  FinanceRecordRepository get recordRepository => records;

  void dispose() {
    controller.dispose();
    if (identical(_shared, this)) {
      _shared = null;
    }
  }

  Future<int?> _demoBudget(DateTime month) async {
    // Demo injection only; not a budget CRUD store.
    return 100000;
  }
}
