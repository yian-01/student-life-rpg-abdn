import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/schedule/composition/schedule_composition.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_event_repository.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_task_repository.dart';
import 'package:student_life_rpg/shared/models/schedule_item.dart';

void main() {
  test(
    'demo composition loads without mutating injected repositories',
    () async {
      final composition = ScheduleComposition.inMemoryDemo();
      final today = DateTime.now();
      final schedule = await composition.loadDay(today);

      expect(schedule.date, DateTime(today.year, today.month, today.day));
      expect(
        schedule.items.any(
          (item) => item.sourceType == ScheduleSourceType.event,
        ),
        isTrue,
      );
      expect(schedule.unscheduledTasks, isNotEmpty);
    },
  );

  test(
    'composition with injected repositories does not seed demo data',
    () async {
      final taskRepository = InMemoryTaskRepository();
      final eventRepository = InMemoryEventRepository();
      final composition = ScheduleComposition(
        taskRepository: taskRepository,
        eventRepository: eventRepository,
        courseOccurrencesForDate: (_) async => const <ScheduleItem>[],
      );

      final schedule = await composition.loadDay(DateTime(2026, 10, 5));

      expect(schedule.items, isEmpty);
      expect(schedule.unscheduledTasks, isEmpty);
      expect(await taskRepository.list(), isEmpty);
      expect(await eventRepository.list(), isEmpty);
    },
  );
}
