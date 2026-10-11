import 'package:flutter/material.dart';

import '../composition/schedule_composition.dart';
import '../controllers/day_schedule_controller.dart';
import '../services/day_schedule_service.dart';
import 'day_schedule_page.dart';

/// `/schedule` 路由宿主：持有 [DayScheduleController] 并负责释放。
///
/// 组合根可通过 [loader] 注入真实组合；未注入时回退到明确标注的内存演示装配，
/// 仅用于原型演示，重启不保留数据。
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key, this.loader});

  final DayScheduleLoader? loader;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  late final DayScheduleController _controller;

  @override
  void initState() {
    super.initState();
    _controller = DayScheduleController(
      loader: widget.loader ?? ScheduleComposition.inMemoryDemo(),
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
