import 'package:flutter/material.dart';
import '../../timetable_capture/scnu_web_session.dart';
import '../services/scnu_timetable_source.dart';
import '../../../app/campus_recovery.dart';
import '../../../app/data/campus_data.dart';
import '../../../shared/presentation/record_editor_dialog.dart';
import '../models/course.dart';
import '../models/semester.dart';
import '../services/course_reference_guard.dart';
import 'academic_editors.dart';
import 'course_detail_page.dart';
import 'assignment_exam_page.dart';
import 'timetable_import_page.dart';

class AcademicManagementPage extends StatefulWidget {
  const AcademicManagementPage({super.key, required this.data});
  final CampusData data;
  @override
  State<AcademicManagementPage> createState() => _AcademicManagementPageState();
}

class _AcademicManagementPageState extends State<AcademicManagementPage> {
  List<Semester> _semesters = [];
  List<Course> _courses = [];
  bool _busy = false;
  String? _error;
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
      await widget.data.academic.load();
      final semesters = widget.data.academic.semesters;
      final courses = widget.data.academic.courses;
      if (mounted) {
        setState(() {
          _semesters = semesters;
          _courses = courses;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '读取失败，请重试或恢复备份。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit({
    Semester? semester,
    Course? course,
    bool isCourse = false,
  }) async {
    if (isCourse && _semesters.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先新建学期')));
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => isCourse
          ? CourseEditor(
              data: widget.data,
              semesters: _semesters,
              course: course,
            )
          : SemesterEditor(
              data: widget.data,
              semester: semester,
              courses: _courses,
            ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _remove(String id, String name, bool isCourse) async {
    if (!await confirmRemoval(context, name) || !mounted) return;
    setState(() => _busy = true);
    try {
      if (isCourse) {
        // 有作业或考试引用时禁止删除，且不改动任何数据。
        await ensureCourseDeletable(
          courseId: id,
          courseName: name,
          assignments: widget.data.assignments,
          exams: widget.data.exams,
        );
        await widget.data.academic.removeCourse(id);
      } else {
        await widget.data.academic.removeSemester(id);
      }
      if (mounted) await _load();
    } on StateError catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          // 课程：用引用守卫给出的中文原因；
          // 学期：沿用既有提示，不暴露仓库层的英文错误文本。
          _error = isCourse ? error.message : '删除失败：学期可能仍有课程引用，请先处理课程并检查存储。';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = isCourse ? '删除失败，请检查存储后重试。' : '删除失败：学期可能仍有课程引用，请先处理课程并检查存储。';
        });
      }
    }
  }

  Future<void> _openRecords(Course course) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssignmentExamPage(data: widget.data, course: course),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openTimetableImport() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => TimetableImportPage(
          data: widget.data,
          semesters: _semesters,
          htmlLoader: ScnuTimetableHtmlLoader(ScnuWebSession(context)),
          htmlParser: const ScnuTimetableHtmlParser(),
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('学期与课程'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '重新读取 / 从备份恢复',
            onPressed: _busy
                ? null
                : () async {
                    if (await recoverCampusData(context, widget.data) &&
                        mounted) {
                      await _load();
                    }
                  },
            icon: const Icon(Icons.restore),
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(text: '学期'),
            Tab(text: '课程'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                key: const Key('academic-error'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 18,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    FilledButton.icon(
                      key: const Key('new-semester'),
                      onPressed: _busy ? null : () => _edit(),
                      icon: const Icon(Icons.add),
                      label: const Text('新建学期'),
                    ),
                    if (_semesters.isEmpty && !_busy)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('先添加学期，再录入课程。'),
                      ),
                    for (final semester in _semesters)
                      Card(
                        child: ListTile(
                          title: Text(semester.name),
                          subtitle: Text(
                            '${_date(semester.startDate)} — ${_date(semester.endDate)}\n第 1 周周一：${_date(semester.week1Monday)}',
                          ),
                          trailing: PopupMenuButton<String>(
                            key: Key('semester-actions-${semester.id}'),
                            enabled: !_busy,
                            onSelected: (v) {
                              if (v == 'edit') {
                                _edit(semester: semester);
                              } else {
                                _remove(semester.id, semester.name, false);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('编辑')),
                              PopupMenuItem(value: 'delete', child: Text('删除')),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    FilledButton.icon(
                      key: const Key('new-course'),
                      onPressed: _busy ? null : () => _edit(isCourse: true),
                      icon: const Icon(Icons.add),
                      label: const Text('新建课程'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('import-timetable'),
                      onPressed: _busy || _semesters.isEmpty
                          ? null
                          : _openTimetableImport,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('从课表导入'),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '课程按所属学期、周次和星期进入日程。绩点采用自定义 4.0 规则，不代表学校官方换算。',
                      ),
                    ),
                    if (_courses.isEmpty && !_busy) const Text('暂无课程'),
                    for (final course in _courses)
                      Card(
                        child: ListTile(
                          title: Text(course.name),
                          onTap: _busy
                              ? null
                              : () async {
                                  await Navigator.of(context).push<void>(
                                    MaterialPageRoute(
                                      builder: (_) => CourseDetailPage(
                                        data: widget.data,
                                        id: course.id,
                                      ),
                                    ),
                                  );
                                  if (mounted) await _load();
                                },
                          subtitle: Text(
                            '${_semesters.where((s) => s.id == course.semesterId).map((s) => s.name).firstOrNull ?? course.semesterId} · ${course.credits} 学分\n${course.slots.length} 个上课时段',
                          ),
                          trailing: PopupMenuButton<String>(
                            key: Key('course-actions-${course.id}'),
                            enabled: !_busy,
                            onSelected: (v) {
                              if (v == 'edit') {
                                _edit(course: course, isCourse: true);
                              } else if (v == 'records') {
                                _openRecords(course);
                              } else {
                                _remove(course.id, course.name, true);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('编辑')),
                              PopupMenuItem(
                                value: 'records',
                                child: Text('作业与考试'),
                              ),
                              PopupMenuItem(value: 'delete', child: Text('删除')),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

String _date(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
