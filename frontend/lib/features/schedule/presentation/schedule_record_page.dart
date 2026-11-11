import 'package:flutter/material.dart';
import '../../../app/data/campus_data.dart';
import '../../../app/module_body.dart';
import '../../../shared/models/schedule_item.dart';
import '../../../shared/presentation/record_editor_dialog.dart';
import '../../../shared/repositories/entity_repository.dart';
import '../../academic/models/assignment.dart';
import '../../academic/presentation/course_detail_page.dart';
import '../../../shared/presentation/undo_removal.dart';
import '../../academic/models/exam.dart';
import '../../academic/presentation/assignment_exam_page.dart';
import '../controllers/schedule_record_controller.dart';
import '../models/event.dart';
import 'event_management_page.dart';

/// Read the original entity by its source ID on every opening. Course mutations
/// stay in academic management, including its semester/reference safeguards.
class ScheduleRecordPage extends StatelessWidget {
  ScheduleRecordPage({
    super.key,
    required this.data,
    this.item,
    this.assignment,
  }) {
    if ((item == null) == (assignment == null) ||
        item?.sourceType == ScheduleSourceType.task) {
      throw ArgumentError('Supply one non-task item or one assignment.');
    }
  }
  final CampusData data;
  final ScheduleItem? item;
  final Assignment? assignment;

  @override
  Widget build(BuildContext context) {
    final deadline = assignment;
    if (deadline != null) {
      return _RecordBody<Assignment>(
        id: deadline.id,
        repository: data.assignments,
        label: '作业详情',
        describe: (row) => [
          row.title,
          '截止 ${formatLocalDateTime(row.dueAt)}',
          row.status.label,
          if (row.description != null) row.description!,
        ],
        edit: (row) => AssignmentEditor(
          repository: data.assignments,
          courseId: row.courseId,
          assignment: row,
        ),
      );
    }
    final entry = item!;
    switch (entry.sourceType) {
      case ScheduleSourceType.exam:
        return _RecordBody<Exam>(
          id: entry.sourceId,
          repository: data.exams,
          label: '考试详情',
          describe: (row) => [
            row.title,
            '开始 ${formatLocalDateTime(row.range.start)}',
            '结束 ${formatLocalDateTime(row.range.end)}',
            if (row.location != null) '地点：${row.location}',
          ],
          edit: (row) => ExamEditor(
            repository: data.exams,
            courseId: row.courseId,
            exam: row,
          ),
        );
      case ScheduleSourceType.event:
        return _RecordBody<Event>(
          id: entry.sourceId,
          repository: data.events,
          label: '事件详情',
          describe: (row) => [
            row.title,
            '开始 ${formatLocalDateTime(row.range.start)}',
            '结束 ${formatLocalDateTime(row.range.end)}',
            if (row.description != null) row.description!,
          ],
          edit: (row) => EventEditor(data: data, event: row),
        );
      case ScheduleSourceType.course:
        return CourseDetailPage(
          data: data,
          id: entry.sourceId,
          occurrence: entry,
        );
      case ScheduleSourceType.task:
        throw StateError('Tasks use TaskEditorDialog.');
    }
  }
}

class _RecordBody<T> extends StatefulWidget {
  const _RecordBody({
    required this.id,
    required this.repository,
    required this.label,
    required this.describe,
    this.edit,
    this.manage,
  });
  final String id;
  final EntityRepository<T> repository;
  final String label;
  final List<String> Function(T) describe;
  final Widget Function(T)? edit;
  final Future<void> Function()? manage;
  @override
  State<_RecordBody<T>> createState() => _RecordBodyState<T>();
}

class _RecordBodyState<T> extends State<_RecordBody<T>> {
  late final _controller = ScheduleRecordController<T>(
    repository: widget.repository,
    id: widget.id,
  );
  bool _acting = false;
  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _edit(T record) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => widget.edit!(record),
      );
      if (saved == true && mounted) await _controller.load();
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _delete() async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      if (!await confirmRemoval(context, widget.label, undoable: true) ||
          !mounted)
        return;
      final entity = _controller.record;
      final repository = widget.repository;
      final removed = await _controller.remove();
      if (removed && mounted) {
        if (entity != null) {
          offerRemovalUndo(
            context,
            widget.label,
            () => repository.insert(entity),
          );
        }
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final record = _controller.record;
      return PopScope(
        canPop: !_controller.isDeleting,
        child: Scaffold(
          appBar: AppBar(title: Text(widget.label)),
          body: ModuleBody(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_controller.isLoading) const LinearProgressIndicator(),
                if (_controller.error != null) ...[
                  Text(
                    _controller.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(
                    onPressed: _acting || _controller.isLoading
                        ? null
                        : _controller.load,
                    child: const Text('重试详情'),
                  ),
                ],
                if (record != null) ...[
                  for (final text in widget.describe(record))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SelectableText(text),
                    ),
                  if (widget.edit != null)
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          key: const Key('schedule-record-edit'),
                          onPressed: _acting || _controller.error != null
                              ? null
                              : () => _edit(record),
                          child: const Text('编辑'),
                        ),
                        TextButton(
                          key: const Key('schedule-record-delete'),
                          onPressed: _acting || _controller.error != null
                              ? null
                              : _delete,
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  if (widget.manage != null)
                    FilledButton(
                      onPressed: _acting
                          ? null
                          : () async {
                              setState(() => _acting = true);
                              try {
                                await widget.manage!();
                                if (mounted) await _controller.load();
                              } finally {
                                if (mounted) setState(() => _acting = false);
                              }
                            },
                      child: const Text('进入学期与课程管理'),
                    ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
