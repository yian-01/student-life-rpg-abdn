import 'package:flutter/material.dart';

import '../../../app/data/campus_data.dart';
import '../../../shared/models/schedule_item.dart';
import '../../academic/models/semester.dart';
import '../../academic/presentation/assignment_exam_page.dart';
import '../../academic/services/course_occurrence_service.dart';
import '../repositories/task_repository.dart';
import '../services/day_schedule_service.dart';
import 'schedule_record_page.dart';
import 'task_editor_dialog.dart';

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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('周课表')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
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
            FutureBuilder<_Week>(
              future: _week,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator();
                }
                final result = snapshot.data;
                if (result == null) {
                  return TextButton(
                    onPressed: () => _select(_monday),
                    child: const Text('读取失败，重试'),
                  );
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 960
                        ? 7
                        : constraints.maxWidth >= 600
                        ? 3
                        : 1;
                    final width =
                        (constraints.maxWidth - (columns - 1) * 8) / columns;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (i, day) in result.days.indexed)
                          SizedBox(
                            width: width,
                            child: _section(
                              context,
                              _dayAt(_monday, i),
                              day,
                              result.semesters,
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    ),
  );

  Widget _section(
    BuildContext context,
    DateTime date,
    DaySchedule day,
    List<Semester>? semesters,
  ) {
    final next = _dayAt(date, 1);
    final label = [
      for (final term in semesters ?? const <Semester>[])
        if (term.containsDate(date))
          if (academicWeekNumber(term.week1Monday, date) case final week?)
            '${term.name} · 第 $week 周',
    ].join('\n');
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context, date),
              child: Text(
                '周${'一二三四五六日'[date.weekday - 1]} · ${date.month}/${date.day}',
              ),
            ),
            if (label.isNotEmpty) Text(label),
            if (day.errors.isNotEmpty)
              TextButton(
                onPressed: () => _select(_monday),
                child: const Text('部分数据读取失败 · 重试'),
              ),
            if (day.items.isEmpty && day.errors.isEmpty) const Text('无安排'),
            for (final item in day.items)
              InkWell(
                onTap: () => _open(item),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${_time(item.range.start.isBefore(date) ? date : item.range.start)}–'
                    '${item.range.end.isBefore(next) ? _time(item.range.end) : '24:00'}\n'
                    '${item.title}${item.location == null ? '' : '\n${item.location}'}',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _date(DateTime date) => formatLocalDateTime(date).split(' ').first;

String _time(DateTime date) => formatLocalDateTime(date).split(' ').last;
