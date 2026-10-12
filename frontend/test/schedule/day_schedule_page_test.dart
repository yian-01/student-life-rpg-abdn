import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/schedule/controllers/day_schedule_controller.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/presentation/day_schedule_page.dart';
import 'package:student_life_rpg/features/schedule/presentation/schedule_page.dart';
import 'package:student_life_rpg/features/schedule/services/day_schedule_service.dart';
import 'package:student_life_rpg/shared/models/schedule_item.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';

void main() {
  testWidgets('shows empty states and allows date navigation', (tester) async {
    final controller = DayScheduleController(
      loader: _FakeLoader(),
      initialDate: DateTime(2026, 10, 5),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: DaySchedulePage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026-10-05'), findsOneWidget);
    expect(find.text('今日暂无已排程事项'), findsOneWidget);
    expect(find.text('暂无未安排任务'), findsOneWidget);

    await tester.tap(find.byTooltip('后一天'));
    await tester.pumpAndSettle();
    expect(find.text('2026-10-06'), findsOneWidget);
  });

  testWidgets('shows a retry action when loading fails', (tester) async {
    final controller = DayScheduleController(
      loader: _FailingLoader(),
      initialDate: DateTime(2026, 10, 5),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: DaySchedulePage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('日程加载失败，请重试。'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('host page loads through an injected loader', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SchedulePage(loader: _FakeLoader())),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DaySchedulePage), findsOneWidget);
    expect(find.text('今日暂无已排程事项'), findsOneWidget);
  });

  testWidgets('renders long text without overflow on a small window', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(240, 320);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final controller = DayScheduleController(
      loader: _LongTextLoader(),
      initialDate: DateTime(2026, 10, 5),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: DaySchedulePage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('超长标题'), findsOneWidget);
  });
}

class _FakeLoader implements DayScheduleLoader {
  @override
  Future<DaySchedule> loadDay(DateTime date) async {
    return DaySchedule(
      date: date,
      items: const [],
      unscheduledTasks: const [],
      completedTaskIds: const {},
    );
  }
}

class _FailingLoader implements DayScheduleLoader {
  @override
  Future<DaySchedule> loadDay(DateTime date) {
    return Future<DaySchedule>.error(StateError('offline'));
  }
}

class _LongTextLoader implements DayScheduleLoader {
  @override
  Future<DaySchedule> loadDay(DateTime date) async {
    return DaySchedule(
      date: DateTime(2026, 10, 5),
      items: [
        ScheduleItem(
          id: 'task:long:20261005:100000000000',
          sourceId: 'long',
          sourceType: ScheduleSourceType.task,
          title: '超长标题：数据结构与算法课程设计说明书最终修订版与附加说明文档',
          range: TimeRange(
            start: DateTime(2026, 10, 5, 10),
            end: DateTime(2026, 10, 5, 11),
          ),
        ),
      ],
      unscheduledTasks: [
        Task(
          id: 'long-unscheduled',
          title: '另一个特别长的未安排任务名称用于检查换行与溢出行为',
          estimatedMinutes: 30,
        ),
      ],
      completedTaskIds: const {},
    );
  }
}
