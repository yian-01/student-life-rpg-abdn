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
  });
  final String title;
  final int estimatedMinutes;
  final DateTime? dueAt;
  final TimeRange? scheduledRange;
}

/// Keeps the user's draft open on write failure; closes only after persistence.
class TaskEditorDialog extends StatefulWidget {
  const TaskEditorDialog({
    super.key,
    required this.selectedDate,
    required this.onSave,
    this.task,
  });
  final DateTime selectedDate;
  final Task? task;
  final Future<void> Function(TaskEditorValue value) onSave;

  @override
  State<TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends State<TaskEditorDialog> {
  late final _title = TextEditingController(text: widget.task?.title ?? '');
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
    super.dispose();
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
      title: Text(widget.task == null ? '添加任务' : '编辑任务'),
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
