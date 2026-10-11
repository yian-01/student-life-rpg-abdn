import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/presentation/schedule_page.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_task_repository.dart';
import 'package:student_life_rpg/features/schedule/services/day_schedule_service.dart';

void main() {
  const banner = Key('day-schedule-demo-banner');
  const addButton = Key('day-schedule-add-task');

  testWidgets('injected TaskRepository drives both reads and writes', (
    tester,
  ) async {
    final repository = InMemoryTaskRepository();
    await repository.insert(
      Task(id: 'seed-1', title: '已存在任务', estimatedMinutes: 10),
    );

    await tester.pumpWidget(
      MaterialApp(home: SchedulePage(taskRepository: repository)),
    );
    await tester.pumpAndSettle();

    // 未注入 loader 时读取必须走同一个仓库，而不是新建演示仓库。
    expect(find.text('已存在任务'), findsOneWidget);
    expect(find.byKey(banner), findsNothing);
    expect(find.text('小组会议'), findsNothing, reason: '真实注入模式不得注入演示数据');

    await tester.tap(find.byKey(addButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('add-task-title')), '新任务');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();

    // 写入后刷新必须能看到同一条记录，证明读写共用同一 TaskRepository。
    expect(find.text('新任务'), findsOneWidget);
    expect(
      (await repository.list()).map((task) => task.title),
      contains('新任务'),
    );

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('injected TaskRepository can complete a task and refresh', (
    tester,
  ) async {
    final repository = InMemoryTaskRepository();
    await repository.insert(
      Task(id: 'task-1', title: '待完成任务', estimatedMinutes: 10),
    );

    await tester.pumpWidget(
      MaterialApp(home: SchedulePage(taskRepository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(find.text('待完成任务'), findsNothing);
    expect((await repository.getById('task-1'))!.isCompleted, isTrue);
  });

  testWidgets('default wiring shows the demo banner and demo data', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SchedulePage()));
    await tester.pumpAndSettle();

    expect(find.byKey(banner), findsOneWidget);
    expect(find.text('演示数据：仅存内存，退出后不保留'), findsOneWidget);
    expect(find.text('小组会议'), findsOneWidget);
  });

  testWidgets('injected loader without repository stays read-only', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: SchedulePage(loader: _EmptyLoader())),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(banner), findsNothing);
    expect(find.byKey(addButton), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
  });
}

class _EmptyLoader implements DayScheduleLoader {
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
