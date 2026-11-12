import '../../../shared/models/schedule_item.dart';

typedef WeekPlacement = ({
  ScheduleItem item,
  int start,
  int end,
  int lane,
  int laneCount,
});

int _minute(DateTime value) => value.hour * 60 + value.minute;

/// Split cross-midnight items at the civil-day boundary and give overlapping
/// items separate lanes. Adjacent items share the same lane.
List<WeekPlacement> placeWeekDay(DateTime date, Iterable<ScheduleItem> items) {
  final day = DateTime(date.year, date.month, date.day);
  final next = DateTime(date.year, date.month, date.day + 1);
  final slices =
      [
        for (final item in items)
          if (item.range.start.isBefore(next) && item.range.end.isAfter(day))
            (
              item: item,
              start: item.range.start.isBefore(day)
                  ? 0
                  : _minute(item.range.start),
              end: item.range.end.isBefore(next)
                  ? _minute(item.range.end)
                  : 1440,
            ),
      ]..sort((a, b) {
        final order = a.start.compareTo(b.start);
        return order == 0 ? a.item.id.compareTo(b.item.id) : order;
      });

  final result = <WeekPlacement>[];
  final activeGroup = <({ScheduleItem item, int start, int end, int lane})>[];
  final laneEnds = <int>[];
  var groupEnd = 0;
  void flushGroup() {
    for (final slice in activeGroup) {
      result.add((
        item: slice.item,
        start: slice.start,
        end: slice.end,
        lane: slice.lane,
        laneCount: laneEnds.length,
      ));
    }
    activeGroup.clear();
    laneEnds.clear();
  }

  for (final slice in slices) {
    final end = slice.end > slice.start ? slice.end : slice.start + 1;
    if (slice.start >= groupEnd) flushGroup();
    var lane = laneEnds.indexWhere((end) => end <= slice.start);
    if (lane == -1) {
      lane = laneEnds.length;
      laneEnds.add(end);
    } else {
      laneEnds[lane] = end;
    }
    activeGroup.add((
      item: slice.item,
      start: slice.start,
      end: end,
      lane: lane,
    ));
    groupEnd = end > groupEnd ? end : groupEnd;
  }
  flushGroup();
  return result;
}
