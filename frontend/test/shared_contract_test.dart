import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:student_life_rpg/shared/models/schedule_item.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';

void main() {
  final start = DateTime(2026, 10, 10, 8, 0, 0, 123, 456);
  final end = DateTime(2026, 10, 10, 9);

  test('TimeRange JSON round trip preserves microseconds', () {
    final original = TimeRange(start: start, end: end);
    final json =
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>;
    final restored = TimeRange.fromJson(json);
    expect(restored.start, start);
    expect(restored.end, end);
    expect(restored.start.microsecond, 456);
    expect(restored.start.isUtc, isFalse);
  });

  test('TimeRange rejects equal, reversed and UTC endpoints', () {
    expect(() => TimeRange(start: start, end: start), throwsArgumentError);
    expect(() => TimeRange(start: end, end: start), throwsArgumentError);
    expect(
      () => TimeRange(start: start.toUtc(), end: end),
      throwsArgumentError,
    );
    expect(
      () => TimeRange(start: start, end: end.toUtc()),
      throwsArgumentError,
    );
  });

  test('TimeRange accepts leap day and cross-day ranges', () {
    final range = TimeRange.fromJson({
      'start': '2024-02-29T23:30:00',
      'end': '2024-03-01T00:30:00.1',
    });
    expect(range.start, DateTime(2024, 2, 29, 23, 30));
    expect(range.end, DateTime(2024, 3, 1, 0, 30, 0, 100));
  });

  test('TimeRange JSON rejects invalid dates and timezone values', () {
    for (final invalid in [
      '2026-02-29T08:00:00',
      '2026-10-32T08:00:00',
      '2026-10-10T24:00:00',
      '2026-10-10T08:60:00',
      '2026-10-10T08:00:60',
      '2026-10-10T08:00:00Z',
      '2026-10-10T08:00:00+08:00',
      '2026-10-10',
    ]) {
      expect(
        () => TimeRange.fromJson({
          'start': invalid,
          'end': '2026-11-01T09:00:00',
        }),
        throwsFormatException,
        reason: invalid,
      );
    }
  });

  test('TimeRange JSON rejects bad structure and reversed ranges', () {
    for (final json in <Map<String, dynamic>>[
      {},
      {'start': start.toIso8601String()},
      {'start': 123, 'end': end.toIso8601String()},
      {'start': null, 'end': end.toIso8601String()},
      {...TimeRange(start: start, end: end).toJson(), 'extra': true},
      {'start': end.toIso8601String(), 'end': start.toIso8601String()},
      {'start': start.toIso8601String(), 'end': start.toIso8601String()},
    ]) {
      expect(() => TimeRange.fromJson(json), throwsFormatException);
    }
  });

  test('ScheduleItem preserves IDs and supports every source type', () {
    final range = TimeRange(start: start, end: end);
    for (final source in ScheduleSourceType.values) {
      final item = ScheduleItem(
        id: ' item-1 ',
        sourceId: ' source-1 ',
        sourceType: source,
        title: 'Study',
        range: range,
      );
      expect(item.id, ' item-1 ');
      expect(item.sourceId, ' source-1 ');
      expect(item.sourceType, source);
      expect(item.range, same(range));
    }
  });

  test('ScheduleItem rejects blank IDs and title', () {
    final range = TimeRange(start: start, end: end);
    for (final blank in ['', '   ', '\t\n']) {
      expect(
        () => ScheduleItem(
          id: blank,
          sourceId: 's1',
          sourceType: ScheduleSourceType.task,
          title: 'Study',
          range: range,
        ),
        throwsArgumentError,
      );
      expect(
        () => ScheduleItem(
          id: 'i1',
          sourceId: blank,
          sourceType: ScheduleSourceType.task,
          title: 'Study',
          range: range,
        ),
        throwsArgumentError,
      );
      expect(
        () => ScheduleItem(
          id: 'i1',
          sourceId: 's1',
          sourceType: ScheduleSourceType.task,
          title: blank,
          range: range,
        ),
        throwsArgumentError,
      );
    }
  });
}
