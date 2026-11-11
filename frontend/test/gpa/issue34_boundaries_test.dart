import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/academic/models/course_slot.dart';
import 'package:student_life_rpg/features/academic/models/exam.dart';
import 'package:student_life_rpg/features/academic/models/semester.dart';
import 'package:student_life_rpg/features/academic/services/semester_week_guard.dart';
import 'package:student_life_rpg/features/schedule/services/conflict_detector.dart';
import 'package:student_life_rpg/features/schedule/services/task_schedule_adapter.dart';
import 'package:student_life_rpg/shared/models/schedule_item.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';

void main() {
  test(
    'A13 independent guard checks anchor, shortening and reassigned semester',
    () {
      Semester semester(DateTime end) => Semester(
        id: 's',
        name: 'five',
        startDate: DateTime(2026, 11, 4),
        endDate: end,
        week1Monday: DateTime(2026, 11, 2),
      );
      final course = Course(
        id: 'c',
        semesterId: 's',
        name: 'boundary',
        credits: 2,
        slots: [
          CourseSlot(weekday: 1, startMinute: 510, endMinute: 550, weeks: [5]),
        ],
        scoreScaleMax: 4,
      );
      expect(semester(DateTime(2026, 12, 6)).lastValidWeek, 5);
      expect(
        coursesOutsideSemesterWeeks(semester(DateTime(2026, 12, 6)), [course]),
        isEmpty,
      );
      expect(
        coursesOutsideSemesterWeeks(semester(DateTime(2026, 11, 29)), [course]),
        ['boundary'],
      );
      final bad = Course(
        id: 'b',
        semesterId: 's',
        name: '999',
        credits: 2,
        slots: [
          CourseSlot(
            weekday: 1,
            startMinute: 510,
            endMinute: 550,
            weeks: [999],
          ),
        ],
        scoreScaleMax: 4,
      );
      expect(
        coursesOutsideSemesterWeeks(semester(DateTime(2026, 12, 6)), [bad]),
        ['999'],
      );
      expect(course.slots.single.weeks, [5]);
    },
  );
  test(
    'real Exam ranges mix with all shared source types at cross-day boundary',
    () {
      final exam = Exam(
        id: 'same',
        courseId: 'c',
        title: '同名',
        range: TimeRange(
          start: DateTime(2026, 11, 6, 23, 30),
          end: DateTime(2026, 11, 7, 0, 30),
        ),
      );
      final examItem = const TaskScheduleAdapter().examToScheduleItem(exam);
      expect(examItem.sourceType, ScheduleSourceType.exam);
      for (final type in ScheduleSourceType.values) {
        final sourceId = type == ScheduleSourceType.exam
            ? 'other-exam'
            : 'same';
        ScheduleItem item(DateTime start, DateTime end) => ScheduleItem(
          id: TaskScheduleAdapter.buildItemId(type, sourceId, start),
          sourceId: sourceId,
          sourceType: type,
          title: '同名',
          range: TimeRange(start: start, end: end),
        );
        final partial = item(DateTime(2026, 11, 7), DateTime(2026, 11, 7, 1));
        final pairs = findConflicts([examItem, partial]);
        expect(pairs.single.overlapRange.start, DateTime(2026, 11, 7));
        expect(pairs.single.overlapRange.end, DateTime(2026, 11, 7, 0, 30));
        expect(
          findConflicts([
            examItem,
            item(exam.range.end, DateTime(2026, 11, 7, 1)),
          ]),
          isEmpty,
        );
      }
    },
  );
}
