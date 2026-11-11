import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_data.dart';
import '../../app/data/campus_data.dart';
import '../../app/module_body.dart';
import '../../shared/models/schedule_item.dart';
import '../academic/models/assignment.dart';
import '../academic/models/course.dart';
import '../academic/models/exam.dart';
import '../academic/presentation/assignment_exam_page.dart';
import '../academic/presentation/course_detail_page.dart';
import '../finance/models/finance_category.dart';
import '../finance/models/finance_record.dart';
import '../schedule/models/event.dart';
import '../schedule/models/task.dart';
import '../schedule/presentation/schedule_record_page.dart';
import '../schedule/presentation/task_editor_dialog.dart';
import '../schedule/repositories/task_repository.dart';
import '../schedule/services/task_schedule_adapter.dart';

enum TodoPeriod {
  today('今天'),
  week('七天内'),
  overdue('逾期'),
  all('全部未完成');

  const TodoPeriod(this.label);
  final String label;
}

enum _Kind {
  task('任务'),
  assignment('作业'),
  exam('考试'),
  course('课程'),
  event('事件'),
  finance('账目');

  const _Kind(this.label);
  final String label;
}

typedef _Entry = ({
  _Kind kind,
  String id,
  String title,
  String? courseId,
  DateTime? date,
  Object record,
  String extra,
});
typedef _Results = ({
  List<_Entry> entries,
  List<_Kind> failed,
  Map<String, String> courses,
  CampusData? data,
  TaskRepository? tasks,
});

DateTime _day(DateTime value, [int offset = 0]) =>
    DateTime(value.year, value.month, value.day + offset);

bool matchesTodoPeriod(Object record, TodoPeriod period, DateTime now) {
  final start = _day(now);
  final end = _day(now, period == TodoPeriod.today ? 1 : 7);
  bool inWindow(DateTime? time) =>
      time != null && !time.isBefore(start) && time.isBefore(end);
  switch (record) {
    case Task():
      if (record.isCompleted) return false;
      if (period == TodoPeriod.all) return true;
      if (period == TodoPeriod.overdue)
        return record.dueAt?.isBefore(now) ?? false;
      final range = record.scheduledRange;
      return inWindow(record.dueAt) ||
          (range != null &&
              range.start.isBefore(end) &&
              range.end.isAfter(start));
    case Assignment():
      if (record.status == AssignmentStatus.submitted) return false;
      if (period == TodoPeriod.all) return true;
      if (period == TodoPeriod.overdue) return record.dueAt.isBefore(now);
      return inWindow(record.dueAt);
    case Exam():
      if (period == TodoPeriod.overdue || !record.range.end.isAfter(now))
        return false;
      return record.range.start.isBefore(
        period == TodoPeriod.today ? end : _day(now, 7),
      );
    default:
      return false;
  }
}

class LocalRecordsPage extends StatefulWidget {
  const LocalRecordsPage({
    super.key,
    this.search = false,
    this.clock = DateTime.now,
  });
  final bool search;
  final DateTime Function() clock;

  @override
  State<LocalRecordsPage> createState() => _LocalRecordsPageState();
}

class _LocalRecordsPageState extends State<LocalRecordsPage>
    with WidgetsBindingObserver {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  late Future<_Results> _future = _load();
  Timer? _debounce;
  TodoPeriod _period = TodoPeriod.today;
  _Kind? _kind;
  String? _course;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _query.dispose();
    _scroll.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() => setState(() => _future = _load());

  Future<_Results> _load() async {
    final failed = <_Kind>[];
    final entries = <_Entry>[];
    final courses = <String, String>{};
    CampusData? data;
    TaskRepository? tasks;

    Future<void> read(_Kind kind, Future<void> Function() action) async {
      try {
        await action();
      } catch (_) {
        failed.add(kind);
      }
    }

    await read(_Kind.task, () async {
      final repo = tasks = await AppData.tasks();
      for (final task in await repo.list()) {
        entries.add((
          kind: _Kind.task,
          id: task.id,
          title: task.title,
          date: task.dueAt ?? task.scheduledRange?.start,
          courseId: null,
          record: task,
          extra: task.note ?? '',
        ));
      }
    });

    try {
      data = await AppData.campus();
    } catch (_) {
      failed.addAll([
        _Kind.course,
        _Kind.assignment,
        _Kind.exam,
        if (widget.search) ...[_Kind.event, _Kind.finance],
      ]);
    }
    final campus = data;
    if (campus != null) {
      await read(_Kind.course, () async {
        for (final course in await campus.courses.list()) {
          courses[course.id] = course.name;
          if (widget.search)
            entries.add((
              kind: _Kind.course,
              id: course.id,
              title: course.name,
              date: null,
              courseId: course.id,
              record: course,
              extra: course.teacher ?? '',
            ));
        }
      });
      await read(_Kind.assignment, () async {
        for (final row in await campus.assignments.list()) {
          entries.add((
            kind: _Kind.assignment,
            id: row.id,
            title: row.title,
            date: row.dueAt,
            courseId: row.courseId,
            record: row,
            extra: row.description ?? '',
          ));
        }
      });
      await read(_Kind.exam, () async {
        for (final row in await campus.exams.list()) {
          entries.add((
            kind: _Kind.exam,
            id: row.id,
            title: row.title,
            date: row.range.start,
            courseId: row.courseId,
            record: row,
            extra: row.location ?? '',
          ));
        }
      });
      if (widget.search) {
        await read(_Kind.event, () async {
          for (final row in await campus.events.list()) {
            entries.add((
              kind: _Kind.event,
              id: row.id,
              title: row.title,
              date: row.range.start,
              courseId: null,
              record: row,
              extra: row.description ?? '',
            ));
          }
        });
        await read(_Kind.finance, () async {
          final names = <String, FinanceCategory>{
            for (final c in await campus.categories.list()) c.id: c,
          };
          for (final row in await campus.records.list()) {
            entries.add((
              kind: _Kind.finance,
              id: row.id,
              title: names[row.categoryId]?.name ?? row.categoryId,
              date: row.occurredAt,
              courseId: null,
              record: row,
              extra: row.note ?? '',
            ));
          }
        });
      }
    }

    return (
      entries: entries,
      failed: failed,
      courses: courses,
      data: data,
      tasks: tasks,
    );
  }

  Future<void> _open(_Entry entry, _Results data) async {
    if (_opening) return;
    _opening = true;
    final navigator = Navigator.of(context);
    final campus = data.data;
    try {
      switch (entry.record) {
        case final Task task:
          final tasks = data.tasks!;
          final current = await tasks.getById(task.id);
          if (!mounted) return;
          if (current == null) throw StateError('Missing task');
          await editExistingTask(context, current, tasks.update);
        case final Course course:
          await navigator.push<void>(
            MaterialPageRoute(
              builder: (_) => CourseDetailPage(data: campus!, id: course.id),
            ),
          );
        case final Assignment assignment:
          await navigator.push<void>(
            MaterialPageRoute(
              builder: (_) =>
                  ScheduleRecordPage(data: campus!, assignment: assignment),
            ),
          );
        case final Exam exam:
          await _openTimed(
            campus!,
            const TaskScheduleAdapter().examToScheduleItem(exam),
          );
        case final Event event:
          await _openTimed(
            campus!,
            const TaskScheduleAdapter().eventToScheduleItem(event),
          );
        case final FinanceRecord record:
          await navigator.pushNamed<void>(
            '/finance',
            arguments: record.occurredAt,
          );
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开该记录，已重新读取。')));
    } finally {
      _opening = false;
      if (mounted) _refresh();
    }
  }

  Future<void> _openTimed(CampusData data, ScheduleItem item) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ScheduleRecordPage(data: data, item: item),
        ),
      );

  int _compare(_Entry a, _Entry b) {
    final aPriority = a.record is Task
        ? (a.record as Task).priority.index
        : TaskPriority.normal.index;
    final bPriority = b.record is Task
        ? (b.record as Task).priority.index
        : TaskPriority.normal.index;
    if (!widget.search && aPriority != bPriority)
      return bPriority.compareTo(aPriority);
    final aDate = a.date;
    final bDate = b.date;
    if (aDate != bDate) {
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      final byDate = aDate.compareTo(bDate);
      if (byDate != 0) return byDate;
    }
    final byKind = a.kind.index.compareTo(b.kind.index);
    return byKind == 0 ? a.id.compareTo(b.id) : byKind;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.search ? '本地搜索' : '待办'),
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ModuleBody(
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.search)
            TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) {
                _debounce?.cancel();
                _refresh();
              },
              onChanged: (_) {
                _debounce?.cancel();
                setState(() {});
                _debounce = Timer(const Duration(milliseconds: 200), _refresh);
              },
              decoration: InputDecoration(
                labelText: '搜索课程、事项和账目',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: '清空',
                  onPressed: () {
                    _query.clear();
                    _debounce?.cancel();
                    _refresh();
                  },
                  icon: const Icon(Icons.clear),
                ),
              ),
            )
          else ...[
            Wrap(
              spacing: 8,
              children: [
                for (final period in TodoPeriod.values)
                  ChoiceChip(
                    label: Text(period.label),
                    selected: _period == period,
                    onSelected: (_) => setState(() => _period = period),
                  ),
              ],
            ),
            Text(switch (_period) {
              TodoPeriod.today => '今天有安排或到期的未完成事项',
              TodoPeriod.week => '从今天起七个日历日内的未完成事项',
              TodoPeriod.overdue => '截止时间已过的未完成事项',
              TodoPeriod.all => '全部未完成事项，含未安排事项',
            }),
          ],
          if (!widget.search || _query.text.trim().isNotEmpty)
            FutureBuilder<_Results>(
              future: _future,
              builder: (context, snapshot) {
                final data = snapshot.data;
                if (data == null)
                  return snapshot.hasError
                      ? TextButton(
                          onPressed: _refresh,
                          child: const Text('读取失败，点击重试'),
                        )
                      : const LinearProgressIndicator();
                final course = data.courses.containsKey(_course)
                    ? _course
                    : null;
                final now = widget.clock();
                final keyword = _query.text.trim().toLowerCase();
                final results = data.entries.where((row) {
                  if (_kind != null && row.kind != _kind) return false;
                  if (!widget.search) {
                    return (course == null || row.courseId == course) &&
                        matchesTodoPeriod(row.record, _period, now);
                  }
                  return '${row.title} ${row.extra} ${data.courses[row.courseId] ?? ''}'
                      .toLowerCase()
                      .contains(keyword);
                }).toList()..sort(_compare);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (snapshot.connectionState != ConnectionState.done)
                      const LinearProgressIndicator(),
                    DropdownButton<_Kind?>(
                      value: _kind,
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('全部类型'),
                        ),
                        for (final kind in _Kind.values)
                          if (widget.search || kind.index <= _Kind.exam.index)
                            DropdownMenuItem(
                              value: kind,
                              child: Text(kind.label),
                            ),
                      ],
                      onChanged: (kind) => setState(() => _kind = kind),
                    ),
                    if (!widget.search)
                      DropdownButton<String?>(
                        value: course,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('全部课程'),
                          ),
                          for (final entry in data.courses.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(
                                entry.value,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() => _course = value),
                      ),
                    if (data.failed.isNotEmpty)
                      TextButton(
                        onPressed: _refresh,
                        child: Text(
                          '未能读取${data.failed.map((kind) => kind.label).join('、')} · 重试',
                        ),
                      ),
                    if (results.isEmpty)
                      Text(data.failed.isEmpty ? '没有符合条件的记录' : '已读取的数据中没有匹配记录'),
                    for (final row in results.where(
                      (row) => widget.search || row.kind != _Kind.exam,
                    ))
                      _tile(row, data),
                    if (!widget.search &&
                        results.any((row) => row.kind == _Kind.exam)) ...[
                      const Text('即将到来的考试'),
                      for (final row in results.where(
                        (row) => row.kind == _Kind.exam,
                      ))
                        _tile(row, data),
                    ],
                  ],
                );
              },
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text('输入名称、备注或分类开始搜索。'),
            ),
        ],
      ),
    ),
  );

  Widget _tile(_Entry row, _Results data) {
    final record = row.record;
    return Card(
      child: ListTile(
        key: ValueKey((row.kind, row.id)),
        title: Text(row.title),
        subtitle: Text(
          [
            row.kind.label,
            if (record is Task) '${record.priority.label}优先级',
            if (record is Task && record.steps.isNotEmpty)
              '${record.steps.where((step) => step.done).length}/${record.steps.length} 子步骤',
            if (record is Assignment) record.status.label,
            if (row.courseId != null && row.kind != _Kind.course)
              data.courses[row.courseId] ?? '所属课程',
            if (row.date != null) formatLocalDateTime(row.date!),
            if (widget.search && row.extra.isNotEmpty) row.extra,
          ].join(' · '),
        ),
        onTap: () => _open(row, data),
      ),
    );
  }
}
