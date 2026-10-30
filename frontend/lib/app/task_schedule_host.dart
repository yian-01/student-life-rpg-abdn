import 'package:flutter/material.dart';

import '../features/schedule/presentation/schedule_page.dart';
import '../features/schedule/repositories/file_task_repository.dart';
import '../features/schedule/repositories/task_repository.dart';
import 'app_data.dart';

class TaskScheduleHost extends StatefulWidget {
  const TaskScheduleHost({super.key});

  @override
  State<TaskScheduleHost> createState() => _TaskScheduleHostState();
}

class _TaskScheduleHostState extends State<TaskScheduleHost> {
  late Future<TaskRepository> _repository = AppData.tasks();
  int _generation = 0;

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
      setState(() => _generation++);
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

  @override
  Widget build(BuildContext context) => FutureBuilder<TaskRepository>(
    future: _repository,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        final repository = snapshot.data!;
        return SchedulePage(
          key: ValueKey(_generation),
          taskRepository: repository,
          onRecover: repository is FileTaskRepository
              ? () => _recover(repository)
              : null,
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
