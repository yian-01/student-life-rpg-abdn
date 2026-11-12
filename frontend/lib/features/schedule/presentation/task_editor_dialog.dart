import 'package:flutter/material.dart';

import '../../../shared/models/time_range.dart';
import '../../../shared/presentation/civil_datetime_field.dart';
import '../models/task.dart';

class TaskEditorValue {
  const TaskEditorValue({
    required this.title,
    required this.estimatedMinutes,
    this.dueAt,
    this.scheduledRange,
    this.note,
    this.priority = TaskPriority.normal,
    this.steps = const [],
  });
  final String title;
  final int estimatedMinutes;
  final DateTime? dueAt;
  final TimeRange? scheduledRange;
  final String? note;
  final TaskPriority priority;
  final List<TaskStep> steps;
}

/// Keeps the user's draft open on write failure; closes only after persistence.
class TaskEditorDialog extends StatefulWidget {
  const TaskEditorDialog({
    super.key,
    required this.selectedDate,
    required this.onSave,
    this.task,
    this.copying = false,
    this.copyAnchor,
  });
  final DateTime selectedDate;
  final Task? task;
  final bool copying;
  final DateTime? copyAnchor;
  final Future<void> Function(TaskEditorValue value) onSave;

  @override
  State<TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends State<TaskEditorDialog> {
  late final _title = TextEditingController(text: widget.task?.title ?? '');
  late final _note = TextEditingController(text: widget.task?.note ?? '');
  final _step = TextEditingController();
  late TaskPriority _priority = widget.task?.priority ?? TaskPriority.normal;
  late final List<TaskStep> _steps = [...?widget.task?.steps];
  int _stepSequence = 0;
  late final _minutes = TextEditingController(
    text: '${widget.task?.estimatedMinutes ?? 30}',
  );
  late bool _scheduled = widget.task?.scheduledRange != null;
  late bool _hasDue = widget.task?.dueAt != null;
  late DateTime _start =
      widget.task?.scheduledRange?.start ??
      DateTime(
        widget.selectedDate.year,
        widget.selectedDate.month,
        widget.selectedDate.day,
        9,
      );
  late DateTime _end =
      widget.task?.scheduledRange?.end ??
      DateTime(
        widget.selectedDate.year,
        widget.selectedDate.month,
        widget.selectedDate.day,
        10,
      );
  late DateTime _due =
      widget.task?.dueAt ??
      DateTime(
        widget.selectedDate.year,
        widget.selectedDate.month,
        widget.selectedDate.day,
        18,
      );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _minutes.dispose();
    _note.dispose();
    _step.dispose();
    super.dispose();
  }

  void _addStep() {
    final title = _step.text.trim();
    if (_saving || title.isEmpty) return;
    setState(() {
      _steps.add(
        TaskStep(
          id: 'step-${DateTime.now().microsecondsSinceEpoch}-${_stepSequence++}',
          title: title,
        ),
      );
      _step.clear();
    });
  }

  Future<void> _renameStep(int index) async {
    final old = _steps[index];
    var title = old.title;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑子步骤'),
        content: TextFormField(
          initialValue: title,
          onChanged: (value) => title = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (title.trim().isNotEmpty) Navigator.pop(context, title.trim());
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (mounted && result != null) {
      setState(
        () =>
            _steps[index] = TaskStep(id: old.id, title: result, done: old.done),
      );
    }
  }

  void _shiftDeadline() {
    final anchor = widget.copyAnchor!;
    final target = widget.selectedDate;
    final original = widget.task!.dueAt!;
    final delta = DateTime.utc(
      target.year,
      target.month,
      target.day,
    ).difference(DateTime.utc(anchor.year, anchor.month, anchor.day)).inDays;
    _due = DateTime(
      original.year,
      original.month,
      original.day + delta,
      original.hour,
      original.minute,
      original.second,
      original.millisecond,
      original.microsecond,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _title.text.trim();
    final minutes = int.tryParse(_minutes.text.trim());
    String? error;
    if (title.isEmpty) {
      error = '请输入任务标题';
    } else if (minutes == null || minutes <= 0) {
      error = '预计分钟必须是正整数';
    } else if (_scheduled && !_start.isBefore(_end)) {
      error = '结束时间必须晚于开始时间';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    if (_step.text.trim().isNotEmpty) _addStep();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        TaskEditorValue(
          title: title,
          estimatedMinutes: minutes!,
          dueAt: _hasDue ? _due : null,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          priority: _priority,
          steps: List.unmodifiable(_steps),
          scheduledRange: _scheduled
              ? TimeRange(start: _start, end: _end)
              : null,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _error = '任务保存失败，请重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      scrollable: true,
      title: Text(
        widget.copying
            ? '复制任务'
            : widget.task == null
            ? '添加任务'
            : '编辑任务',
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('add-task-title'),
              controller: _title,
              enabled: !_saving,
              autofocus: true,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('add-task-minutes'),
              controller: _minutes,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '预计分钟'),
            ),
            SwitchListTile(
              key: const Key('task-scheduled-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('安排时间'),
              value: _scheduled,
              onChanged: _saving ? null : (v) => setState(() => _scheduled = v),
            ),
            if (_scheduled) ...[
              CivilDateTimeField(
                label: '开始',
                value: _start,
                enabled: !_saving,
                onChanged: (v) => setState(() => _start = v),
              ),
              CivilDateTimeField(
                label: '结束',
                value: _end,
                enabled: !_saving,
                onChanged: (v) => setState(() => _end = v),
              ),
            ],
            SwitchListTile(
              key: const Key('task-due-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('截止时间'),
              value: _hasDue,
              onChanged: _saving ? null : (v) => setState(() => _hasDue = v),
            ),
            if (_hasDue)
              CivilDateTimeField(
                label: '截止',
                value: _due,
                enabled: !_saving,
                onChanged: (v) => setState(() => _due = v),
              ),
            if (widget.copying && _hasDue && widget.task?.dueAt != null)
              Wrap(
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _due = widget.task!.dueAt!),
                    child: const Text('保留原截止'),
                  ),
                  if (widget.copyAnchor != null)
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => setState(_shiftDeadline),
                      child: const Text('随目标日期平移'),
                    ),
                ],
              ),
            TextField(
              controller: _note,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: '备注（可选）'),
            ),
            DropdownButtonFormField<TaskPriority>(
              initialValue: _priority,
              decoration: const InputDecoration(labelText: '优先级'),
              items: [
                for (final priority in TaskPriority.values)
                  DropdownMenuItem(
                    value: priority,
                    child: Text(priority.label),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => _priority = value);
                    },
            ),
            if (_steps.isNotEmpty)
              Text(
                '子步骤 ${_steps.where((step) => step.done).length}/${_steps.length}（任务完成状态单独设置）',
              ),
            for (final (index, step) in _steps.indexed)
              ListTile(
                key: ValueKey(step.id),
                contentPadding: EdgeInsets.zero,
                leading: Checkbox(
                  value: step.done,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _steps[index] = TaskStep(
                            id: step.id,
                            title: step.title,
                            done: value ?? false,
                          );
                        }),
                ),
                title: Text(step.title),
                onTap: _saving ? null : () => _renameStep(index),
                trailing: IconButton(
                  tooltip: '删除子步骤',
                  onPressed: _saving
                      ? null
                      : () => setState(() => _steps.removeAt(index)),
                  icon: const Icon(Icons.close),
                ),
              ),
            TextField(
              controller: _step,
              enabled: !_saving,
              onSubmitted: (_) => _addStep(),
              decoration: InputDecoration(
                labelText: '新子步骤',
                suffixIcon: IconButton(
                  tooltip: '添加子步骤',
                  onPressed: _saving ? null : _addStep,
                  icon: const Icon(Icons.add),
                ),
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(
            _saving
                ? '保存中…'
                : widget.task == null
                ? '添加'
                : '保存',
          ),
        ),
      ],
    ),
  );
}

/// Shared task editing entry point for list-based views.
Future<bool?> editExistingTask(
  BuildContext context,
  Task task,
  Future<void> Function(Task) save,
) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => TaskEditorDialog(
    task: task,
    selectedDate: task.scheduledRange?.start ?? task.dueAt ?? DateTime.now(),
    onSave: (value) => save(
      task.copyWith(
        title: value.title,
        estimatedMinutes: value.estimatedMinutes,
        scheduledRange: value.scheduledRange,
        dueAt: value.dueAt,
        note: value.note,
        priority: value.priority,
        steps: value.steps,
      ),
    ),
  ),
);
