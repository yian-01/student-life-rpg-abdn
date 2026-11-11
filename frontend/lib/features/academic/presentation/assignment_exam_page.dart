import 'package:flutter/material.dart';
import '../../../app/data/campus_data.dart';
import '../../../shared/models/time_range.dart';
import '../../../shared/presentation/civil_datetime_field.dart';
import '../../../shared/presentation/record_editor_dialog.dart';
import '../../../shared/presentation/undo_removal.dart';
import '../models/assignment.dart';
import '../models/course.dart';
import '../models/exam.dart';
import '../repositories/assignment_repository.dart';
import '../repositories/exam_repository.dart';

/// 单门课程的作业与考试管理。
///
/// 本页与组合根共享 [CampusData] 注入的持久化仓库。
class AssignmentExamPage extends StatefulWidget {
  const AssignmentExamPage({
    super.key,
    required this.data,
    required this.course,
  });
  final CampusData data;
  final Course course;
  @override
  State<AssignmentExamPage> createState() => _AssignmentExamPageState();
}

class _AssignmentExamPageState extends State<AssignmentExamPage> {
  List<Assignment> _assignments = const [];
  List<Exam> _exams = const [];
  bool _busy = false;
  AssignmentStatus? _statusFilter;
  String? _error;

  AssignmentRepository get _assignmentRepo => widget.data.assignments;
  ExamRepository get _examRepo => widget.data.exams;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // 排序在界面层完成：不依赖仓库返回顺序（共享持久化实现返回插入顺序），
      // 也便于日后替换仓库实现时展示一致。
      final assignments = sortAssignmentsForDisplay(
        await _assignmentRepo.listForCourse(widget.course.id),
      );
      final exams = sortExamsForDisplay(
        await _examRepo.listForCourse(widget.course.id),
      );
      if (!mounted) return;
      setState(() {
        _assignments = assignments;
        _exams = exams;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '读取失败，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editAssignment({Assignment? assignment}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AssignmentEditor(
        repository: _assignmentRepo,
        courseId: widget.course.id,
        assignment: assignment,
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _editExam({Exam? exam}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExamEditor(
        repository: _examRepo,
        courseId: widget.course.id,
        exam: exam,
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _removeAssignment(Assignment assignment) async {
    if (!await confirmRemoval(context, assignment.title, undoable: true) ||
        !mounted)
      return;
    try {
      final repository = _assignmentRepo;
      if (!await repository.remove(assignment.id))
        throw StateError('Missing assignment');
      if (!mounted) return;
      offerRemovalUndo(context, assignment.title, () async {
        await repository.insert(assignment);
        if (mounted) await _load();
      });
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = '删除失败，请检查存储后重试。');
    }
  }

  Future<void> _removeExam(Exam exam) async {
    if (!await confirmRemoval(context, exam.title, undoable: true) || !mounted)
      return;
    try {
      final repository = _examRepo;
      if (!await repository.remove(exam.id)) throw StateError('Missing exam');
      if (!mounted) return;
      offerRemovalUndo(context, exam.title, () async {
        await repository.insert(exam);
        if (mounted) await _load();
      });
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = '删除失败，请检查存储后重试。');
    }
  }

  /// 只读详情：列表点一下就能看到全部字段，不需要进编辑态。
  Future<void> _openAssignmentDetail(Assignment row) => showDialog<void>(
    context: context,
    builder: (_) => _RecordDetail(
      key: Key('assignment-detail-${row.id}'),
      title: row.title,
      rows: [
        ('所属课程', widget.course.name),
        ('截止时间', formatLocalDateTime(row.dueAt)),
        ('提交状态', row.status.label),
        (
          '描述',
          row.description?.trim().isNotEmpty == true
              ? row.description!
              : '（未填）',
        ),
      ],
    ),
  );

  Future<void> _openExamDetail(Exam row) {
    final cross = isCrossDay(row.range.start, row.range.end);
    return showDialog<void>(
      context: context,
      builder: (_) => _RecordDetail(
        key: Key('exam-detail-${row.id}'),
        title: row.title,
        rows: [
          ('所属课程', widget.course.name),
          ('开始', formatLocalDateTime(row.range.start)),
          ('结束', formatLocalDateTime(row.range.end)),
          ('时长', formatDuration(row.range.end.difference(row.range.start))),
          ('跨日', cross ? '是（跨过午夜）' : '否'),
          (
            '地点',
            row.location?.trim().isNotEmpty == true ? row.location! : '（未填）',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(title: Text('作业与考试 · ${widget.course.name}')),
      body: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: '作业'),
              Tab(text: '考试'),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    children: [
                      _AssignmentList(
                        rows: _assignments
                            .where(
                              (row) =>
                                  _statusFilter == null ||
                                  row.status == _statusFilter,
                            )
                            .toList(),
                        filter: _statusFilter,
                        onFilter: (status) =>
                            setState(() => _statusFilter = status),
                        onCreate: () => _editAssignment(),
                        onEdit: (row) => _editAssignment(assignment: row),
                        onDelete: _removeAssignment,
                        onOpen: _openAssignmentDetail,
                      ),
                      _ExamList(
                        rows: _exams,
                        onCreate: () => _editExam(),
                        onEdit: (row) => _editExam(exam: row),
                        onDelete: _removeExam,
                        onOpen: _openExamDetail,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );
}

class _AssignmentList extends StatelessWidget {
  const _AssignmentList({
    required this.rows,
    required this.filter,
    required this.onFilter,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
    required this.onOpen,
  });
  final List<Assignment> rows;
  final AssignmentStatus? filter;
  final ValueChanged<AssignmentStatus?> onFilter;
  final VoidCallback onCreate;
  final ValueChanged<Assignment> onEdit;
  final ValueChanged<Assignment> onDelete;
  final ValueChanged<Assignment> onOpen;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      FilledButton.icon(
        key: const Key('new-assignment'),
        onPressed: onCreate,
        icon: const Icon(Icons.add),
        label: const Text('新建作业'),
      ),
      const SizedBox(height: 12),
      DropdownButton<AssignmentStatus?>(
        value: filter,
        isExpanded: true,
        items: [
          const DropdownMenuItem(value: null, child: Text('全部状态')),
          for (final status in AssignmentStatus.values)
            DropdownMenuItem(value: status, child: Text(status.label)),
        ],
        onChanged: onFilter,
      ),
      if (rows.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text('暂无作业。作业以截止事项呈现，不生成额外持续时间。'),
        ),
      for (final row in rows)
        Card(
          child: ListTile(
            key: Key('assignment-tile-${row.id}'),
            onTap: () => onOpen(row),
            title: Text(
              row.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${row.status.label} · 截止 ${formatLocalDateTime(row.dueAt)}'
              '${row.description == null || row.description!.isEmpty ? '' : '\n${row.description}'}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: row.description != null && row.description!.isNotEmpty,
            trailing: PopupMenuButton<String>(
              key: Key('assignment-actions-${row.id}'),
              onSelected: (value) {
                if (value == 'edit') onEdit(row);
                if (value == 'delete') onDelete(row);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ),
        ),
    ],
  );
}

class _ExamList extends StatelessWidget {
  const _ExamList({
    required this.rows,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
    required this.onOpen,
  });
  final List<Exam> rows;
  final VoidCallback onCreate;
  final ValueChanged<Exam> onEdit;
  final ValueChanged<Exam> onDelete;
  final ValueChanged<Exam> onOpen;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      FilledButton.icon(
        key: const Key('new-exam'),
        onPressed: onCreate,
        icon: const Icon(Icons.add),
        label: const Text('新建考试'),
      ),
      const SizedBox(height: 12),
      if (rows.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text('暂无考试。考试按起止时间进入日程。'),
        ),
      for (final row in rows)
        Card(
          child: ListTile(
            key: Key('exam-tile-${row.id}'),
            onTap: () => onOpen(row),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    row.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isCrossDay(row.range.start, row.range.end))
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Chip(
                      label: Text('跨日', style: TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
            subtitle: Text(
              '${formatLocalDateTime(row.range.start)} – '
              '${formatLocalDateTime(row.range.end)}'
              '${row.location == null || row.location!.isEmpty ? '' : '\n地点：${row.location}'}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: row.location != null && row.location!.isNotEmpty,
            trailing: PopupMenuButton<String>(
              key: Key('exam-actions-${row.id}'),
              onSelected: (value) {
                if (value == 'edit') onEdit(row);
                if (value == 'delete') onDelete(row);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ),
        ),
    ],
  );
}

/// 作业编辑器：标题、截止时间、描述。
class AssignmentEditor extends StatefulWidget {
  const AssignmentEditor({
    super.key,
    required this.repository,
    required this.courseId,
    this.assignment,
  });
  final AssignmentRepository repository;
  final String courseId;
  final Assignment? assignment;
  @override
  State<AssignmentEditor> createState() => _AssignmentEditorState();
}

class _AssignmentEditorState extends State<AssignmentEditor> {
  late final _title = TextEditingController(
    text: widget.assignment?.title ?? '',
  );
  late final _description = TextEditingController(
    text: widget.assignment?.description ?? '',
  );
  late AssignmentStatus _status =
      widget.assignment?.status ?? AssignmentStatus.notStarted;
  late DateTime _dueAt =
      widget.assignment?.dueAt ?? DateTime.now().add(const Duration(days: 1));
  late final _id =
      widget.assignment?.id ??
      'assignment-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) throw const FormatException('作业标题不能为空');
    if (_dueAt.isUtc) throw const FormatException('截止时间必须是本地时间');
    final description = _description.text.trim();
    final value = Assignment(
      id: _id,
      courseId: widget.courseId,
      title: title,
      dueAt: _dueAt,
      status: _status,
      description: description.isEmpty ? null : description,
    );
    if (widget.assignment == null) {
      await widget.repository.insert(value);
    } else {
      await widget.repository.update(value);
    }
  }

  @override
  Widget build(BuildContext context) => RecordEditorDialog(
    title: widget.assignment == null ? '新建作业' : '编辑作业',
    onSave: _save,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('assignment-title'),
          controller: _title,
          decoration: const InputDecoration(labelText: '作业标题'),
        ),
        const SizedBox(height: 8),
        CivilDateTimeField(
          key: const Key('assignment-due'),
          label: '截止时间',
          value: _dueAt,
          enabled: true,
          onChanged: (value) => setState(() => _dueAt = value),
        ),
        DropdownButtonFormField<AssignmentStatus>(
          initialValue: _status,
          decoration: const InputDecoration(labelText: '提交状态'),
          items: [
            for (final status in AssignmentStatus.values)
              DropdownMenuItem(value: status, child: Text(status.label)),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _status = value);
          },
        ),
        TextField(
          key: const Key('assignment-description'),
          controller: _description,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '描述（可留空）',
            alignLabelWithHint: true,
          ),
        ),
      ],
    ),
  );
}

/// 考试编辑器：标题、起止时间、地点。
class ExamEditor extends StatefulWidget {
  const ExamEditor({
    super.key,
    required this.repository,
    required this.courseId,
    this.exam,
  });
  final ExamRepository repository;
  final String courseId;
  final Exam? exam;
  @override
  State<ExamEditor> createState() => _ExamEditorState();
}

class _ExamEditorState extends State<ExamEditor> {
  late final _title = TextEditingController(text: widget.exam?.title ?? '');
  late final _location = TextEditingController(
    text: widget.exam?.location ?? '',
  );
  late DateTime _start =
      widget.exam?.range.start ?? DateTime.now().add(const Duration(days: 7));
  late DateTime _end =
      widget.exam?.range.end ??
      DateTime.now().add(const Duration(days: 7, hours: 2));
  late final _id =
      widget.exam?.id ?? 'exam-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) throw const FormatException('考试名称不能为空');
    if (_start.isUtc || _end.isUtc) {
      throw const FormatException('考试时间必须是本地时间');
    }
    if (!_start.isBefore(_end)) {
      throw const FormatException('考试结束时间必须晚于开始时间');
    }
    final location = _location.text.trim();
    final value = Exam(
      id: _id,
      courseId: widget.courseId,
      title: title,
      range: TimeRange(start: _start, end: _end),
      location: location.isEmpty ? null : location,
    );
    if (widget.exam == null) {
      await widget.repository.insert(value);
    } else {
      await widget.repository.update(value);
    }
  }

  @override
  Widget build(BuildContext context) => RecordEditorDialog(
    title: widget.exam == null ? '新建考试' : '编辑考试',
    onSave: _save,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('exam-title'),
          controller: _title,
          decoration: const InputDecoration(labelText: '考试名称'),
        ),
        const SizedBox(height: 8),
        CivilDateTimeField(
          key: const Key('exam-start'),
          label: '开始时间',
          value: _start,
          enabled: true,
          onChanged: (value) => setState(() => _start = value),
        ),
        CivilDateTimeField(
          key: const Key('exam-end'),
          label: '结束时间',
          value: _end,
          enabled: true,
          onChanged: (value) => setState(() => _end = value),
        ),
        TextField(
          key: const Key('exam-location'),
          controller: _location,
          decoration: const InputDecoration(labelText: '地点（可留空）'),
        ),
      ],
    ),
  );
}

/// `YYYY-MM-DD HH:mm`，列表展示用。
String formatLocalDateTime(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.year}-$month-$day $hour:$minute';
}

/// 作业列表展示顺序：按截止时间升序。
///
/// 刻意放在界面层：共享持久化仓库返回插入顺序，展示顺序不应依赖它。
/// 入参可能是不可修改列表，因此先复制再排序。
List<Assignment> sortAssignmentsForDisplay(Iterable<Assignment> rows) =>
    <Assignment>[...rows]..sort((a, b) => a.dueAt.compareTo(b.dueAt));

/// 考试列表展示顺序：按开始时间升序。
List<Exam> sortExamsForDisplay(Iterable<Exam> rows) =>
    <Exam>[...rows]..sort((a, b) => a.range.start.compareTo(b.range.start));

/// 是否跨过午夜（例如 23:30–次日 00:30）。
///
/// 只比较本地日期；跨日的考试在列表和详情里都要显式标出，
/// 否则「结束 00:30」会被误读成同一天凌晨。
bool isCrossDay(DateTime start, DateTime end) =>
    start.year != end.year || start.month != end.month || start.day != end.day;

/// 人类可读的时长，如「2 小时 30 分钟」。
String formatDuration(Duration duration) {
  if (duration.isNegative) return '（时间倒置）';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '$minutes 分钟';
  if (minutes == 0) return '$hours 小时';
  return '$hours 小时 $minutes 分钟';
}

/// 只读详情弹窗：列表点一下即可看到全部字段。
class _RecordDetail extends StatelessWidget {
  const _RecordDetail({super.key, required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(title, maxLines: 3, overflow: TextOverflow.ellipsis),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      row.$1,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(child: Text(row.$2)),
                ],
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}
