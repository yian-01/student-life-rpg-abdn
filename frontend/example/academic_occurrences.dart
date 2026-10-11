import 'dart:io';

import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/academic/repositories/course_repository.dart';
import 'package:student_life_rpg/features/academic/repositories/semester_repository.dart';
import 'package:student_life_rpg/features/academic/services/course_occurrence_service.dart';
import 'package:student_life_rpg/shared/models/schedule_item.dart';

import 'academic_synthetic_data.dart';

/// Run from frontend: dart run example/academic_occurrences.dart
/// Synthetic data; 4.0 is a demo scale, not an official university policy.
Future<void> main() async {
  late final InMemoryCourseRepository courses;
  final semesters = InMemorySemesterRepository(
    isReferenced: (id) => courses.hasCoursesForSemester(id),
  );
  courses = InMemoryCourseRepository(semesterExists: semesters.exists);
  final semester = syntheticSemester();
  await semesters.insert(semester);
  await courses.insert(syntheticMathCourse());
  await courses.insert(syntheticEnglishCourse());

  // A/I can pass this closure as CourseOccurrencesForDate. No substitute types.
  Future<List<ScheduleItem>> loadCourseOccurrences(DateTime date) async {
    final items = <ScheduleItem>[];
    for (final course in await courses.list()) {
      final semester = await semesters.getById(course.semesterId);
      if (semester == null) {
        throw StateError('Missing semester ${course.semesterId}');
      }
      items.addAll(occurrencesForDate(course, semester, date));
    }
    return List<ScheduleItem>.unmodifiable(items);
  }

  stdout.writeln('Synthetic data; demo scoreScaleMax=4.0; memory only.');
  for (final (day, expected) in [(5, 1), (12, 0), (19, 1), (7, 1), (14, 1)]) {
    final items = await loadCourseOccurrences(DateTime(2026, 10, day));
    if (items.length != expected) {
      throw StateError('Unexpected occurrences on October $day');
    }
    stdout.writeln(
      '2026-10-${day.toString().padLeft(2, '0')}: ${items.length}',
    );
    for (final item in items) {
      stdout.writeln('  ${item.id} ${item.range.start} -> ${item.range.end}');
    }
  }

  // J consumes these exact Course entities after filtering by semester.
  final List<Course> gpaInput = await courses.listForSemester(semester.id);
  stdout.writeln(
    'J input: ${gpaInput.map((c) => '${c.id}:${c.gradePoint}').join(', ')}',
  );
  stdout.writeln(
    'Verified repository -> model -> occurrence callback; I/J services await integration.',
  );
}
