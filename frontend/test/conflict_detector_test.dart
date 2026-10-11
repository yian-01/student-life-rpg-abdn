import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/schedule/services/conflict_detector.dart';
import 'package:student_life_rpg/shared/models/schedule_item.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';

TimeRange range(int start, int end) => TimeRange(
  start: DateTime(2026, 10, 11, 0, start),
  end: DateTime(2026, 10, 11, 0, end),
);

ScheduleItem item(String id, int start, int end) => ScheduleItem(
  id: id,
  sourceId: 'source:$id',
  sourceType: ScheduleSourceType.event,
  title: 'Synthetic schedule example $id',
  range: range(start, end),
);

List<String> pairs(List<ConflictPair> conflicts) => [
  for (final pair in conflicts) '${pair.firstId}|${pair.secondId}',
];

void main() {
  test('overlaps is symmetric for partial intersection and containment', () {
    for (final other in [range(90, 150), range(70, 80), range(60, 120)]) {
      expect(overlaps(range(60, 120), other), isTrue);
      expect(overlaps(other, range(60, 120)), isTrue);
    }
  });

  test('touching and disjoint half-open ranges do not overlap', () {
    for (final other in [range(120, 180), range(0, 60), range(130, 180)]) {
      expect(overlaps(range(60, 120), other), isFalse);
      expect(overlaps(other, range(60, 120)), isFalse);
    }
  });

  test('empty, single and disjoint lists have no conflicts', () {
    expect(findConflicts([]), isEmpty);
    expect(findConflicts([item('a', 0, 60)]), isEmpty);
    expect(findConflicts([item('a', 0, 60), item('b', 60, 90)]), isEmpty);
  });

  test('intersection uses max start and min end including containment', () {
    final conflicts = findConflicts([
      item('z', 60, 180),
      item('a', 90, 120),
      item('m', 150, 210),
    ]);
    expect(pairs(conflicts), ['a|z', 'm|z']);
    expect(conflicts[0].overlapRange.start, range(90, 120).start);
    expect(conflicts[0].overlapRange.end, range(90, 120).end);
    expect(conflicts[1].overlapRange.start, range(150, 180).start);
    expect(conflicts[1].overlapRange.end, range(150, 180).end);
  });

  test('every pair appears once with deterministic sorting', () {
    final items = [item('c', 0, 60), item('a', 0, 60), item('b', 0, 60)];
    expect(pairs(findConflicts(items)), ['a|b', 'a|c', 'b|c']);
    expect(pairs(findConflicts(items.reversed.toList())), [
      'a|b',
      'a|c',
      'b|c',
    ]);
  });

  test('duplicate IDs are rejected even for non-overlapping items', () {
    expect(
      () => findConflicts([item('a', 0, 60), item('a', 90, 120)]),
      throwsArgumentError,
    );
  });

  test('original IDs retain whitespace and are compared without trimming', () {
    expect(pairs(findConflicts([item('a', 0, 60), item(' a ', 0, 60)])), [
      ' a |a',
    ]);
  });

  test('does not mutate input and returns an immutable result snapshot', () {
    final a = item('b', 0, 60);
    final b = item('a', 30, 90);
    final items = [a, b];
    final result = findConflicts(List.unmodifiable(items));
    expect(items, orderedEquals([a, b]));
    expect(a.range.start, range(0, 60).start);
    expect(b.range.end, range(30, 90).end);
    items.clear();
    expect(pairs(result), ['a|b']);
    expect(() => result.clear(), throwsUnsupportedError);
  });

  test('cross-day and microsecond intersections preserve full precision', () {
    final start = DateTime(2026, 10, 11, 23, 59, 59, 999, 998);
    final middle = DateTime(2026, 10, 11, 23, 59, 59, 999, 999);
    final end = DateTime(2026, 10, 12);
    ScheduleItem at(String id, DateTime from, DateTime to) => ScheduleItem(
      id: id,
      sourceId: id,
      sourceType: ScheduleSourceType.task,
      title: id,
      range: TimeRange(start: from, end: to),
    );
    final result = findConflicts([
      at('a', start, end),
      at('b', middle, DateTime(2026, 10, 12, 1)),
    ]);
    expect(result.single.overlapRange.start, middle);
    expect(result.single.overlapRange.end, end);
    expect(result.single.overlapRange.start.isUtc, isFalse);
  });

  test('all source types participate even when they share a source ID', () {
    final items = [
      for (final type in ScheduleSourceType.values)
        ScheduleItem(
          id: type.name,
          sourceId: 'same source',
          sourceType: type,
          title: type.name,
          range: range(0, 60),
        ),
    ];
    expect(pairs(findConflicts(items)), [
      'course|event',
      'course|task',
      'event|task',
    ]);
  });
}
