import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/finance/controllers/finance_controller.dart';
import 'package:student_life_rpg/features/finance/models/finance_category.dart';
import 'package:student_life_rpg/features/finance/models/finance_type.dart';
import 'package:student_life_rpg/features/finance/repositories/in_memory_finance_repositories.dart';
import 'package:student_life_rpg/features/finance/services/finance_summary_service.dart';
import 'package:student_life_rpg/shared/repositories/entity_repository.dart';

/// Category repository whose `getById` fails on demand.
class _FlakyCategoryRepository implements EntityRepository<FinanceCategory> {
  _FlakyCategoryRepository(this._delegate);

  final EntityRepository<FinanceCategory> _delegate;
  Object? _failure;

  void failNextWith(Object error) => _failure = error;

  @override
  Future<List<FinanceCategory>> list() => _delegate.list();

  @override
  Future<FinanceCategory?> getById(String id) async {
    final failure = _failure;
    if (failure != null) {
      _failure = null;
      throw failure;
    }
    return _delegate.getById(id);
  }

  @override
  Future<void> insert(FinanceCategory entity) => _delegate.insert(entity);

  @override
  Future<void> update(FinanceCategory entity) => _delegate.update(entity);

  @override
  Future<bool> remove(String id) => _delegate.remove(id);
}

void main() {
  late InMemoryFinanceCategoryRepository categories;
  late InMemoryFinanceRecordRepository records;
  late _FlakyCategoryRepository flaky;
  late FinanceController controller;

  setUp(() async {
    InMemoryFinanceRecordRepository? recordRepo;
    categories = InMemoryFinanceCategoryRepository(
      referencedCategoryIds: () => recordRepo?.referencedCategoryIds() ?? {},
    );
    records = InMemoryFinanceRecordRepository(categories: categories);
    recordRepo = records;
    flaky = _FlakyCategoryRepository(categories);

    controller = FinanceController(
      records: records,
      categories: flaky,
      service: FinanceSummaryService(
        records: records,
        categories: flaky,
        loadBudget: (_) async => null,
      ),
      clock: () => DateTime(2026, 10, 15, 12),
    );
    await controller.load();
    await categories.insert(
      FinanceCategory(id: 'food', name: '餐饮', type: FinanceType.expense),
    );
    await controller.load();
  });

  test(
    'category lookup failure is reported through error, not thrown',
    () async {
      final errors = <Object?>[];
      controller.addListener(() => errors.add(controller.error));
      flaky.failNextWith(StateError('category store offline'));

      await expectLater(
        controller.addRecord(categoryId: 'food', amountText: '12.30'),
        completes,
      );

      expect(controller.error, isStateError);
      expect(errors.last, isStateError);
      expect(controller.monthRecords, isEmpty);
    },
  );

  test('unknown category sets error and notifies listeners', () async {
    final errors = <Object?>[];
    controller.addListener(() => errors.add(controller.error));

    await controller.addRecord(categoryId: 'ghost', amountText: '5');

    expect(controller.error, isStateError);
    expect(errors.single, isStateError);
  });

  test('a later valid submission succeeds after earlier failures', () async {
    flaky.failNextWith(StateError('category store offline'));
    await controller.addRecord(categoryId: 'food', amountText: 'oops');
    expect(controller.error, isNotNull);

    await controller.addRecord(categoryId: 'ghost', amountText: '5');
    expect(controller.error, isNotNull);

    await controller.addRecord(categoryId: 'food', amountText: '12.30');

    expect(controller.error, isNull);
    expect(controller.monthRecords, hasLength(1));
    expect(controller.monthRecords.single.amountMinor, 1230);
    expect(controller.monthRecords.single.categoryId, 'food');
  });

  test('amount validation failure is surfaced and stores nothing', () async {
    await controller.addRecord(categoryId: 'food', amountText: '-1');

    expect(controller.error, isFormatException);
    expect(controller.monthRecords, isEmpty);
  });

  test('clock returning an invalid timestamp is surfaced as error', () async {
    var brokenClock = false;
    final broken = FinanceController(
      records: records,
      categories: categories,
      service: FinanceSummaryService(
        records: records,
        categories: categories,
        loadBudget: (_) async => null,
      ),
      clock: () =>
          brokenClock ? DateTime.utc(2026, 10, 15) : DateTime(2026, 10, 15, 12),
    );
    brokenClock = true;
    await broken.load();
    await expectLater(
      broken.addRecord(categoryId: 'food', amountText: '1'),
      completes,
    );

    expect(broken.error, isArgumentError);
    expect(broken.monthRecords, isEmpty);
  });
}
