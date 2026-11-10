import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/schedule/controllers/day_schedule_controller.dart';
import 'package:student_life_rpg/features/schedule/models/event.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/presentation/day_schedule_page.dart';
import 'package:student_life_rpg/features/schedule/presentation/event_management_page.dart';
import 'package:student_life_rpg/features/schedule/presentation/task_editor_dialog.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_event_repository.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_task_repository.dart';
import 'package:student_life_rpg/features/schedule/services/day_schedule_service.dart';
import 'package:student_life_rpg/shared/models/schedule_item.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';

import '../support/campus_fixture.dart';

final _day = DateTime(2027, 2, 8);

DaySchedule _empty(DateTime date) => DaySchedule(
  date: date,
  items: const [],
  unscheduledTasks: const [],
  completedTaskIds: const {},
);

class _Loader implements DayScheduleLoader {
  _Loader(this.load);
  final Future<DaySchedule> Function(DateTime) load;
  @override
  Future<DaySchedule> loadDay(DateTime date) => load(date);
}

DayScheduleController _controller({
  InMemoryTaskRepository? tasks,
  InMemoryEventRepository? events,
  DateTime? date,
  CourseOccurrencesForDate? courses,
}) => DayScheduleController(
  initialDate: date ?? _day,
  taskRepository: tasks,
  loader: DayScheduleService(
    taskRepository: tasks ?? InMemoryTaskRepository(),
    eventRepository: events ?? InMemoryEventRepository(),
    courseOccurrencesForDate: courses ?? (_) async => [],
  ),
);

Future<void> _pump(
  WidgetTester tester,
  DayScheduleController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(home: DaySchedulePage(controller: controller)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'date title opens picker; cancel and system back preserve date; today resets it',
    (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      final title = find.byKey(const Key('schedule-select-date'));
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.selectedDate, _day);

      await tester.tap(title);
      await tester.pumpAndSettle();
      await tester.tap(find.text('15').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(controller.selectedDate, DateTime(2027, 2, 15));
      await tester.tap(title);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.selectedDate, DateTime(2027, 2, 15));

      await tester.tap(find.byKey(const Key('schedule-today')));
      await tester.pumpAndSettle();
      final now = DateTime.now();
      expect(controller.selectedDate, DateTime(now.year, now.month, now.day));
    },
  );

  testWidgets(
    'rapid navigation stays enabled and stale failure cannot overwrite newest day',
    (tester) async {
      final requests = <DateTime, Completer<DaySchedule>>{};
      final controller = DayScheduleController(
        initialDate: _day,
        loader: _Loader(
          (date) => (requests[date] = Completer<DaySchedule>()).future,
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: DaySchedulePage(controller: controller)),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('后一天'));
      await tester.pump();
      await tester.tap(find.byTooltip('后一天'));
      await tester.pump();
      final latest = DateTime(2027, 2, 10);
      expect(requests.keys, [_day, DateTime(2027, 2, 9), latest]);
      requests[latest]!.complete(_empty(latest));
      await tester.pumpAndSettle();
      requests[_day]!.completeError(StateError('stale error'));
      requests[DateTime(2027, 2, 9)]!.complete(_empty(DateTime(2027, 2, 9)));
      await tester.pumpAndSettle();
      expect(controller.schedule!.date, latest);
      expect(controller.errorMessage, isNull);
    },
  );

  testWidgets(
    'returning from event management keeps selected date and refreshes changes',
    (tester) async {
      final events = InMemoryEventRepository();
      final controller = _controller(events: events);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => DaySchedulePage(
              controller: controller,
              onManageEvents: (date) async {
                expect(date, _day);
                await events.insert(
                  Event(
                    id: 'linked',
                    title: '返回后出现',
                    range: TimeRange(start: date, end: DateTime(2027, 2, 8, 1)),
                  ),
                );
                if (context.mounted) {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const Scaffold(body: Text('事件管理')),
                    ),
                  );
                }
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('manage-events')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.selectedDate, _day);
      expect(find.text('返回后出现'), findsOneWidget);
    },
  );

  testWidgets(
    'cross-day and cross-year labels retain actual endpoints including midnight',
    (tester) async {
      final events = InMemoryEventRepository();
      await events.insert(
        Event(
          id: 'night',
          title: '跨日',
          range: TimeRange(
            start: DateTime(2027, 2, 8, 23, 30),
            end: DateTime(2027, 2, 9, 0, 30),
          ),
        ),
      );
      await events.insert(
        Event(
          id: 'midnight',
          title: '午夜结束',
          range: TimeRange(
            start: DateTime(2027, 2, 8, 23),
            end: DateTime(2027, 2, 9),
          ),
        ),
      );
      await events.insert(
        Event(
          id: 'year',
          title: '跨年',
          range: TimeRange(
            start: DateTime(2027, 12, 31, 23, 30),
            end: DateTime(2028, 1, 1, 0, 30),
          ),
        ),
      );
      final controller = _controller(events: events);
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      expect(find.textContaining('02-08 23:30 → 02-09 00:30'), findsOneWidget);
      expect(find.textContaining('02-08 23:00 → 02-09 00:00'), findsOneWidget);
      await controller.loadDay(DateTime(2027, 2, 9));
      await tester.pumpAndSettle();
      expect(find.text('午夜结束'), findsNothing);
      expect(find.textContaining('02-08 23:30 → 02-09 00:30'), findsOneWidget);
      await controller.loadDay(DateTime(2028, 1, 1));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('2027-12-31 23:30 → 2028-01-01 00:30'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'scheduled task expands estimate and independent deadline from same snapshot',
    (tester) async {
      final tasks = InMemoryTaskRepository();
      await tasks.insert(
        Task(
          id: 'planned',
          title: '准备报告',
          estimatedMinutes: 45,
          dueAt: DateTime(2027, 2, 10, 18),
          scheduledRange: TimeRange(
            start: DateTime(2027, 2, 8, 9),
            end: DateTime(2027, 2, 8, 10),
          ),
        ),
      );
      final controller = _controller(tasks: tasks);
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      expect(find.textContaining('计划 09:00 - 10:00'), findsOneWidget);
      final details = find.byKey(const Key('scheduled-task-details-planned'));
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(find.text('估时 45 分钟'), findsOneWidget);
      expect(find.text('截止 2027-02-10 18:00'), findsOneWidget);
      await controller.updateTask(
        'planned',
        title: '准备报告',
        estimatedMinutes: 75,
        dueAt: null,
        scheduledRange: (await tasks.getById('planned'))!.scheduledRange,
      );
      await tester.pumpAndSettle();
      expect(find.text('估时 75 分钟'), findsOneWidget);
      expect(find.text('截止：未设置'), findsOneWidget);
      expect(find.text('截止 2027-02-10 18:00'), findsNothing);
    },
  );

  testWidgets(
    'three mixed active items show three pairs and full source labels; completion removes two pairs',
    (tester) async {
      final tasks = InMemoryTaskRepository();
      final events = InMemoryEventRepository();
      final range = TimeRange(
        start: DateTime(2027, 2, 8, 9),
        end: DateTime(2027, 2, 8, 10),
      );
      await tasks.insert(
        Task(
          id: 'same',
          title: '同名',
          estimatedMinutes: 30,
          scheduledRange: range,
        ),
      );
      await events.insert(Event(id: 'same', title: '同名', range: range));
      final controller = _controller(
        tasks: tasks,
        events: events,
        courses: (_) async => [
          ScheduleItem(
            id: 'course:same',
            sourceId: 'same',
            sourceType: ScheduleSourceType.course,
            title: '同名',
            range: range,
          ),
        ],
      );
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      expect(find.text('时间冲突 · 3 对冲突'), findsOneWidget);
      expect(find.textContaining('课程：同名 / 事件：同名'), findsOneWidget);
      expect(find.textContaining('事件：同名 / 任务：同名'), findsOneWidget);
      await controller.setTaskCompleted('same', true);
      await tester.pumpAndSettle();
      expect(controller.schedule!.items, hasLength(3));
      expect(find.text('时间冲突 · 1 对冲突'), findsOneWidget);
      expect(find.textContaining('任务：同名'), findsNothing);
    },
  );

  testWidgets('unscheduled section clearly covers all dates', (tester) async {
    final tasks = InMemoryTaskRepository();
    await tasks.insert(
      Task(id: 'global', title: '所有日期可见', estimatedMinutes: 20),
    );
    final controller = _controller(tasks: tasks);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    expect(find.text('未安排任务（全部日期）'), findsOneWidget);
    await tester.tap(find.byTooltip('后一天'));
    await tester.pumpAndSettle();
    expect(find.text('所有日期可见'), findsOneWidget);
  });

  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets(
      '$width width large text and keyboard retain form, errors and submit access',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);
        final tasks = InMemoryTaskRepository();
        await tasks.insert(
          Task(
            id: 'long',
            title: '长文案课程设计报告与小组成果材料' * 5,
            estimatedMinutes: 50,
            dueAt: DateTime(2027, 2, 10, 18),
            scheduledRange: TimeRange(
              start: DateTime(2027, 2, 8, 9),
              end: DateTime(2027, 2, 8, 10),
            ),
          ),
        );
        final controller = _controller(tasks: tasks);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: DaySchedulePage(controller: controller),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('day-schedule-add-task')));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        final submit = find.widgetWithText(FilledButton, '添加');
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        final error = find.text('请输入任务标题');
        await tester.ensureVisible(error);
        expect(error.hitTestable(), findsOneWidget);
        final title = find.byKey(const Key('add-task-title'));
        final minutes = find.byKey(const Key('add-task-minutes'));
        await tester.ensureVisible(title);
        await tester.enterText(title, '键盘下的新任务');
        await tester.ensureVisible(minutes);
        await tester.enterText(minutes, '35');
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(
          (await tasks.list()).where((t) => t.title == '键盘下的新任务'),
          hasLength(1),
        );
        expect(find.byType(TaskEditorDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'event editor double-open and deletion cancellation keep one route and data',
    (tester) async {
      final data = emptyCampusData();
      addTearDown(data.dispose);
      await data.events.insert(
        Event(
          id: 'event',
          title: '保留事件',
          range: TimeRange(start: _day, end: DateTime(2027, 2, 8, 1)),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: EventManagementPage(data: data, initialDate: _day),
        ),
      );
      await tester.pumpAndSettle();
      final add = tester
          .widget<FloatingActionButton>(find.byKey(const Key('new-event')))
          .onPressed!;
      add();
      add();
      await tester.pumpAndSettle();
      expect(find.byType(EventEditor), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final menu = tester.widget<PopupMenuButton<String>>(
        find.byKey(const Key('event-actions-event')),
      );
      menu.onSelected!('delete');
      menu.onSelected!('delete');
      await tester.pumpAndSettle();
      expect(find.text('确认删除？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await data.events.list(), hasLength(1));
      await tester.tap(find.byKey(const Key('new-event')));
      await tester.pumpAndSettle();
      expect(find.byType(EventEditor), findsOneWidget);
    },
  );
}
