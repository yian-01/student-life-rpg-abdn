import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../app/data/campus_data.dart';
import '../../../shared/models/schedule_item.dart';
import '../../academic/models/semester.dart';
import '../../academic/presentation/assignment_exam_page.dart';
import '../../academic/services/course_occurrence_service.dart';
import '../repositories/task_repository.dart';
import '../services/day_schedule_service.dart';
import '../services/calendar_export.dart';
import 'schedule_record_page.dart';
import 'task_editor_dialog.dart';
import 'week_timetable_grid.dart';

DateTime _dayAt(DateTime date, int offset) =>
    DateTime(date.year, date.month, date.day + offset);

class WeekSchedulePage extends StatefulWidget {
  const WeekSchedulePage({
    super.key,
    required this.data,
    required this.tasks,
    required this.initialDate,
  });
  final CampusData data;
  final TaskRepository tasks;
  final DateTime initialDate;

  @override
  State<WeekSchedulePage> createState() => _WeekSchedulePageState();
}

typedef _Week = ({List<DaySchedule> days, List<Semester>? semesters});

class _WeekSchedulePageState extends State<WeekSchedulePage> {
  late DateTime _monday = _dayAt(
    widget.initialDate,
    1 - widget.initialDate.weekday,
  );
  late Future<_Week> _week = _load(_monday);
  bool _opening = false;
  bool _exporting = false;
  ScheduleSourceType? _filter;

  Future<_Week> _load(DateTime monday) async {
    final service = widget.data.schedule(widget.tasks);
    final days = await Future.wait([
      for (var day = 0; day < 7; day++) service.loadDay(_dayAt(monday, day)),
    ]);
    List<Semester>? semesters;
    try {
      semesters = await widget.data.semesters.list();
    } catch (_) {
      // Daily sections report source failures and keep the healthy items.
    }
    return (days: days, semesters: semesters);
  }

  void _select(DateTime date) {
    setState(() {
      _monday = _dayAt(date, 1 - date.weekday);
      _week = _load(_monday);
    });
  }

  Future<void> _open(ScheduleItem item) async {
    if (_opening) return;
    _opening = true;
    try {
      if (item.sourceType == ScheduleSourceType.task) {
        final task = await widget.tasks.getById(item.sourceId);
        if (!mounted) return;
        if (task == null) throw StateError('Task was deleted');
        await editExistingTask(context, task, widget.tasks.update);
      } else {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => ScheduleRecordPage(data: widget.data, item: item),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开该事项，请刷新。')));
      }
    } finally {
      _opening = false;
      if (mounted) _select(_monday);
    }
  }

  Future<void> _export(List<List<ScheduleItem>> items) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = exportCalendar(items.expand((day) => day), DateTime.now());
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: '导出周课表',
        fileName: 'student-life-week-${_date(_monday)}.ics',
        bytes: bytes,
        lockParentWindow: true,
      );
      if (mounted && saved != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已保存日历文件。')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('日历导出失败，请检查保存位置。')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _jumpToWeek() async {
    final target = await showDatePicker(
      context: context,
      initialDate: _monday,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200, 12, 31),
      helpText: '选择一周中的任意日期',
    );
    if (mounted && target != null) _select(target);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('周课表'),
      actions: [
        IconButton(
          tooltip: '跳到指定周',
          onPressed: _jumpToWeek,
          icon: const Icon(Icons.calendar_month_outlined),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1500),
        child: Column(
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  tooltip: '上一周',
                  onPressed: () => _select(_dayAt(_monday, -7)),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('${_date(_monday)} — ${_date(_dayAt(_monday, 6))}'),
                IconButton(
                  tooltip: '下一周',
                  onPressed: () => _select(_dayAt(_monday, 7)),
                  icon: const Icon(Icons.chevron_right),
                ),
                TextButton(
                  onPressed: () => _select(DateTime.now()),
                  child: const Text('本周'),
                ),
              ],
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final type in <ScheduleSourceType?>[
                    null,
                    ...ScheduleSourceType.values,
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(type == null ? '全部事项' : weekItemType(type)),
                        selected: _filter == type,
                        onSelected: (_) => setState(() => _filter = type),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<_Week>(
                future: _week,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Align(
                      alignment: Alignment.topCenter,
                      child: LinearProgressIndicator(),
                    );
                  }
                  final result = snapshot.data;
                  if (result == null) {
                    return Center(
                      child: TextButton(
                        onPressed: () => _select(_monday),
                        child: const Text('读取失败，重试'),
                      ),
                    );
                  }
                  final dates = [
                    for (var i = 0; i < 7; i++) _dayAt(_monday, i),
                  ];
                  final items = [
                    for (final day in result.days)
                      day.items
                          .where(
                            (item) =>
                                _filter == null || item.sourceType == _filter,
                          )
                          .toList(),
                  ];
                  final termWeeks = {
                    for (final term in result.semesters ?? const <Semester>[])
                      for (final date in dates)
                        if (term.containsDate(date))
                          if (academicWeekNumber(term.week1Monday, date)
                              case final week?)
                            '${term.name} · 第 $week 周',
                  };
                  final count = items
                      .expand((day) => day)
                      .map((item) => item.id)
                      .toSet()
                      .length;
                  final canExport =
                      count > 0 &&
                      !result.days.any(
                        (day) => day.errors.keys.any(
                          (source) => source != ScheduleDataSource.assignments,
                        ),
                      );
                  return Column(
                    children: [
                      if (result.days.any((day) => day.errors.isNotEmpty))
                        TextButton(
                          onPressed: () => _select(_monday),
                          child: const Text('部分数据读取失败 · 重试'),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Text(
                                [
                                  ...termWeeks,
                                  count == 0 ? '本周无匹配事项' : '$count 项安排',
                                ].join('  ·  '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '导出本周日历（ICS）',
                            onPressed: canExport && !_exporting
                                ? () => _export(items)
                                : null,
                            icon: const Icon(Icons.file_download_outlined),
                          ),
                        ],
                      ),
                      Expanded(
                        child: WeekTimetableGrid(
                          key: ValueKey(_monday),
                          dates: dates,
                          items: items,
                          onSelectDate: (date) => Navigator.pop(context, date),
                          onOpen: _open,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _date(DateTime date) => formatLocalDateTime(date).split(' ').first;
