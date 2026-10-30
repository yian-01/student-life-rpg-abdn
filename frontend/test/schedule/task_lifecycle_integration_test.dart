import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/schedule/controllers/day_schedule_controller.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/presentation/day_schedule_page.dart';
import 'package:student_life_rpg/features/schedule/presentation/task_editor_dialog.dart';
import 'package:student_life_rpg/features/schedule/repositories/file_task_repository.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_event_repository.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_task_repository.dart';
import 'package:student_life_rpg/features/schedule/repositories/task_repository.dart';
import 'package:student_life_rpg/features/schedule/services/day_schedule_service.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';

final day = DateTime(2026, 10, 5);
TimeRange range(int startHour, int startMinute, int endHour, int endMinute) =>
    TimeRange(
      start: DateTime(2026, 10, 5, startHour, startMinute),
      end: DateTime(2026, 10, 5, endHour, endMinute),
    );

DayScheduleController controllerFor(TaskRepository repository) =>
    DayScheduleController(
      loader: DayScheduleService(
        taskRepository: repository,
        eventRepository: InMemoryEventRepository(),
        courseOccurrencesForDate: (_) async => [],
      ),
      taskRepository: repository,
      initialDate: day,
      idGenerator: () => 'new-task',
    );

Future<void> openEdit(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('task-actions-$id')).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('编辑 / 安排时间'));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'edits, cross-day scheduling, clearing and deletion survive reopening disk storage',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'task-lifecycle-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/tasks.json';
      FileTaskRepository reopen() =>
          FileTaskRepository(const FileJsonDocumentStore(), path);
      final controller = controllerFor(reopen());
      addTearDown(controller.dispose);
      final due = DateTime(2026, 10, 8, 18);
      final scheduled = TimeRange(
        start: DateTime(2026, 10, 5, 23),
        end: DateTime(2026, 10, 6, 1),
      );
      await controller.addTask(title: '原始任务', estimatedMinutes: 30, dueAt: due);
      await controller.setTaskCompleted('new-task', true);
      await controller.updateTask(
        'new-task',
        title: '修改后',
        estimatedMinutes: 45,
        dueAt: due,
        scheduledRange: scheduled,
      );
      var restored = (await reopen().list()).single;
      expect(restored.title, '修改后');
      expect(restored.isCompleted, isTrue);
      expect(restored.dueAt, due);
      expect(restored.scheduledRange!.end, scheduled.end);
      await controller.loadDay(DateTime(2026, 10, 6));
      expect(controller.schedule!.items.single.title, '修改后');
      expect(
        controller.schedule!.isCrossDay(controller.schedule!.items.single),
        isTrue,
      );
      await controller.updateTask(
        'new-task',
        title: '修改后',
        estimatedMinutes: 45,
        dueAt: due,
        scheduledRange: null,
      );
      restored = (await reopen().list()).single;
      expect(restored.scheduledRange, isNull);
      expect(
        restored.dueAt,
        due,
        reason: 'Clearing a plan must not erase its deadline',
      );
      await controller.setTaskCompleted('new-task', false);
      expect(controller.schedule!.unscheduledTasks.single.id, 'new-task');
      await controller.removeTask('new-task');
      expect(await reopen().list(), isEmpty);
    },
  );

  test('conflicts use strict overlap and omit completed tasks', () async {
    final repository = InMemoryTaskRepository();
    for (final task in [
      Task(
        id: 'a',
        title: 'A',
        estimatedMinutes: 60,
        scheduledRange: range(9, 0, 10, 0),
      ),
      Task(
        id: 'b',
        title: 'B',
        estimatedMinutes: 60,
        scheduledRange: range(10, 0, 11, 0),
      ),
      Task(
        id: 'c',
        title: 'C',
        estimatedMinutes: 30,
        scheduledRange: range(9, 30, 10, 0),
      ),
    ]) {
      await repository.insert(task);
    }
    final controller = controllerFor(repository);
    addTearDown(controller.dispose);
    await controller.loadDay();
    expect(controller.conflicts, hasLength(1));
    await controller.setTaskCompleted('c', true);
    expect(controller.conflicts, isEmpty);
    await controller.setTaskCompleted('c', false);
    expect(controller.conflicts, hasLength(1));
  });

  testWidgets(
    'new task enters the selected day and displays existing conflict results',
    (tester) async {
      final repository = InMemoryTaskRepository();
      await repository.insert(
        Task(
          id: 'existing',
          title: '原有安排',
          estimatedMinutes: 60,
          scheduledRange: range(9, 30, 10, 30),
        ),
      );
      final controller = controllerFor(repository);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: DaySchedulePage(controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('day-schedule-add-task')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('add-task-title')), '新安排');
      await tester.ensureVisible(
        find.byKey(const Key('task-scheduled-switch')),
      );
      await tester.tap(find.byKey(const Key('task-scheduled-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '添加'));
      await tester.pumpAndSettle();
      final task = (await repository.getById('new-task'))!;
      expect(task.scheduledRange!.start, DateTime(2026, 10, 5, 9));
      expect(task.dueAt, isNull);
      expect(controller.schedule!.items, hasLength(2));
      expect(find.byKey(const Key('day-schedule-conflicts')), findsOneWidget);
      expect(find.text('时间冲突 · 1 处'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('edit can clear a plan without losing the independent deadline', (
    tester,
  ) async {
    final repository = InMemoryTaskRepository();
    final due = DateTime(2026, 10, 8, 18);
    await repository.insert(
      Task(
        id: 'edit',
        title: '旧标题',
        estimatedMinutes: 30,
        dueAt: due,
        scheduledRange: range(9, 0, 10, 0),
      ),
    );
    final controller = controllerFor(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: DaySchedulePage(controller: controller)),
    );
    await tester.pumpAndSettle();
    await openEdit(tester, 'edit');
    await tester.enterText(find.byKey(const Key('add-task-title')), '新标题');
    await tester.ensureVisible(find.byKey(const Key('task-scheduled-switch')));
    await tester.tap(find.byKey(const Key('task-scheduled-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    final task = (await repository.getById('edit'))!;
    expect(task.scheduledRange, isNull);
    expect(task.dueAt, due);
    expect(find.text('新标题'), findsOneWidget);
    expect(controller.schedule!.items, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('completed task can be reopened, delete requires confirmation', (
    tester,
  ) async {
    final repository = InMemoryTaskRepository();
    await repository.insert(
      Task(id: 'done', title: '已完成', estimatedMinutes: 10, isCompleted: true),
    );
    final controller = controllerFor(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: DaySchedulePage(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('completed-tasks')));
    await tester.tap(find.byKey(const Key('completed-tasks')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect((await repository.getById('done'))!.isCompleted, isFalse);
    await tester.tap(find.byKey(const Key('task-actions-done')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await repository.list(), hasLength(1));
    await tester.tap(find.byKey(const Key('task-actions-done')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(await repository.list(), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed save retains the draft, retry writes once', (
    tester,
  ) async {
    var attempts = 0;
    TaskEditorValue? written;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => TaskEditorDialog(
                  selectedDate: day,
                  onSave: (value) async {
                    if (++attempts == 1) {
                      throw const FileSystemException('disk full');
                    }
                    written = value;
                  },
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('add-task-title')), '保留输入');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();
    expect(find.text('任务保存失败，请重试。'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('add-task-title')))
          .controller!
          .text,
      '保留输入',
    );
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();
    expect(written!.title, '保留输入');
    expect(attempts, 2);
    expect(find.byType(TaskEditorDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('invalid reversed range stays in editor without writing', (
    tester,
  ) async {
    var writes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TaskEditorDialog(
          selectedDate: day,
          task: Task(
            id: 'bad-range',
            title: '校验',
            estimatedMinutes: 10,
            scheduledRange: range(9, 0, 10, 0),
          ),
          onSave: (_) async {
            writes++;
          },
        ),
      ),
    );
    // Select a later start with the native time input; the end remains 10:00.
    await tester.ensureVisible(find.text('09:00'));
    await tester.tap(find.text('09:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, '11');
    await tester.enterText(fields.last, '00');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('结束时间必须晚于开始时间'), findsOneWidget);
    expect(writes, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
