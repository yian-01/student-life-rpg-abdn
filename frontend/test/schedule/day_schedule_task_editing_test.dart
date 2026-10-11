import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/schedule/controllers/day_schedule_controller.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/presentation/day_schedule_page.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_event_repository.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_task_repository.dart';
import 'package:student_life_rpg/features/schedule/repositories/task_repository.dart';
import 'package:student_life_rpg/features/schedule/services/day_schedule_service.dart';
import 'package:student_life_rpg/shared/models/schedule_item.dart';

void main() {
  group('DayScheduleController task editing', () {
    test(
      'addTask writes through the repository and refreshes the day',
      () async {
        final taskRepository = InMemoryTaskRepository();
        final controller = _controllerFor(
          taskRepository: taskRepository,
          idGenerator: () => 'task-generated-1',
        );
        addTearDown(controller.dispose);

        await controller.loadDay();
        expect(controller.schedule!.unscheduledTasks, isEmpty);

        await controller.addTask(title: 'New task', estimatedMinutes: 25);

        expect(controller.schedule!.unscheduledTasks.map((task) => task.id), [
          'task-generated-1',
        ]);
        expect(
          (await taskRepository.getById('task-generated-1'))!.title,
          'New task',
        );
      },
    );

    test('setTaskCompleted toggles state and refreshes the day', () async {
      final taskRepository = InMemoryTaskRepository();
      await taskRepository.insert(
        Task(id: 'task-1', title: 'Task', estimatedMinutes: 10),
      );
      final controller = _controllerFor(taskRepository: taskRepository);
      addTearDown(controller.dispose);

      await controller.loadDay();
      expect(controller.schedule!.unscheduledTasks, hasLength(1));

      await controller.setTaskCompleted('task-1', true);
      expect(controller.schedule!.unscheduledTasks, isEmpty);
      expect((await taskRepository.getById('task-1'))!.isCompleted, isTrue);

      await controller.loadDay();
      expect(controller.schedule!.unscheduledTasks, isEmpty);
    });

    test('editing without an injected repository throws StateError', () async {
      final controller = DayScheduleController(
        loader: _EmptyLoader(),
        initialDate: DateTime(2026, 10, 5),
      );
      addTearDown(controller.dispose);

      expect(controller.canEditTasks, isFalse);
      await expectLater(
        controller.addTask(title: 'Task', estimatedMinutes: 10),
        throwsStateError,
      );
      await expectLater(
        controller.setTaskCompleted('task-1', true),
        throwsStateError,
      );
    });

    test('invalid input throws ArgumentError and writes nothing', () async {
      final taskRepository = InMemoryTaskRepository();
      final controller = _controllerFor(taskRepository: taskRepository);
      addTearDown(controller.dispose);

      await expectLater(
        controller.addTask(title: '   ', estimatedMinutes: 10),
        throwsArgumentError,
      );
      await expectLater(
        controller.addTask(title: 'Task', estimatedMinutes: 0),
        throwsArgumentError,
      );
      expect(await taskRepository.list(), isEmpty);
    });

    test('repository failures propagate to the caller', () async {
      final controller = _controllerFor(
        taskRepository: _FailingTaskRepository(),
      );
      addTearDown(controller.dispose);

      await expectLater(
        controller.addTask(title: 'Task', estimatedMinutes: 10),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('DaySchedulePage task editing', () {
    testWidgets('adds a task through the dialog and lists it as unscheduled', (
      tester,
    ) async {
      final taskRepository = InMemoryTaskRepository();
      final controller = _controllerFor(
        taskRepository: taskRepository,
        idGenerator: () => 'task-generated-1',
      );
      addTearDown(controller.dispose);

      await _pumpPage(tester, controller);
      expect(find.text('暂无未安排任务'), findsOneWidget);

      await tester.tap(find.byKey(const Key('day-schedule-add-task')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('add-task-title')), '阅读第二章');
      await tester.enterText(find.byKey(const Key('add-task-minutes')), '45');
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();

      expect(find.text('阅读第二章'), findsOneWidget);
      expect(find.text('暂无未安排任务'), findsNothing);
      expect((await taskRepository.list()).single.estimatedMinutes, 45);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('rejects an empty title inside the dialog', (tester) async {
      final controller = _controllerFor(
        taskRepository: InMemoryTaskRepository(),
      );
      addTearDown(controller.dispose);

      await _pumpPage(tester, controller);
      await tester.tap(find.byKey(const Key('day-schedule-add-task')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();

      expect(find.text('请输入任务标题'), findsOneWidget);
      expect(find.byKey(const Key('add-task-title')), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });

    testWidgets('completing a task removes it from the unscheduled section', (
      tester,
    ) async {
      final taskRepository = InMemoryTaskRepository();
      await taskRepository.insert(
        Task(id: 'task-1', title: 'Task', estimatedMinutes: 10),
      );
      final controller = _controllerFor(taskRepository: taskRepository);
      addTearDown(controller.dispose);

      await _pumpPage(tester, controller);
      expect(find.text('Task'), findsOneWidget);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      expect(find.text('Task'), findsNothing);
      expect(find.text('暂无未安排任务'), findsOneWidget);
      expect((await taskRepository.getById('task-1'))!.isCompleted, isTrue);
    });

    testWidgets('shows retry feedback when saving fails', (tester) async {
      final controller = _controllerFor(
        taskRepository: _FailingTaskRepository(),
      );
      addTearDown(controller.dispose);

      await _pumpPage(tester, controller);
      await tester.tap(find.byKey(const Key('day-schedule-add-task')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('add-task-title')), 'Task');
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();

      expect(find.text('任务保存失败，请重试。'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });
}

DayScheduleController _controllerFor({
  required TaskRepository taskRepository,
  TaskIdGenerator? idGenerator,
}) {
  return DayScheduleController(
    loader: DayScheduleService(
      taskRepository: taskRepository,
      eventRepository: InMemoryEventRepository(),
      courseOccurrencesForDate: (_) async => const <ScheduleItem>[],
    ),
    taskRepository: taskRepository,
    idGenerator: idGenerator,
    initialDate: DateTime(2026, 10, 5),
  );
}

Future<void> _pumpPage(
  WidgetTester tester,
  DayScheduleController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(home: DaySchedulePage(controller: controller)),
  );
  await tester.pumpAndSettle();
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

class _FailingTaskRepository implements TaskRepository {
  @override
  Future<List<Task>> list() async => const [];

  @override
  Future<Task?> getById(String id) async => null;

  @override
  Future<void> insert(Task entity) async {
    throw StateError('disk offline');
  }

  @override
  Future<void> update(Task entity) async {
    throw StateError('disk offline');
  }

  @override
  Future<bool> remove(String id) async => false;

  @override
  Future<void> setCompleted(String id, bool isCompleted) async {
    throw StateError('disk offline');
  }
}
