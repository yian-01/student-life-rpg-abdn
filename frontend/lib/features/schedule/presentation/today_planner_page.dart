import 'package:flutter/material.dart';

import '../../../app/app_data.dart';
import '../../../app/module_body.dart';
import '../../../shared/models/schedule_item.dart';
import '../../academic/models/assignment.dart';
import '../../academic/presentation/assignment_exam_page.dart';
import '../models/task.dart';
import '../repositories/task_repository.dart';
import '../services/day_schedule_service.dart';
import '../services/today_planner.dart';
import 'week_timetable_grid.dart' show weekItemType;

class TodayPlannerPage extends StatefulWidget {
  const TodayPlannerPage({super.key, this.clock = DateTime.now});

  final DateTime Function() clock;

  @override
  State<TodayPlannerPage> createState() => _TodayPlannerPageState();
}

typedef _Plan = ({
  DaySchedule day,
  DayScheduleLoader loader,
  TaskRepository tasks,
});

class _TodayPlannerPageState extends State<TodayPlannerPage> {
  late Future<_Plan> _future = _load();
  bool _saving = false;

  Future<_Plan> _load() async {
    final campus = await AppData.campus();
    final tasks = await AppData.tasks();
    final loader = campus.schedule(tasks);
    return (
      day: await loader.loadDay(widget.clock()),
      loader: loader,
      tasks: tasks,
    );
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _suggest(_Plan plan, Task task) async {
    final slot = suggestTaskTime(plan.day, task, widget.clock());
    if (_saving || slot == null) return;
    setState(() => _saving = true);
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(task.title),
          content: Text(
            '安排在 ${formatLocalDateTime(slot.start)} 至 ${formatLocalDateTime(slot.end)}？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('加入日程'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      final saved = await applyTaskSuggestion(
        loader: plan.loader,
        tasks: plan.tasks,
        taskId: task.id,
        proposed: slot,
        now: widget.clock(),
      );
      if (mounted) {
        _message(saved ? '已加入今日日程。' : '日程或任务已变化，请查看最新建议。');
        _refresh();
      }
    } catch (_) {
      if (mounted) _message('安排任务失败，请刷新后重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('今日规划'),
      actions: [
        IconButton(
          tooltip: '刷新今日规划',
          onPressed: _saving ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<_Plan>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final plan = snapshot.data;
        if (plan == null) {
          return Center(
            child: TextButton(
              onPressed: _refresh,
              child: const Text('读取日程失败，重试'),
            ),
          );
        }
        final day = plan.day;
        final now = widget.clock();
        final timedErrors = day.errors.keys.any(
          (source) => source != ScheduleDataSource.assignments,
        );
        final upcoming = day.items
            .where(
              (item) =>
                  !day.isCompletedTask(item) && item.range.end.isAfter(now),
            )
            .toList();
        final tasks = [...day.unscheduledTasks]..sort(comparePlanningTasks);
        final deadlines = day.assignmentDeadlines.where(
          (row) => row.status != AssignmentStatus.submitted,
        );
        return ModuleBody(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${day.date.month} 月 ${day.date.day} 日',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (day.errors.isNotEmpty)
                Text(timedErrors ? '部分日程读取失败。刷新后可安排任务。' : '作业截止时间读取失败。'),
              const SizedBox(height: 12),
              Text('接下来的安排', style: Theme.of(context).textTheme.titleMedium),
              if (upcoming.isEmpty && !timedErrors) const Text('今天剩余时段暂无安排'),
              for (final item in upcoming)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.title),
                  subtitle: Text(
                    '${weekItemType(item.sourceType)} · ${_time(item.range.start)}–${_time(item.range.end)}'
                    '${item.location == null ? '' : ' · ${item.location}'}',
                  ),
                  trailing: item.sourceType == ScheduleSourceType.task
                      ? IconButton(
                          tooltip: '专注此任务',
                          icon: const Icon(Icons.timer_outlined),
                          onPressed: () async {
                            try {
                              final task = await plan.tasks.getById(
                                item.sourceId,
                              );
                              if (context.mounted && task != null) {
                                await Navigator.of(
                                  context,
                                ).pushNamed('/focus', arguments: task);
                              }
                            } catch (_) {
                              if (mounted) _message('读取任务失败，请刷新。');
                            }
                          },
                        )
                      : null,
                ),
              const Divider(),
              Text('今天截止的作业', style: Theme.of(context).textTheme.titleMedium),
              if (deadlines.isEmpty &&
                  !day.errors.containsKey(ScheduleDataSource.assignments))
                const Text('今天暂无未提交作业'),
              for (final row in deadlines)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(row.title),
                  subtitle: Text(
                    '${_time(row.dueAt)} 截止${row.dueAt.isBefore(now) ? ' · 已逾期' : ''}',
                  ),
                ),
              const Divider(),
              Text('给待办安排时间', style: Theme.of(context).textTheme.titleMedium),
              if (tasks.isEmpty) const Text('暂无未安排任务'),
              for (final task in tasks) _taskCard(plan, task, now),
            ],
          ),
        );
      },
    ),
  );

  Widget _taskCard(_Plan plan, Task task, DateTime now) {
    final slot = suggestTaskTime(plan.day, task, now);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(task.title, style: Theme.of(context).textTheme.titleMedium),
            Text('${task.priority.label}优先级 · 预计 ${task.estimatedMinutes} 分钟'),
            if (task.dueAt case final due?)
              Text(
                '截止 ${formatLocalDateTime(due)}${due.isBefore(now) ? ' · 已逾期' : ''}',
              ),
            Text(
              slot == null
                  ? '今天没有可确认的空档'
                  : '建议 ${_time(slot.start)}–${_time(slot.end)}',
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: slot == null || _saving
                      ? null
                      : () => _suggest(plan, task),
                  child: const Text('安排这段时间'),
                ),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pushNamed('/focus', arguments: task),
                  child: const Text('开始专注'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _time(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
