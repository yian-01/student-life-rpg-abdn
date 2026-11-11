import 'package:flutter/material.dart';

import '../../../app/data/campus_data.dart';
import '../../../app/data/campus_store.dart';
import '../../../app/module_body.dart';
import '../../../shared/models/schedule_item.dart';
import '../../../shared/models/time_range.dart';
import '../../../shared/presentation/civil_datetime_field.dart';
import '../../../shared/presentation/record_editor_dialog.dart';
import '../models/assignment.dart';
import '../models/course.dart';
import '../models/course_adjustment.dart';
import '../models/exam.dart';
import '../models/semester.dart';
import 'academic_editors.dart';
import 'assignment_exam_page.dart';

class CourseDetailPage extends StatefulWidget {
  const CourseDetailPage({
    super.key,
    required this.data,
    required this.id,
    this.occurrence,
  });

  final CampusData data;
  final String id;
  final ScheduleItem? occurrence;

  @override
  State<CourseDetailPage> createState() => _CourseDetailPageState();
}

typedef _CourseDetail = ({
  Course course,
  List<Semester> semesters,
  List<Assignment> assignments,
  List<Exam> exams,
});

class _CourseDetailPageState extends State<CourseDetailPage> {
  late Future<_CourseDetail?> _detail = _load();
  bool _working = false;

  Future<_CourseDetail?> _load() async {
    final course = await widget.data.courses.getById(widget.id);
    if (course == null) return null;
    return (
      course: course,
      semesters: await widget.data.semesters.list(),
      assignments: sortAssignmentsForDisplay(
        await widget.data.assignments.listForCourse(course.id),
      ),
      exams: sortExamsForDisplay(
        await widget.data.exams.listForCourse(course.id),
      ),
    );
  }

  void _reload() => setState(() => _detail = _load());

  Future<void> _dialog(Widget child) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      if (await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => child,
              ) ==
              true &&
          mounted) {
        _reload();
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _storeAdjustment(String id, CourseAdjustment? adjustment) async {
    final latest = await widget.data.courses.getById(widget.id);
    if (latest == null) throw const FormatException('课程已经删除。');
    await widget.data.courses.update(
      Course.fromJson({
        ...latest.toJson(),
        'adjustments': [
          for (final row in latest.adjustments)
            if (row.occurrenceId != id) row.toJson(),
          if (adjustment != null) adjustment.toJson(),
        ],
      }, scoreScaleMax: CampusStore.scoreScaleMax),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('课程详情')),
    body: FutureBuilder<_CourseDetail?>(
      future: _detail,
      builder: (context, snapshot) {
        final detail = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done &&
            detail == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: _reload,
              child: const Text('读取课程失败，点击重试'),
            ),
          );
        }
        if (detail == null) return const Center(child: Text('课程已删除'));
        final course = detail.course;
        final occurrence = widget.occurrence;
        return ModuleBody(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                course.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                '${course.credits} 学分 · ${course.gradePoint == null ? '未评分' : '绩点 ${course.gradePoint}'}',
              ),
              Text('教师 · ${course.teacher ?? '未填写'}'),
              if (occurrence != null) ...[
                Text(
                  '本次 ${formatLocalDateTime(occurrence.range.start)} — ${formatLocalDateTime(occurrence.range.end)}',
                ),
                Text('教室 · ${occurrence.location ?? '未填写'}'),
                OutlinedButton(
                  onPressed: _working
                      ? null
                      : () => _dialog(
                          _AdjustmentEditor(
                            occurrence: occurrence,
                            current: course.adjustments
                                .where(
                                  (row) => row.occurrenceId == occurrence.id,
                                )
                                .firstOrNull,
                            onSave: (value) =>
                                _storeAdjustment(occurrence.id, value),
                          ),
                        ),
                  child: const Text('仅修改这一次'),
                ),
              ],
              TextButton(
                onPressed: _working
                    ? null
                    : () => _dialog(
                        CourseEditor(
                          data: widget.data,
                          semesters: detail.semesters,
                          course: course,
                        ),
                      ),
                child: const Text('修改每周安排及课程资料'),
              ),
              if (occurrence != null)
                TextButton(
                  onPressed: () async {
                    await Navigator.of(context).pushNamed<void>('/academic');
                    if (mounted) _reload();
                  },
                  child: const Text('进入学期与课程管理'),
                ),
              const Divider(),
              const Text('每周安排'),
              if (course.slots.isEmpty) const Text('暂无上课时间'),
              for (final slot in course.slots)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '周${slot.weekday} · ${_minute(slot.startMinute)}–${_minute(slot.endMinute)}',
                  ),
                  subtitle: Text(
                    '第 ${slot.weeks.join('、')} 周\n教室 · ${slot.location ?? '未填写'}',
                  ),
                ),
              if (course.adjustments.isNotEmpty) const Text('单次调课和停课'),
              for (final row in course.adjustments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(formatLocalDateTime(row.original.start)),
                  subtitle: Text(
                    row.replacement == null
                        ? '停课'
                        : '${formatLocalDateTime(row.replacement!.start)} — ${formatLocalDateTime(row.replacement!.end)}'
                              '${row.location == null ? '' : '\n教室 · ${row.location}'}',
                  ),
                  trailing: IconButton(
                    tooltip: '恢复原安排',
                    onPressed: _working
                        ? null
                        : () => _dialog(
                            RecordEditorDialog(
                              title: '恢复原安排',
                              onSave: () =>
                                  _storeAdjustment(row.occurrenceId, null),
                              child: const Text('保存后，这一次课将恢复原日期、时间和教室。'),
                            ),
                          ),
                    icon: const Icon(Icons.restore),
                  ),
                ),
              const Divider(),
              Wrap(
                spacing: 12,
                children: [
                  TextButton(
                    onPressed: _working
                        ? null
                        : () => _dialog(
                            AssignmentEditor(
                              repository: widget.data.assignments,
                              courseId: course.id,
                            ),
                          ),
                    child: const Text('新建作业'),
                  ),
                  TextButton(
                    onPressed: _working
                        ? null
                        : () => _dialog(
                            ExamEditor(
                              repository: widget.data.exams,
                              courseId: course.id,
                            ),
                          ),
                    child: const Text('新建考试'),
                  ),
                ],
              ),
              if (detail.assignments.isEmpty) const Text('暂无关联作业'),
              for (final assignment in detail.assignments)
                ListTile(
                  title: Text(assignment.title),
                  subtitle: Text(
                    '${assignment.status.label} · 截止 ${formatLocalDateTime(assignment.dueAt)}',
                  ),
                  onTap: _working
                      ? null
                      : () => _dialog(
                          AssignmentEditor(
                            repository: widget.data.assignments,
                            courseId: course.id,
                            assignment: assignment,
                          ),
                        ),
                ),
              if (detail.exams.isEmpty) const Text('暂无关联考试'),
              for (final exam in detail.exams)
                ListTile(
                  title: Text(exam.title),
                  subtitle: Text(
                    '${formatLocalDateTime(exam.range.start)} — ${formatLocalDateTime(exam.range.end)}\n地点 · ${exam.location ?? '未填写'}',
                  ),
                  onTap: _working
                      ? null
                      : () => _dialog(
                          ExamEditor(
                            repository: widget.data.exams,
                            courseId: course.id,
                            exam: exam,
                          ),
                        ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

String _minute(int value) =>
    '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';

class _AdjustmentEditor extends StatefulWidget {
  const _AdjustmentEditor({
    required this.occurrence,
    this.current,
    required this.onSave,
  });
  final ScheduleItem occurrence;
  final CourseAdjustment? current;
  final Future<void> Function(CourseAdjustment) onSave;

  @override
  State<_AdjustmentEditor> createState() => _AdjustmentEditorState();
}

class _AdjustmentEditorState extends State<_AdjustmentEditor> {
  late final TimeRange _original =
      widget.current?.original ?? widget.occurrence.range;
  late DateTime _start =
      (widget.current?.replacement ?? widget.occurrence.range).start;
  late DateTime _end =
      (widget.current?.replacement ?? widget.occurrence.range).end;
  late final _location = TextEditingController(
    text: widget.occurrence.location ?? '',
  );
  bool _cancelled = false;

  @override
  void dispose() {
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RecordEditorDialog(
    title: '仅修改这一次',
    onSave: () {
      if (!_cancelled && !_start.isBefore(_end)) {
        throw const FormatException('结束时间必须晚于开始时间。');
      }
      return widget.onSave(
        CourseAdjustment(
          occurrenceId: widget.occurrence.id,
          original: _original,
          replacement: _cancelled ? null : TimeRange(start: _start, end: _end),
          location: _cancelled || _location.text.trim().isEmpty
              ? null
              : _location.text.trim(),
        ),
      );
    },
    child: Column(
      children: [
        Text('原安排 · ${formatLocalDateTime(_original.start)}'),
        SwitchListTile(
          title: const Text('本次停课'),
          value: _cancelled,
          onChanged: (value) => setState(() => _cancelled = value),
        ),
        if (!_cancelled) ...[
          CivilDateTimeField(
            label: '开始',
            value: _start,
            enabled: true,
            onChanged: (value) => setState(() => _start = value),
          ),
          CivilDateTimeField(
            label: '结束',
            value: _end,
            enabled: true,
            onChanged: (value) => setState(() => _end = value),
          ),
          TextField(
            controller: _location,
            decoration: const InputDecoration(labelText: '教室'),
          ),
        ],
      ],
    ),
  );
}
