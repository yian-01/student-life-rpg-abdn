import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/schedule/models/event.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/services/task_schedule_adapter.dart';
import 'package:student_life_rpg/shared/models/schedule_item.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';

void main() {
  const adapter = TaskScheduleAdapter();

  test('Event maps to a stable ScheduleItem', () {
    final event = Event(
      id: 'event-1',
      title: 'Event',
      range: TimeRange(
        start: DateTime(2026, 10, 5, 9),
        end: DateTime(2026, 10, 5, 10),
      ),
    );

    final item = adapter.eventToScheduleItem(event);
    expect(item.id, contains('event:event-1:20261005:090000'));
    expect(item.sourceId, event.id);
    expect(item.sourceType, ScheduleSourceType.event);
    expect(item.range, same(event.range));
  });

  test('scheduled Task maps and unscheduled Task returns null', () {
    final range = TimeRange(
      start: DateTime(2026, 10, 5, 20),
      end: DateTime(2026, 10, 5, 21),
    );
    final scheduled = Task(
      id: 'task-1',
      title: 'Task',
      estimatedMinutes: 60,
      isCompleted: true,
      scheduledRange: range,
    );
    final unscheduled = Task(
      id: 'task-2',
      title: 'Later',
      estimatedMinutes: 10,
    );

    final item = adapter.taskToScheduleItem(scheduled);
    expect(item, isNotNull);
    expect(item!.sourceType, ScheduleSourceType.task);
    expect(item.sourceId, scheduled.id);
    expect(adapter.taskToScheduleItem(unscheduled), isNull);
  });

  test('different dates produce different ScheduleItem ids', () {
    final first = Task(
      id: 'task-1',
      title: 'Task',
      estimatedMinutes: 20,
      scheduledRange: TimeRange(
        start: DateTime(2026, 10, 5, 20),
        end: DateTime(2026, 10, 5, 20, 20),
      ),
    );
    final second = Task(
      id: 'task-1',
      title: 'Task',
      estimatedMinutes: 20,
      scheduledRange: TimeRange(
        start: DateTime(2026, 10, 6, 20),
        end: DateTime(2026, 10, 6, 20, 20),
      ),
    );

    expect(
      adapter.taskToScheduleItem(first)!.id,
      isNot(adapter.taskToScheduleItem(second)!.id),
    );
  });

  test('same second with different microsecond starts produces unique ids', () {
    final first = Task(
      id: 'task-1',
      title: 'Task',
      estimatedMinutes: 20,
      scheduledRange: TimeRange(
        start: DateTime(2026, 10, 5, 20, 0, 0, 0, 1),
        end: DateTime(2026, 10, 5, 20, 20),
      ),
    );
    final second = Task(
      id: 'task-1',
      title: 'Task',
      estimatedMinutes: 20,
      scheduledRange: TimeRange(
        start: DateTime(2026, 10, 5, 20, 0, 0, 0, 2),
        end: DateTime(2026, 10, 5, 20, 20),
      ),
    );

    final firstItem = adapter.taskToScheduleItem(first)!;
    final secondItem = adapter.taskToScheduleItem(second)!;
    expect(firstItem.id, isNot(secondItem.id));
    expect(firstItem.id, contains('200000000001'));
    expect(secondItem.id, contains('200000000002'));
  });

  test('millisecond and microsecond parts are combined into six digits', () {
    final item = adapter.taskToScheduleItem(
      Task(
        id: 'task-1',
        title: 'Task',
        estimatedMinutes: 20,
        scheduledRange: TimeRange(
          start: DateTime(2026, 10, 5, 8, 5, 6, 7, 8),
          end: DateTime(2026, 10, 5, 9),
        ),
      ),
    )!;

    expect(item.id, contains(':20261005:080506007008'));
  });

  test('encoded source id keeps separators out of the derived id', () {
    final item = adapter.eventToScheduleItem(
      Event(
        id: 'event:with/slash',
        title: 'Event',
        range: TimeRange(
          start: DateTime(2026, 10, 5, 9),
          end: DateTime(2026, 10, 5, 10),
        ),
      ),
    );

    expect(item.sourceId, 'event:with/slash');
    expect(item.id, contains(Uri.encodeComponent('event:with/slash')));
  });
}
