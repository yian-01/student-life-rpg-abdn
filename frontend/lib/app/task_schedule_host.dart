import 'package:flutter/material.dart';

import '../features/academic/presentation/assignment_exam_page.dart';
import '../features/schedule/presentation/schedule_page.dart';
import '../features/schedule/presentation/week_schedule_page.dart';
import '../features/schedule/repositories/file_task_repository.dart';
import '../features/schedule/repositories/task_repository.dart';
import '../features/schedule/presentation/schedule_record_page.dart';
import 'app_data.dart';
import 'data/campus_data.dart';
import 'campus_recovery.dart';

class TaskScheduleHost extends StatefulWidget {
  const TaskScheduleHost({super.key});

  @override
  State<TaskScheduleHost> createState() => _TaskScheduleHostState();
}

class _TaskScheduleHostState extends State<TaskScheduleHost> {
  late Future<TaskRepository> _repository = AppData.tasks();
  late Future<CampusData> _campus = AppData.campus();

  Future<void> _recover(TaskRepository repository) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新读取任务文件'),
        content: const Text(
          '将重新读取磁盘。文件损坏时尝试恢复上一有效备份，损坏原件会保留；最近一次修改可能不在备份中。恢复后请检查任务，再重试失败的操作。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await (repository as FileTaskRepository).recoverFromBackup();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已重新读取，请核对任务后重试操作。')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('恢复失败，文件已保留，请检查存储权限和备份。')));
      }
    }
  }

  Future<void> _addAssignment(CampusData data, DateTime date) async {
    final courses = await data.courses.list();
    if (!mounted) return;
    if (courses.isEmpty) {
      final openAcademic = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('先创建一门课程'),
          content: const Text('作业需要关联课程。请先新建或导入课程，再回来添加作业。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('去学期与课程'),
            ),
          ],
        ),
      );
      if (openAcademic == true && mounted) {
        await Navigator.of(context).pushNamed<void>('/academic');
      }
      return;
    }

    final semesters = {
      for (final semester in await data.semesters.list())
        semester.id: semester.name,
    };
    if (!mounted) return;
    final labels = {
      for (final course in courses)
        course.id: [
          course.name,
          ?semesters[course.semesterId],
          ?course.teacher,
        ].join(' · '),
    };
    final counts = <String, int>{};
    for (final label in labels.values) {
      counts.update(label, (count) => count + 1, ifAbsent: () => 1);
    }
    final seen = <String, int>{};
    final options = labels.map((id, label) {
      final index = seen.update(label, (count) => count + 1, ifAbsent: () => 1);
      return MapEntry(id, counts[label] == 1 ? label : '$label · $index');
    });
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AssignmentEditor.chooseCourse(
        repository: data.assignments,
        courseOptions: options,
        initialDueAt: DateTime(date.year, date.month, date.day, 23, 59),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<TaskRepository>(
    future: _repository,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        final repository = snapshot.data!;
        return FutureBuilder<CampusData>(
          future: _campus,
          builder: (context, campus) {
            final data = campus.data;
            if (data == null) {
              return Scaffold(
                appBar: AppBar(title: const Text('日程手账')),
                body: Center(
                  child: campus.hasError
                      ? TextButton(
                          onPressed: () =>
                              setState(() => _campus = AppData.campus()),
                          child: const Text('无法打开本机数据目录，点击重试'),
                        )
                      : const CircularProgressIndicator(),
                ),
              );
            }
            // Do not initialize CampusDataHost here: a corrupt Campus document
            // must not prevent the independent Task repository from displaying.
            return SchedulePage(
              loader: data.schedule(repository),
              onOpenWeek: (date) => Navigator.of(context).push<DateTime>(
                MaterialPageRoute(
                  builder: (_) => WeekSchedulePage(
                    data: data,
                    tasks: repository,
                    initialDate: date,
                  ),
                ),
              ),
              onManageEvents: (date) => Navigator.of(
                context,
              ).pushNamed<void>('/events', arguments: date),
              taskRepository: repository,
              onManageAcademic: () =>
                  Navigator.of(context).pushNamed<void>('/academic'),
              onOpenItem: (item) => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => ScheduleRecordPage(data: data, item: item),
                ),
              ),
              onAddAssignment: (date) => _addAssignment(data, date),
              onOpenAssignment: (assignment) =>
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => ScheduleRecordPage(
                        data: data,
                        assignment: assignment,
                      ),
                    ),
                  ),
              onRecoverCampus: () async {
                await recoverCampusData(context, data);
              },
              onRecover: repository is FileTaskRepository
                  ? () => _recover(repository)
                  : null,
            );
          },
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('日程手账')),
        body: Center(
          child: snapshot.hasError
              ? TextButton(
                  onPressed: () =>
                      setState(() => _repository = AppData.tasks()),
                  child: const Text('无法打开任务存储，点击重试'),
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}
