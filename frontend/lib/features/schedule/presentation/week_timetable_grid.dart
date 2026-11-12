import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../shared/models/schedule_item.dart';
import '../services/week_timetable_layout.dart';

const _dateHeight = 52.0;
const _scrollbarSpace = 10.0;
const _hourHeight = 68.0;
const _axisWidth = 52.0;

class WeekTimetableGrid extends StatefulWidget {
  const WeekTimetableGrid({
    super.key,
    required this.dates,
    required this.items,
    required this.onSelectDate,
    required this.onOpen,
  });

  final List<DateTime> dates;
  final List<List<ScheduleItem>> items;
  final ValueChanged<DateTime> onSelectDate;
  final ValueChanged<ScheduleItem> onOpen;

  @override
  State<WeekTimetableGrid> createState() => _WeekTimetableGridState();
}

class _WeekTimetableGridState extends State<WeekTimetableGrid> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final columns = [
      for (final (i, date) in widget.dates.indexed)
        placeWeekDay(date, widget.items[i]),
    ];
    var firstHour = 8;
    var lastHour = 20;
    for (final item in columns.expand((column) => column)) {
      firstHour = math.min(firstHour, item.start ~/ 60);
      lastHour = math.max(lastHour, (item.end / 60).ceil());
    }
    final height = (lastHour - firstHour) * _hourHeight;
    final theme = Theme.of(context);
    final gridLine = theme.colorScheme.outlineVariant;
    final today = DateTime.now();

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - _axisWidth;
        final baseWidth = math.max(112.0, available / widget.dates.length);
        final widths = [
          for (final day in columns)
            math.max(
              baseWidth,
              day.fold(1, (count, item) => math.max(count, item.laneCount)) *
                  76.0,
            ),
        ];
        final canScroll = widths.reduce((a, b) => a + b) > available + 0.1;
        return Scrollbar(
          controller: _vertical,
          notificationPredicate: (event) => event.metrics.axis == Axis.vertical,
          child: SingleChildScrollView(
            controller: _vertical,
            primary: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _axisWidth,
                  height: _scrollbarSpace + _dateHeight + height,
                  child: Stack(
                    children: [
                      Positioned(
                        top: _scrollbarSpace + 15,
                        left: 5,
                        child: Text('时间', style: theme.textTheme.labelMedium),
                      ),
                      for (var hour = firstHour; hour < lastHour; hour++)
                        Positioned(
                          top:
                              _scrollbarSpace +
                              _dateHeight +
                              (hour - firstHour) * _hourHeight +
                              4,
                          left: 4,
                          child: Text(
                            weekClock(hour * 60),
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Scrollbar(
                    controller: _horizontal,
                    thumbVisibility: canScroll,
                    scrollbarOrientation: ScrollbarOrientation.top,
                    notificationPredicate: (event) =>
                        event.metrics.axis == Axis.horizontal,
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.stylus,
                        },
                      ),
                      child: SingleChildScrollView(
                        key: const Key('week-grid-horizontal'),
                        controller: _horizontal,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(top: _scrollbarSpace),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final (index, date) in widget.dates.indexed)
                              SizedBox(
                                width: widths[index],
                                child: Column(
                                  children: [
                                    SizedBox(
                                      height: _dateHeight,
                                      width: double.infinity,
                                      child: TextButton(
                                        key: ValueKey(
                                          'week-date-${date.toIso8601String()}',
                                        ),
                                        onPressed: () =>
                                            widget.onSelectDate(date),
                                        style: DateUtils.isSameDay(date, today)
                                            ? TextButton.styleFrom(
                                                backgroundColor: theme
                                                    .colorScheme
                                                    .primaryContainer,
                                              )
                                            : null,
                                        child: Text(
                                          '周${'一二三四五六日'[date.weekday - 1]} · ${date.month}/${date.day}',
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: height,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          border: Border(
                                            right: BorderSide(color: gridLine),
                                          ),
                                        ),
                                        child: Stack(
                                          children: [
                                            for (
                                              var hour = firstHour;
                                              hour <= lastHour;
                                              hour++
                                            )
                                              Positioned(
                                                left: 0,
                                                right: 0,
                                                top: math.min(
                                                  (hour - firstHour) *
                                                      _hourHeight,
                                                  height - 1,
                                                ),
                                                child: Divider(
                                                  height: 1,
                                                  color: gridLine,
                                                ),
                                              ),
                                            for (final placement
                                                in columns[index])
                                              Positioned(
                                                top:
                                                    (placement.start -
                                                        firstHour * 60) *
                                                    _hourHeight /
                                                    60,
                                                left:
                                                    placement.lane *
                                                        widths[index] /
                                                        placement.laneCount +
                                                    2,
                                                width:
                                                    widths[index] /
                                                        placement.laneCount -
                                                    4,
                                                height:
                                                    (placement.end -
                                                        placement.start) *
                                                    _hourHeight /
                                                    60,
                                                child: _GridEntry(
                                                  placement: placement,
                                                  onOpen: () => widget.onOpen(
                                                    placement.item,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String weekClock(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

String weekItemType(ScheduleSourceType type) => switch (type) {
  ScheduleSourceType.course => '课程',
  ScheduleSourceType.exam => '考试',
  ScheduleSourceType.task => '任务',
  ScheduleSourceType.event => '事件',
};

class _GridEntry extends StatelessWidget {
  const _GridEntry({required this.placement, required this.onOpen});

  final WeekPlacement placement;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final item = placement.item;
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (item.sourceType) {
      ScheduleSourceType.course => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      ScheduleSourceType.exam => (
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      ScheduleSourceType.task => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      ScheduleSourceType.event => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
    };
    final time = '${weekClock(placement.start)}–${weekClock(placement.end)}';
    final label =
        '${weekItemType(item.sourceType)} · ${item.title} · $time'
        '${item.location == null ? '' : ' · ${item.location}'}';
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onOpen,
      child: Tooltip(
        message: label,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(7),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            child: LayoutBuilder(
              builder: (context, constraints) => Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: constraints.maxHeight >= 32 ? 4 : 0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (constraints.maxHeight >= 14)
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          height: 1.1,
                        ),
                      ),
                    if (constraints.maxHeight >= 42)
                      Text(
                        time,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 10,
                          height: 1.2,
                        ),
                      ),
                    if (constraints.maxHeight >= 61 && item.location != null)
                      Text(
                        item.location!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 11,
                          height: 1.2,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
