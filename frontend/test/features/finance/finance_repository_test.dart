import 'package:flutter_test/flutter_test.dart';

import 'controllable_category_repository.dart';
import 'package:student_life_rpg/features/finance/models/finance_category.dart';
import 'package:student_life_rpg/features/finance/models/finance_record.dart';
import 'package:student_life_rpg/features/finance/models/finance_type.dart';
import 'package:student_life_rpg/features/finance/repositories/in_memory_finance_repositories.dart';

void main() {
  late InMemoryFinanceCategoryRepository categories;
  late InMemoryFinanceRecordRepository records;

  setUp(() {
    InMemoryFinanceRecordRepository? recordRepo;
    categories = InMemoryFinanceCategoryRepository(
      referencedCategoryIds: () => recordRepo?.referencedCategoryIds() ?? {},
    );
    records = InMemoryFinanceRecordRepository(categories: categories);
    recordRepo = records;
  });

  Future<void> seed() async {
    await categories.insert(
      FinanceCategory(id: 'food', name: '餐饮', type: FinanceType.expense),
    );
    await categories.insert(
      FinanceCategory(id: 'pay', name: '生活费', type: FinanceType.income),
    );
  }

  test('CRUD, type matching and referenced category protection', () async {
    await seed();
    final record = FinanceRecord(
      id: 'r1',
      categoryId: 'food',
      type: FinanceType.expense,
      amountMinor: 100,
      occurredAt: DateTime(2026, 10, 15, 12),
    );
    await records.insert(record);
    expect((await records.getById('r1'))?.amountMinor, 100);
    expect(await records.getById('missing'), isNull);

    expect(
      records.insert(
        FinanceRecord(
          id: 'r2',
          categoryId: 'missing',
          type: FinanceType.expense,
          amountMinor: 1,
          occurredAt: DateTime(2026, 10, 15),
        ),
      ),
      throwsStateError,
    );
    expect(
      records.insert(
        FinanceRecord(
          id: 'r2',
          categoryId: 'pay',
          type: FinanceType.expense,
          amountMinor: 1,
          occurredAt: DateTime(2026, 10, 15),
        ),
      ),
      throwsStateError,
    );
    expect(
      categories.update(
        FinanceCategory(id: 'food', name: '餐饮', type: FinanceType.income),
      ),
      throwsStateError,
    );
    expect(categories.remove('food'), throwsStateError);
    expect(await categories.remove('missing'), isFalse);

    await records.remove('r1');
    expect(await categories.remove('food'), isTrue);
    expect(records.update(record), throwsStateError);
  });

  group('async category validation races', () {
    late ControllableCategoryRepository gate;

    FinanceRecord build(String id, {int amountMinor = 100}) => FinanceRecord(
      id: id,
      categoryId: 'food',
      type: FinanceType.expense,
      amountMinor: amountMinor,
      occurredAt: DateTime(2026, 10, 15),
    );

    setUp(() async {
      InMemoryFinanceRecordRepository? recordRepo;
      categories = InMemoryFinanceCategoryRepository(
        referencedCategoryIds: () => recordRepo?.referencedCategoryIds() ?? {},
      );
      gate = ControllableCategoryRepository(categories);
      gate.autoRelease();
      records = InMemoryFinanceRecordRepository(categories: gate);
      recordRepo = records;
      await seed();
    });

    test('concurrent inserts of the same id: only one succeeds', () async {
      gate.block();
      final first = records.insert(build('dup'));
      final second = records.insert(build('dup'));
      await gate.reach(2);

      await expectLater(first, completes);
      await expectLater(second, throwsStateError);

      expect(
        (await records.list()).where((item) => item.id == 'dup'),
        hasLength(1),
      );
      expect((await records.getById('dup'))?.amountMinor, 100);
    });

    test('update in flight does not resurrect a removed record', () async {
      await records.insert(build('r1'));
      gate.block();

      final pending = records.update(build('r1', amountMinor: 999));
      expect(await records.remove('r1'), isTrue);
      await gate.reach(1);

      await expectLater(pending, throwsStateError);
      expect(await records.getById('r1'), isNull);
      expect(await records.list(), isEmpty);
    });

    test('concurrent inserts of different ids keep both records', () async {
      gate.block();
      final futures = [records.insert(build('a')), records.insert(build('b'))];
      await gate.reach(2);
      await Future.wait(futures);

      expect((await records.list()).map((item) => item.id).toSet(), {'a', 'b'});
    });
  });

  test(
    'listForMonth uses half-open local month and sorts by time then id',
    () async {
      await seed();
      final first = FinanceRecord(
        id: 'b',
        categoryId: 'food',
        type: FinanceType.expense,
        amountMinor: 1,
        occurredAt: DateTime(2026, 10, 1),
      );
      final second = FinanceRecord(
        id: 'a',
        categoryId: 'food',
        type: FinanceType.expense,
        amountMinor: 2,
        occurredAt: DateTime(2026, 10, 1),
      );
      final monthEnd = FinanceRecord(
        id: 'end',
        categoryId: 'food',
        type: FinanceType.expense,
        amountMinor: 3,
        occurredAt: DateTime(2026, 10, 31, 23, 59, 59, 999, 999),
      );
      final nextMonth = FinanceRecord(
        id: 'next',
        categoryId: 'food',
        type: FinanceType.expense,
        amountMinor: 4,
        occurredAt: DateTime(2026, 11, 1),
      );
      final previous = FinanceRecord(
        id: 'prev',
        categoryId: 'food',
        type: FinanceType.expense,
        amountMinor: 5,
        occurredAt: DateTime(2026, 9, 30, 23, 59, 59),
      );
      for (final item in [second, first, monthEnd, nextMonth, previous]) {
        await records.insert(item);
      }

      final october = await records.listForMonth(2026, 10);
      expect(october.map((item) => item.id), ['a', 'b', 'end']);
      expect((await records.listForMonth(2026, 11)).map((item) => item.id), [
        'next',
      ]);
    },
  );
}
