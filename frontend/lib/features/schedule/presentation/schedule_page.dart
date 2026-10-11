import 'package:flutter/material.dart';

import '../composition/schedule_composition.dart';
import '../controllers/day_schedule_controller.dart';
import '../repositories/task_repository.dart';
import '../services/day_schedule_service.dart';
import 'day_schedule_page.dart';

/// `/schedule` 路由宿主：持有 [DayScheduleController] 并负责释放。
///
/// 组合根可注入真实组合（[loader] + [taskRepository]，后者用于新增任务与切换完成
/// 状态）；未注入时回退到明确标注的内存演示装配，仅用于原型演示，重启不保留数据。
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key, this.loader, this.taskRepository});

  final DayScheduleLoader? loader;
  final TaskRepository? taskRepository;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  late final DayScheduleController _controller;

  @override
  void initState() {
    super.initState();
    final loader = widget.loader;
    if (loader == null) {
      final demo = ScheduleComposition.inMemoryDemo();
      _controller = DayScheduleController(
        loader: demo,
        taskRepository: widget.taskRepository ?? demo.taskRepository,
      );
      return;
    }
    _controller = DayScheduleController(
      loader: loader,
      taskRepository: widget.taskRepository,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      DaySchedulePage(controller: _controller);
}
