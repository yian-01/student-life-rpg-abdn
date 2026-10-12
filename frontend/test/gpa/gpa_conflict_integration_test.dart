import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/academic/models/course_slot.dart';
import 'package:student_life_rpg/features/academic/models/semester.dart';
import 'package:student_life_rpg/features/academic/services/course_occurrence_service.dart';
import 'package:student_life_rpg/features/schedule/services/conflict_detector.dart';
import 'package:student_life_rpg/features/schedule/services/day_schedule_service.dart';
import 'package:student_life_rpg/features/schedule/models/event.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_event_repository.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_task_repository.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';

void main() {
  test(
    'G course expansion and I day loading feed K with real shared types',
    () async {
      final day = DateTime(2026, 10, 12);
      final semester = Semester(
        id: 's',
        name: 'Synthetic',
        startDate: day,
        endDate: DateTime(2026, 12, 31),
        week1Monday: day,
      );
      final course = Course(
        id: 'math',
        semesterId: 's',
        name: 'Synthetic math',
        credits: 3,
        gradePoint: 4,
        scoreScaleMax: 4,
        slots: [
          CourseSlot(weekday: 1, startMinute: 540, endMinute: 600, weeks: [1]),
        ],
      );
      final events = InMemoryEventRepository();
      await events.insert(
        Event(
          id: 'meeting',
          title: 'Synthetic meeting',
          range: TimeRange(
            start: DateTime(2026, 10, 12, 9, 30),
            end: DateTime(2026, 10, 12, 10, 30),
          ),
        ),
      );
      final service = DayScheduleService(
        taskRepository: InMemoryTaskRepository(),
        eventRepository: events,
        courseOccurrencesForDate: (date) async =>
            occurrencesForDate(course, semester, date),
      );
      final schedule = await service.loadDay(day);
      final pair = findConflicts(schedule.items).single;
      expect(pair.firstId, 'course:math:0:20261012');
      expect(pair.overlapRange.start, DateTime(2026, 10, 12, 9, 30));
      expect(pair.overlapRange.end, DateTime(2026, 10, 12, 10));
    },
  );
}
