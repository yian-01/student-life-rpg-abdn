import 'package:flutter/material.dart';

import '../composition/schedule_composition.dart';
import '../controllers/day_schedule_controller.dart';
import '../repositories/task_repository.dart';
import '../services/day_schedule_service.dart';
import 'day_schedule_page.dart';

/// `/schedule` 路由宿主：持有 [DayScheduleController] 并负责释放。
///
/// 装配规则（读取与写入必须落在同一个 [TaskRepository] 上）：
///
/// | loader | taskRepository | 行为 |
/// | --- | --- | --- |
/// | 已注入 | 已注入 | 读取用 loader，写入用同一仓库 |
/// | 已注入 | 未注入 | 只读：读取用 loader，隐藏新增/勾选入口 |
/// | 未注入 | 已注入 | 读取与写入共用该仓库，不注入演示数据 |
/// | 未注入 | 未注入 | 内存演示装配，显示“仅存内存”提示并注入演示数据 |
class SchedulePage extends StatefulWidget {
  const SchedulePage({
    super.key,
    this.loader,
    this.taskRepository,
    this.onRecover,
  });

  final Future<void> Function()? onRecover;
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
    final taskRepository = widget.taskRepository;

    if (loader != null) {
      _controller = DayScheduleController(
        loader: loader,
        taskRepository: taskRepository,
      );
      return;
    }

    if (taskRepository != null) {
      _controller = DayScheduleController(
        loader: ScheduleComposition.forTaskRepository(taskRepository),
        taskRepository: taskRepository,
      );
      return;
    }

    final demo = ScheduleComposition.inMemoryDemo();
    _controller = DayScheduleController(
      loader: demo,
      taskRepository: demo.taskRepository,
      demoData: true,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      DaySchedulePage(controller: _controller, onRecover: widget.onRecover);
}
