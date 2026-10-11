import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/schedule/models/event.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_event_repository.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_task_repository.dart';
import 'package:student_life_rpg/features/schedule/services/day_schedule_service.dart';
import 'package:student_life_rpg/shared/models/schedule_item.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';

void main() {
  group('DayScheduleService', () {
    test(
      'uses the requested local day and filters course occurrences',
      () async {
        final taskRepository = InMemoryTaskRepository();
        final eventRepository = InMemoryEventRepository();
        final requestedDates = <DateTime>[];
        final service = DayScheduleService(
          taskRepository: taskRepository,
          eventRepository: eventRepository,
          courseOccurrencesForDate: (date) async {
            requestedDates.add(date);
            if (date == DateTime(2026, 10, 5)) {
              return [
                ScheduleItem(
                  id: 'course:g-1:0:20261005',
                  sourceId: 'g-1',
                  sourceType: ScheduleSourceType.course,
                  title: 'Week 1 course',
                  range: TimeRange(
                    start: DateTime(2026, 10, 5, 8),
                    end: DateTime(2026, 10, 5, 9),
                  ),
                ),
              ];
            }
            return const <ScheduleItem>[];
          },
        );

        final weekOne = await service.loadDay(DateTime(2026, 10, 5, 12));
        final weekTwo = await service.loadDay(DateTime(2026, 10, 12, 12));

        expect(
          weekOne.items.map((item) => item.title),
          contains('Week 1 course'),
        );
        expect(weekTwo.items, isEmpty);
        expect(requestedDates[0], DateTime(2026, 10, 5));
        expect(requestedDates[1], DateTime(2026, 10, 12));
      },
    );

    test('rejects UTC query dates', () async {
      final service = DayScheduleService(
        taskRepository: InMemoryTaskRepository(),
        eventRepository: InMemoryEventRepository(),
        courseOccurrencesForDate: (_) async => const [],
      );

      await expectLater(
        service.loadDay(DateTime.utc(2026, 10, 5)),
        throwsArgumentError,
      );
    });

    test(
      'cross-midnight item appears on both days with its full range',
      () async {
        final eventRepository = InMemoryEventRepository();
        await eventRepository.insert(
          Event(
            id: 'event-overnight',
            title: 'Overnight',
            range: TimeRange(
              start: DateTime(2026, 10, 5, 23, 30),
              end: DateTime(2026, 10, 6, 0, 30),
            ),
          ),
        );
        final service = DayScheduleService(
          taskRepository: InMemoryTaskRepository(),
          eventRepository: eventRepository,
          courseOccurrencesForDate: (_) async => const [],
        );

        final monday = await service.loadDay(DateTime(2026, 10, 5));
        final tuesday = await service.loadDay(DateTime(2026, 10, 6));

        expect(monday.items.single.title, 'Overnight');
        expect(tuesday.items.single.title, 'Overnight');
        expect(monday.items.single.range.start, DateTime(2026, 10, 5, 23, 30));
        expect(monday.isCrossDay(monday.items.single), isTrue);
        expect(tuesday.isCrossDay(tuesday.items.single), isTrue);
      },
    );

    test('end exactly at midnight does not leak into the next day', () async {
      final eventRepository = InMemoryEventRepository();
      await eventRepository.insert(
        Event(
          id: 'event-until-midnight',
          title: 'Until midnight',
          range: TimeRange(
            start: DateTime(2026, 10, 5, 23),
            end: DateTime(2026, 10, 6),
          ),
        ),
      );
      final service = DayScheduleService(
        taskRepository: InMemoryTaskRepository(),
        eventRepository: eventRepository,
        courseOccurrencesForDate: (_) async => const [],
      );

      final monday = await service.loadDay(DateTime(2026, 10, 5));
      final tuesday = await service.loadDay(DateTime(2026, 10, 6));

      expect(monday.items, hasLength(1));
      expect(monday.isCrossDay(monday.items.single), isFalse);
      expect(tuesday.items, isEmpty);
    });

    test('sorts by start, end, source type, and id', () async {
      final eventRepository = InMemoryEventRepository();
      final taskRepository = InMemoryTaskRepository();
      final start = DateTime(2026, 10, 5, 10);
      final end = DateTime(2026, 10, 5, 11);

      await eventRepository.insert(
        Event(
          id: 'z-event',
          title: 'Event',
          range: TimeRange(start: start, end: end),
        ),
      );
      await taskRepository.insert(
        Task(
          id: 'a-task',
          title: 'Task',
          estimatedMinutes: 60,
          scheduledRange: TimeRange(start: start, end: end),
        ),
      );

      final service = DayScheduleService(
        taskRepository: taskRepository,
        eventRepository: eventRepository,
        courseOccurrencesForDate: (_) async => [
          ScheduleItem(
            id: 'z-course',
            sourceId: 'course',
            sourceType: ScheduleSourceType.course,
            title: 'Course',
            range: TimeRange(start: start, end: end),
          ),
        ],
      );

      final result = await service.loadDay(start);
      expect(result.items.map((item) => item.sourceType), [
        ScheduleSourceType.course,
        ScheduleSourceType.event,
        ScheduleSourceType.task,
      ]);
    });

    test('sorts equal ranges by end time then id', () async {
      final eventRepository = InMemoryEventRepository();
      await eventRepository.insert(
        Event(
          id: 'b-short',
          title: 'Short',
          range: TimeRange(
            start: DateTime(2026, 10, 5, 10),
            end: DateTime(2026, 10, 5, 10, 30),
          ),
        ),
      );
      await eventRepository.insert(
        Event(
          id: 'a-long',
          title: 'Long',
          range: TimeRange(
            start: DateTime(2026, 10, 5, 10),
            end: DateTime(2026, 10, 5, 12),
          ),
        ),
      );

      final service = DayScheduleService(
        taskRepository: InMemoryTaskRepository(),
        eventRepository: eventRepository,
        courseOccurrencesForDate: (_) async => const [],
      );

      final result = await service.loadDay(DateTime(2026, 10, 5));
      expect(result.items.map((item) => item.title), ['Short', 'Long']);
    });

    test(
      'unscheduled section excludes completed tasks and sorts dueAt last',
      () async {
        final taskRepository = InMemoryTaskRepository();
        await taskRepository.insert(
          Task(
            id: 'task-later',
            title: 'Later',
            estimatedMinutes: 10,
            dueAt: DateTime(2026, 10, 7),
          ),
        );
        await taskRepository.insert(
          Task(id: 'task-no-due', title: 'No due date', estimatedMinutes: 10),
        );
        await taskRepository.insert(
          Task(
            id: 'task-done',
            title: 'Done',
            estimatedMinutes: 10,
            isCompleted: true,
          ),
        );

        final service = DayScheduleService(
          taskRepository: taskRepository,
          eventRepository: InMemoryEventRepository(),
          courseOccurrencesForDate: (_) async => const [],
        );

        final result = await service.loadDay(DateTime(2026, 10, 5));
        expect(result.unscheduledTasks.map((task) => task.id), [
          'task-later',
          'task-no-due',
        ]);
      },
    );

    test('scheduled tasks are never listed as unscheduled', () async {
      final taskRepository = InMemoryTaskRepository();
      await taskRepository.insert(
        Task(
          id: 'task-scheduled',
          title: 'Scheduled elsewhere',
          estimatedMinutes: 10,
          scheduledRange: TimeRange(
            start: DateTime(2026, 10, 9, 8),
            end: DateTime(2026, 10, 9, 9),
          ),
        ),
      );

      final service = DayScheduleService(
        taskRepository: taskRepository,
        eventRepository: InMemoryEventRepository(),
        courseOccurrencesForDate: (_) async => const [],
      );

      final result = await service.loadDay(DateTime(2026, 10, 5));
      expect(result.items, isEmpty);
      expect(result.unscheduledTasks, isEmpty);
    });

    test('completed scheduled tasks remain in the day list', () async {
      final taskRepository = InMemoryTaskRepository();
      await taskRepository.insert(
        Task(
          id: 'task-done',
          title: 'Done',
          estimatedMinutes: 30,
          isCompleted: true,
          scheduledRange: TimeRange(
            start: DateTime(2026, 10, 5, 14),
            end: DateTime(2026, 10, 5, 14, 30),
          ),
        ),
      );
      final service = DayScheduleService(
        taskRepository: taskRepository,
        eventRepository: InMemoryEventRepository(),
        courseOccurrencesForDate: (_) async => const [],
      );

      final result = await service.loadDay(DateTime(2026, 10, 5));
      expect(result.items, hasLength(1));
      expect(result.isCompletedTask(result.items.single), isTrue);
      expect(result.unscheduledTasks, isEmpty);
    });

    test('DaySchedule copies expose immutable collections', () {
      final schedule = DaySchedule(
        date: DateTime(2026, 10, 5, 13),
        items: const [],
        unscheduledTasks: const [],
        completedTaskIds: const {'task-1'},
      );

      expect(schedule.date, DateTime(2026, 10, 5));
      expect(
        () => schedule.items.add(
          ScheduleItem(
            id: 'i',
            sourceId: 's',
            sourceType: ScheduleSourceType.task,
            title: 't',
            range: TimeRange(
              start: DateTime(2026, 10, 5, 8),
              end: DateTime(2026, 10, 5, 9),
            ),
          ),
        ),
        throwsUnsupportedError,
      );
      expect(() => schedule.completedTaskIds.add('x'), throwsUnsupportedError);
    });
  });
}
