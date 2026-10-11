import '../../../shared/models/schedule_item.dart';
import '../../../shared/models/time_range.dart';

/// One conflicting pair of schedule item IDs and their complete intersection.
class ConflictPair {
  ConflictPair({
    required this.firstId,
    required this.secondId,
    required this.overlapRange,
  });

  final String firstId;
  final String secondId;
  final TimeRange overlapRange;
}

/// Tests strict intersection of local half-open ranges [start, end).
bool overlaps(TimeRange a, TimeRange b) =>
    a.start.isBefore(b.end) && b.start.isBefore(a.end);

/// Returns each conflicting pair once, ordered by its original item IDs.
///
/// Duplicate item IDs are invalid even when the items do not overlap.
/// Input order and source ranges are preserved. No source entity is modified.
List<ConflictPair> findConflicts(List<ScheduleItem> items) {
  final ids = <String>{};
  for (final item in items) {
    if (!ids.add(item.id)) {
      throw ArgumentError.value(item.id, 'items', 'Duplicate ScheduleItem ID.');
    }
  }

  final result = <ConflictPair>[];
  for (var i = 0; i < items.length; i++) {
    for (var j = i + 1; j < items.length; j++) {
      final a = items[i];
      final b = items[j];
      if (!overlaps(a.range, b.range)) continue;
      final aFirst = a.id.compareTo(b.id) < 0;
      result.add(
        ConflictPair(
          firstId: aFirst ? a.id : b.id,
          secondId: aFirst ? b.id : a.id,
          overlapRange: TimeRange(
            start: a.range.start.isAfter(b.range.start)
                ? a.range.start
                : b.range.start,
            end: a.range.end.isBefore(b.range.end) ? a.range.end : b.range.end,
          ),
        ),
      );
    }
  }
  result.sort((a, b) {
    final first = a.firstId.compareTo(b.firstId);
    return first != 0 ? first : a.secondId.compareTo(b.secondId);
  });
  return List.unmodifiable(result);
}
