import 'package:flutter/material.dart';
import '../../features/academic/models/assignment.dart';
import '../../features/academic/models/course.dart';
import '../../features/academic/models/exam.dart';
import '../../features/academic/presentation/assignment_exam_page.dart';
import '../../features/finance/presentation/budget_editor.dart';
import '../../features/finance/presentation/category_manager.dart';
import '../../features/finance/models/money.dart';
import '../../features/schedule/presentation/week_schedule_page.dart';
import '../app_data.dart';
import '../data/campus_data.dart';
import '../campus_data_host.dart';

/// Entrances reuse the same persistent repositories/editors as existing pages.
class GardenAcademicRecords extends StatefulWidget {
  const GardenAcademicRecords({
    super.key,
    required this.data,
    required this.exams,
  });
  final CampusData data;
  final bool exams;
  @override
  State<GardenAcademicRecords> createState() => _GardenAcademicRecordsState();
}

typedef _AcademicRows = ({
  List<Course> courses,
  List<Assignment> assignments,
  List<Exam> exams,
});

class _GardenAcademicRecordsState extends State<GardenAcademicRecords> {
  late Future<_AcademicRows> _future = _load();
  Future<_AcademicRows> _load() async => (
    courses: await widget.data.courses.list(),
    assignments: await widget.data.assignments.list(),
    exams: await widget.data.exams.list(),
  );
  Future<void> _open(Course course) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssignmentExamPage(data: widget.data, course: course),
      ),
    );
    if (mounted) {
      setState(() {
        _future = _load();
      });
    }
  }

  Future<void> _add(List<Course> courses) async {
    if (courses.isEmpty) {
      await Navigator.of(context).pushNamed('/academic');
    } else {
      final course = await showDialog<Course>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择课程'),
          children: [
            for (final course in courses)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, course),
                child: Text(course.name),
              ),
          ],
        ),
      );
      if (course == null || !mounted) return;
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => widget.exams
            ? ExamEditor(repository: widget.data.exams, courseId: course.id)
            : AssignmentEditor(
                repository: widget.data.assignments,
                courseId: course.id,
              ),
      );
    }
    if (mounted) {
      setState(() {
        _future = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.exams ? '考试' : '作业')),
    body: FutureBuilder<_AcademicRows>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() {
                _future = _load();
              }),
              child: const Text('读取失败，点击重试'),
            ),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final courses = {for (final c in data.courses) c.id: c};
        final rows = widget.exams
            ? (data.exams
                  .map((e) => (e.courseId, e.title, e.range.start))
                  .toList()
                ..sort((a, b) => a.$3.compareTo(b.$3)))
            : (data.assignments
                  .map((e) => (e.courseId, e.title, e.dueAt))
                  .toList()
                ..sort((a, b) => a.$3.compareTo(b.$3)));
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _add(data.courses),
                child: Text(widget.exams ? '添加考试' : '添加作业'),
              ),
            ),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Text(
                  data.courses.isEmpty
                      ? '先创建或导入课程，再安排作业与考试。'
                      : widget.exams
                      ? '尚无考试安排。'
                      : '尚无作业。',
                ),
              ),
            for (final row in rows)
              ListTile(
                title: Text(row.$2),
                subtitle: Text(
                  '${courses[row.$1]?.name ?? '课程不可用'} · ${row.$3.month}/${row.$3.day} ${row.$3.hour.toString().padLeft(2, '0')}:${row.$3.minute.toString().padLeft(2, '0')}',
                ),
                onTap: courses[row.$1] == null
                    ? null
                    : () => _open(courses[row.$1]!),
              ),
          ],
        );
      },
    ),
  );
}

class GardenWeekPage extends StatefulWidget {
  const GardenWeekPage({super.key});
  @override
  State<GardenWeekPage> createState() => _GardenWeekPageState();
}

class _GardenWeekPageState extends State<GardenWeekPage> {
  late final _tasks = AppData.tasks();
  @override
  Widget build(BuildContext context) => CampusDataHost(
    title: '周课表',
    builder: (context, data) => FutureBuilder(
      future: _tasks,
      builder: (context, tasks) {
        if (tasks.hasError) {
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pushNamed('/todo'),
                child: const Text('无法读取待办，打开任务恢复'),
              ),
            ),
          );
        }
        if (tasks.data == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return WeekSchedulePage(
          data: data,
          tasks: tasks.data!,
          initialDate: DateTime.now(),
        );
      },
    ),
  );
}

class GardenFinanceSettings extends StatefulWidget {
  const GardenFinanceSettings({
    super.key,
    required this.data,
    required this.budgets,
  });
  final CampusData data;
  final bool budgets;
  @override
  State<GardenFinanceSettings> createState() => _GardenFinanceSettingsState();
}

class _GardenFinanceSettingsState extends State<GardenFinanceSettings> {
  late Future<void> _load = Future<void>.delayed(
    Duration.zero,
    () => widget.data.finance.load(),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.budgets ? '预算' : '分类')),
    body: FutureBuilder<void>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() {
                _load = widget.data.finance.load();
              }),
              child: const Text('读取失败，点击重试'),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListenableBuilder(
          listenable: widget.data.finance,
          builder: (context, _) {
            if (widget.data.finance.error != null) {
              return Center(
                child: TextButton(
                  onPressed: () => setState(() {
                    _load = widget.data.finance.load();
                  }),
                  child: const Text('账本读取失败，点击重试'),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (widget.budgets)
                  BudgetSection(
                    controller: widget.data.budgetController,
                    spentByCategory: {
                      for (final c
                          in widget.data.finance.summary?.expenseByCategory ??
                              [])
                        c.categoryId: c.amountMinor,
                    },
                  )
                else ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => showCategoryManager(
                        context,
                        controller: widget.data.finance,
                      ),
                      child: const Text('管理分类'),
                    ),
                  ),
                  for (final category
                      in widget.data.finance.availableCategories)
                    ListTile(
                      title: Text(category.name),
                      subtitle: Text(
                        category.type.name == 'expense' ? '支出' : '收入',
                      ),
                    ),
                ],
                if (widget.budgets && widget.data.finance.summary != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Text(
                      '本月支出 ¥ ${formatAmountMinor(widget.data.finance.summary!.expenseMinor)}',
                    ),
                  ),
              ],
            );
          },
        );
      },
    ),
  );
}
