import 'package:flutter/material.dart';

import '../../../shared/models/schedule_item.dart';
import '../controllers/day_schedule_controller.dart';
import '../models/task.dart';
import '../services/day_schedule_service.dart';

/// 单日日程页面：由外部注入 [DayScheduleController]，页面不创建仓库。
class DaySchedulePage extends StatefulWidget {
  const DaySchedulePage({super.key, required this.controller});

  final DayScheduleController controller;

  @override
  State<DaySchedulePage> createState() => _DaySchedulePageState();
}

class _DaySchedulePageState extends State<DaySchedulePage> {
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
        item.sourceType != ScheduleSourceType.task) {
      return null;
    }
    return (value) => _setCompleted(item.sourceId, value);
  }

  Future<void> _setCompleted(String taskId, bool isCompleted) async {
    try {
      await widget.controller.setTaskCompleted(taskId, isCompleted);
    } catch (_) {
      _showMessage('更新完成状态失败，请重试。');
    }
  }

  Future<void> _showAddTaskDialog() async {
    final input = await showDialog<_NewTaskInput>(
      context: context,
      builder: (context) => const _AddTaskDialog(),
    );
    if (input == null) {
      return;
    }
    try {
      await widget.controller.addTask(
        title: input.title,
        estimatedMinutes: input.estimatedMinutes,
      );
      _showMessage('已添加任务：${input.title}');
    } catch (_) {
      _showMessage('任务保存失败，请重试。');
    }
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
      appBar: AppBar(title: const Text('Schedule')),
      body: SafeArea(
        child: Column(
          children: [
            _DateNavigator(controller: widget.controller),
            const Divider(height: 1),
            Expanded(child: _buildBody(schedule)),
          ],
        ),
      ),
      floatingActionButton: widget.controller.canEditTasks
          ? FloatingActionButton.extended(
              key: const Key('day-schedule-add-task'),
              onPressed: _showAddTaskDialog,
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
      padding: const EdgeInsets.all(16),
      children: [
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
            ),
          ),
        const SizedBox(height: 20),
        const _SectionTitle('未安排任务'),
        if (schedule.unscheduledTasks.isEmpty)
          const _EmptyMessage('暂无未安排任务')
        else
          ...schedule.unscheduledTasks.map(
            (task) => _UnscheduledTaskTile(
              task: task,
              onToggleComplete: widget.controller.canEditTasks
                  ? (value) => _setCompleted(task.id, value)
                  : null,
            ),
          ),
      ],
    );
  }
}

class _DateNavigator extends StatelessWidget {
  const _DateNavigator({required this.controller});

  final DayScheduleController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: '前一天',
            onPressed: controller.isLoading ? null : controller.goToPreviousDay,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              _formatDate(controller.selectedDate),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(child: Text(label, textAlign: TextAlign.center)),
    );
  }
}

class _ScheduledItemTile extends StatelessWidget {
  const _ScheduledItemTile({
    required this.item,
    required this.completed,
    required this.crossDay,
    this.onToggleComplete,
  });

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
        trailing: toggle != null
            ? Checkbox(
                value: completed,
                onChanged: (value) => toggle(value ?? false),
              )
            : (completed
                  ? const Chip(
                      avatar: Icon(Icons.check, size: 16),
                      label: Text('已完成'),
                    )
                  : null),
      ),
    );
  }
}

class _UnscheduledTaskTile extends StatelessWidget {
  const _UnscheduledTaskTile({required this.task, this.onToggleComplete});

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
        trailing: toggle == null
            ? null
            : Checkbox(
                value: false,
                onChanged: (value) => toggle(value ?? false),
              ),
      ),
    );
  }
}

class _NewTaskInput {
  const _NewTaskInput({required this.title, required this.estimatedMinutes});

  final String title;
  final int estimatedMinutes;
}

/// 最小新增任务表单：标题 + 预计分钟。
class _AddTaskDialog extends StatefulWidget {
  const _AddTaskDialog();

  @override
  State<_AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends State<_AddTaskDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _minutesController = TextEditingController(
    text: '30',
  );
  String? _errorText;

  @override
  void dispose() {
    _titleController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    final minutes = int.tryParse(_minutesController.text.trim());
    if (title.isEmpty) {
      setState(() => _errorText = '请输入任务标题');
      return;
    }
    if (minutes == null || minutes <= 0) {
      setState(() => _errorText = '预计分钟必须是正整数');
      return;
    }
    Navigator.of(
      context,
    ).pop(_NewTaskInput(title: title, estimatedMinutes: minutes));
  }

  @override
  Widget build(BuildContext context) {
    final errorText = _errorText;
    return AlertDialog(
      title: const Text('添加任务'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('add-task-title'),
            controller: _titleController,
            autofocus: true,
            decoration: const InputDecoration(labelText: '标题'),
          ),
          TextField(
            key: const Key('add-task-minutes'),
            controller: _minutesController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '预计分钟'),
          ),
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                errorText,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('添加')),
      ],
    );
  }
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
