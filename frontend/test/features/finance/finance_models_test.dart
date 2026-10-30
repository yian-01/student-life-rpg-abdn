import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/finance/models/finance_category.dart';
import 'package:student_life_rpg/features/finance/models/finance_record.dart';
import 'package:student_life_rpg/features/finance/models/finance_type.dart';

void main() {
  final occurredAt = DateTime(2026, 10, 11, 8, 30, 0, 123, 456);

  FinanceCategory category() =>
      FinanceCategory(id: 'food', name: '餐饮', type: FinanceType.expense);

  FinanceRecord record() => FinanceRecord(
    id: 'r1',
    categoryId: 'food',
    type: FinanceType.expense,
    amountMinor: 350,
    occurredAt: occurredAt,
    note: 'lunch',
  );

  test('JSON round trip keeps IDs, local time and null note', () {
    final restoredCategory = FinanceCategory.fromJson(category().toJson());
    expect(restoredCategory.id, 'food');
    expect(restoredCategory.type, FinanceType.expense);

    final original = record();
    final restored = FinanceRecord.fromJson(original.toJson());
    expect(restored.occurredAt, occurredAt);
    expect(restored.occurredAt.isUtc, isFalse);
    expect(restored.note, 'lunch');
    expect(
      FinanceRecord.fromJson(record().copyWith(note: null).toJson()).note,
      isNull,
    );
    expect(record().copyWith(note: null).toJson().containsKey('note'), isTrue);
  });

  test('fromJson allows missing nullable note and rejects unknown keys', () {
    expect(
      FinanceRecord.fromJson({
        'id': 'r1',
        'categoryId': 'food',
        'type': 'expense',
        'amountMinor': 1,
        'occurredAt': '2026-10-11T08:30:00',
      }).note,
      isNull,
    );
    expect(
      () => FinanceCategory.fromJson({...category().toJson(), 'extra': true}),
      throwsFormatException,
    );
    expect(
      () => FinanceRecord.fromJson({...record().toJson(), 'extra': true}),
      throwsFormatException,
    );
    expect(
      () => FinanceRecord.fromJson({
        ...record().toJson(),
        'occurredAt': '2026-02-29T08:00:00',
      }),
      throwsFormatException,
    );
  });

  test('constructors reject blank IDs, utc time and non-positive amounts', () {
    expect(
      () => FinanceCategory(id: '  ', name: 'n', type: FinanceType.income),
      throwsArgumentError,
    );
    expect(
      () => FinanceRecord(
        id: 'r1',
        categoryId: 'food',
        type: FinanceType.expense,
        amountMinor: 0,
        occurredAt: occurredAt,
      ),
      throwsArgumentError,
    );
    expect(
      () => FinanceRecord(
        id: 'r1',
        categoryId: 'food',
        type: FinanceType.expense,
        amountMinor: 1,
        occurredAt: occurredAt.toUtc(),
      ),
      throwsArgumentError,
    );
  });

  test('copyWith cannot change id', () {
    expect(category().copyWith(name: 'x').id, 'food');
    expect(record().copyWith(amountMinor: 1).id, 'r1');
  });
}
