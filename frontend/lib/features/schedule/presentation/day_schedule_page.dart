import '../../../app/module_body.dart';
import 'package:flutter/material.dart';

import '../../../shared/models/schedule_item.dart';
import '../controllers/day_schedule_controller.dart';
import '../models/task.dart';
import '../services/day_schedule_service.dart';
import 'task_editor_dialog.dart';

/// 单日日程页面：由外部注入 [DayScheduleController]，页面不创建仓库。
class DaySchedulePage extends StatefulWidget {
  const DaySchedulePage({super.key, required this.controller, this.onRecover});

  final Future<void> Function()? onRecover;
  final DayScheduleController controller;

  @override
  State<DaySchedulePage> createState() => _DaySchedulePageState();
}

class _DaySchedulePageState extends State<DaySchedulePage> {
  bool _adding = false;
  final Set<String> _savingTasks = {};

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.controller.schedule != null ||
          widget.controller.isLoading) {
        return;
      }
      widget.controller.loadDay();
    });
  }

  @override
  void didUpdateWidget(DaySchedulePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    oldWidget.controller.removeListener(_onControllerChanged);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  ValueChanged<bool>? _toggleCallbackFor(ScheduleItem item) {
    if (!widget.controller.canEditTasks ||
        item.sourceType != ScheduleSourceType.task ||
        _savingTasks.contains(item.sourceId)) {
      return null;
    }
    return (value) => _setCompleted(item.sourceId, value);
  }

  Future<void> _setCompleted(String taskId, bool isCompleted) async {
    if (_savingTasks.contains(taskId)) return;
    setState(() => _savingTasks.add(taskId));
    try {
      await widget.controller.setTaskCompleted(taskId, isCompleted);
    } catch (_) {
      _showMessage('更新完成状态失败，请重试。');
    } finally {
      if (mounted) setState(() => _savingTasks.remove(taskId));
    }
  }

  Future<void> _showAddTaskDialog() => _showEditor();

  Future<void> _showEditor([String? id]) async {
    if (_adding || (id != null && _savingTasks.contains(id))) return;
    setState(() => _adding = true);
    try {
      final task = id == null ? null : await widget.controller.taskById(id);
      if (!mounted) return;
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => TaskEditorDialog(
          task: task,
          selectedDate: widget.controller.selectedDate,
          onSave: (value) => id == null
              ? widget.controller.addTask(
                  title: value.title,
                  estimatedMinutes: value.estimatedMinutes,
                  dueAt: value.dueAt,
                  scheduledRange: value.scheduledRange,
                )
              : widget.controller.updateTask(
                  id,
                  title: value.title,
                  estimatedMinutes: value.estimatedMinutes,
                  dueAt: value.dueAt,
                  scheduledRange: value.scheduledRange,
                ),
        ),
      );
    } catch (_) {
      _showMessage('任务读取失败，请重试。');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _removeTask(String id) async {
    if (_savingTasks.contains(id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除任务？'),
        content: const Text('删除后无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _savingTasks.add(id));
    try {
      await widget.controller.removeTask(id);
    } catch (_) {
      _showMessage('删除失败，任务已保留，请重试。');
    } finally {
      if (mounted) setState(() => _savingTasks.remove(id));
    }
  }

  ValueChanged<String>? _actionsFor(String id) =>
      !widget.controller.canEditTasks || _adding || _savingTasks.contains(id)
      ? null
      : (action) {
          if (action == 'edit') {
            _showEditor(id);
          }
          if (action == 'delete') {
            _removeTask(id);
          }
        };

  Widget _conflictNotice(DaySchedule day) {
    final pairs = widget.controller.conflicts;
    if (pairs.isEmpty) return const SizedBox.shrink();
    final items = {for (final item in day.items) item.id: item};
    return Card(
      key: const Key('day-schedule-conflicts'),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '时间冲突 · ${pairs.length} 处',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text('可以保留安排，也可编辑任务调整时间。'),
            for (final pair in pairs)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${items[pair.firstId]!.title} / ${items[pair.secondId]!.title}\n'
                  '${_formatDateTime(pair.overlapRange.start)} — ${_formatDateTime(pair.overlapRange.end)}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final schedule = widget.controller.schedule;
    return Scaffold(
      appBar: AppBar(
        title: const Text('日程手账'),
        actions: [
          if (widget.onRecover != null)
            IconButton(
              tooltip: '重新读取 / 从备份恢复',
              onPressed: widget.onRecover,
              icon: const Icon(Icons.restore),
            ),
        ],
      ),
      body: ModuleBody(
        child: SafeArea(
          child: Column(
            children: [
              if (widget.controller.demoData) const _DemoDataBanner(),
              _DateNavigator(controller: widget.controller),
              const Divider(height: 1),
              Expanded(child: _buildBody(schedule)),
            ],
          ),
        ),
      ),
      floatingActionButton: widget.controller.canEditTasks
          ? FloatingActionButton.extended(
              key: const Key('day-schedule-add-task'),
              onPressed: _adding ? null : _showAddTaskDialog,
              icon: const Icon(Icons.add),
              label: const Text('添加任务'),
            )
          : null,
    );
  }

  Widget _buildBody(DaySchedule? schedule) {
    if (widget.controller.isLoading && schedule == null) {
      return const Center(
        child: CircularProgressIndicator(key: Key('day-schedule-loading')),
      );
    }

    if (widget.controller.errorMessage != null && schedule == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text(
                widget.controller.errorMessage!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: widget.controller.retry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (schedule == null) {
      return const SizedBox.shrink();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        if (widget.onRecover != null)
          const ModuleNotice('任务自动保存在本机。可分别设置安排时间与截止时间。'),
        _conflictNotice(schedule),
        const _SectionTitle('当天日程'),
        if (schedule.items.isEmpty)
          const _EmptyMessage('今日暂无已排程事项')
        else
          ...schedule.items.map(
            (item) => _ScheduledItemTile(
              item: item,
              completed: schedule.isCompletedTask(item),
              crossDay: schedule.isCrossDay(item),
              onToggleComplete: _toggleCallbackFor(item),
              onAction: item.sourceType == ScheduleSourceType.task
                  ? _actionsFor(item.sourceId)
                  : null,
            ),
          ),
        const SizedBox(height: 20),
        const _SectionTitle('未安排任务'),
        if (schedule.unscheduledTasks.isEmpty)
          Column(
            children: [
              const _EmptyMessage('暂无未安排任务'),
              if (widget.controller.canEditTasks)
                TextButton.icon(
                  onPressed: _adding ? null : _showAddTaskDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('创建第一项任务'),
                ),
            ],
          )
        else
          ...schedule.unscheduledTasks.map(
            (task) => _UnscheduledTaskTile(
              task: task,
              onAction: _actionsFor(task.id),
              onToggleComplete:
                  widget.controller.canEditTasks &&
                      !_savingTasks.contains(task.id)
                  ? (value) => _setCompleted(task.id, value)
                  : null,
            ),
          ),
        if (schedule.completedTasks.isNotEmpty)
          ExpansionTile(
            key: const Key('completed-tasks'),
            title: Text('已完成任务（全部）· ${schedule.completedTasks.length}'),
            children: [
              for (final task in schedule.completedTasks)
                _UnscheduledTaskTile(
                  task: task,
                  onAction: _actionsFor(task.id),
                  onToggleComplete:
                      widget.controller.canEditTasks &&
                          !_savingTasks.contains(task.id)
                      ? (v) => _setCompleted(task.id, v)
                      : null,
                ),
            ],
          ),
      ],
    );
  }
}

/// 明确标注演示数据边界：仅存内存，退出后不保留。
class _DemoDataBanner extends StatelessWidget {
  const _DemoDataBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('day-schedule-demo-banner'),
      width: double.infinity,
      color: scheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        '演示数据：仅存内存，退出后不保留',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: scheme.onTertiaryContainer),
      ),
    );
  }
}

class _DateNavigator extends StatelessWidget {
  const _DateNavigator({required this.controller});

  final DayScheduleController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedDate;
    final monday = DateTime(
      selected.year,
      selected.month,
      selected.day - selected.weekday + 1,
    );
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '前一天',
                onPressed: controller.isLoading
                    ? null
                    : controller.goToPreviousDay,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  _formatDate(selected),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: '后一天',
                onPressed: controller.isLoading ? null : controller.goToNextDay,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Material(
                      color: selected.weekday == i + 1
                          ? scheme.primary
                          : scheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: controller.isLoading
                            ? null
                            : () => controller.loadDay(
                                DateTime(
                                  monday.year,
                                  monday.month,
                                  monday.day + i,
                                ),
                              ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          child: Column(
                            children: [
                              Text(
                                const ['一', '二', '三', '四', '五', '六', '日'][i],
                                style: TextStyle(
                                  fontSize: 11,
                                  color: selected.weekday == i + 1
                                      ? scheme.onPrimary
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${DateTime(monday.year, monday.month, monday.day + i).day}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: selected.weekday == i + 1
                                      ? scheme.onPrimary
                                      : scheme.onSurface,
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
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        child: Row(
          children: [
            Icon(
              Icons.event_available_outlined,
              size: 28,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduledItemTile extends StatelessWidget {
  const _ScheduledItemTile({
    required this.item,
    required this.completed,
    required this.crossDay,
    this.onToggleComplete,
    this.onAction,
  });

  final ValueChanged<String>? onAction;
  final ScheduleItem item;
  final bool completed;
  final bool crossDay;
  final ValueChanged<bool>? onToggleComplete;

  @override
  Widget build(BuildContext context) {
    final timeRange =
        '${_formatTime(item.range.start)} - ${_formatTime(item.range.end)}';
    final subtitle = crossDay ? '$timeRange · 跨日' : timeRange;
    final toggle = onToggleComplete;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(child: Text(_sourceLabel(item.sourceType))),
        title: Text(item.title),
        subtitle: Text(subtitle),
        trailing: _TaskActions(
          id: item.sourceId,
          completed: completed,
          onToggle: toggle,
          onAction: onAction,
        ),
      ),
    );
  }
}

class _UnscheduledTaskTile extends StatelessWidget {
  const _UnscheduledTaskTile({
    required this.task,
    this.onToggleComplete,
    this.onAction,
  });

  final ValueChanged<String>? onAction;

  final Task task;
  final ValueChanged<bool>? onToggleComplete;

  @override
  Widget build(BuildContext context) {
    final due = task.dueAt == null
        ? '无截止时间'
        : '截止 ${_formatDateTime(task.dueAt!)}';
    final toggle = onToggleComplete;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.pending_actions)),
        title: Text(task.title),
        subtitle: Text('${task.estimatedMinutes} 分钟 · $due'),
        trailing: _TaskActions(
          id: task.id,
          completed: task.isCompleted,
          onToggle: toggle,
          onAction: onAction,
        ),
      ),
    );
  }
}

class _TaskActions extends StatelessWidget {
  const _TaskActions({
    required this.id,
    required this.completed,
    this.onToggle,
    this.onAction,
  });
  final String id;
  final bool completed;
  final ValueChanged<bool>? onToggle;
  final ValueChanged<String>? onAction;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (onToggle != null)
        Checkbox(value: completed, onChanged: (v) => onToggle!(v ?? false))
      else if (completed)
        const Icon(Icons.check, semanticLabel: '已完成'),
      if (onAction != null)
        PopupMenuButton<String>(
          key: Key('task-actions-$id'),
          tooltip: '任务操作',
          onSelected: onAction,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('编辑 / 安排时间')),
            PopupMenuItem(value: 'delete', child: Text('删除任务')),
          ],
        ),
    ],
  );
}

String _sourceLabel(ScheduleSourceType sourceType) {
  switch (sourceType) {
    case ScheduleSourceType.course:
      return '课';
    case ScheduleSourceType.event:
      return '事';
    case ScheduleSourceType.task:
      return '任';
  }
}

String _formatDate(DateTime date) {
  return '${date.year}-${_two(date.month)}-${_two(date.day)}';
}

String _formatDateTime(DateTime dateTime) {
  return '${_formatDate(dateTime)} ${_formatTime(dateTime)}';
}

String _formatTime(DateTime dateTime) {
  return '${_two(dateTime.hour)}:${_two(dateTime.minute)}';
}

String _two(int value) => value.toString().padLeft(2, '0');
