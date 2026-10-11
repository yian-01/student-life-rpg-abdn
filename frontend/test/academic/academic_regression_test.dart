import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/academic/models/course_slot.dart';
import 'package:student_life_rpg/features/academic/models/semester.dart';
import 'package:student_life_rpg/features/academic/repositories/course_repository.dart';
import 'package:student_life_rpg/features/academic/repositories/semester_repository.dart';
import 'package:student_life_rpg/features/academic/services/course_occurrence_service.dart';

import 'fixtures.dart';

void main() {
  test(
    'real repository pair enforces references and immutable snapshots',
    () async {
      late final InMemoryCourseRepository courses;
      final semesters = InMemorySemesterRepository(
        isReferenced: (id) => courses.hasCoursesForSemester(id),
      );
      courses = InMemoryCourseRepository(semesterExists: semesters.exists);
      final math = syntheticMathCourse();
      await expectLater(courses.insert(math), throwsStateError);
      await semesters.insert(syntheticSemester());
      await courses.insert(math);
      final snapshot = await courses.list();
      await expectLater(semesters.remove(math.semesterId), throwsStateError);
      await courses.remove(math.id);
      expect(snapshot.single, same(math));
      expect(() => snapshot.clear(), throwsUnsupportedError);
      expect(await semesters.remove(math.semesterId), isTrue);
    },
  );

  test('concurrent duplicate insert preserves first record', () async {
    final gate = Completer<bool>();
    final courses = InMemoryCourseRepository(
      semesterExists: (_) => gate.future,
    );
    final first = courses.insert(syntheticMathCourse());
    final second = courses.insert(syntheticMathCourse());
    final rejection = expectLater(second, throwsStateError);
    gate.complete(true);
    await first;
    await rejection;
    expect(await courses.list(), hasLength(1));
  });

  test('reference lookup failures propagate without saving a course', () async {
    final failure = StateError('lookup failed');
    final courses = InMemoryCourseRepository(
      semesterExists: (_) async => throw failure,
    );
    await expectLater(
      courses.insert(syntheticMathCourse()),
      throwsA(same(failure)),
    );
    expect(await courses.list(), isEmpty);
  });

  test('Course wire JSON uses caller scale without storing it as a field', () {
    final course = Course(
      id: 'five-scale',
      semesterId: 's',
      name: 'Synthetic',
      credits: 1,
      gradePoint: 4.5,
      slots: [],
      scoreScaleMax: 5,
    );
    final wire =
        jsonDecode(jsonEncode(course.toJson())) as Map<String, dynamic>;
    expect(wire.containsKey('scoreScaleMax'), isFalse);
    expect(Course.fromJson(wire, scoreScaleMax: 5).gradePoint, 4.5);
    expect(
      () => Course.fromJson(wire, scoreScaleMax: 4),
      throwsFormatException,
    );
  });

  test('UTC date queries are rejected rather than reinterpreted', () {
    final semester = syntheticSemester();
    expect(
      () => occurrencesForDate(
        syntheticMathCourse(),
        semester,
        DateTime.utc(2026, 10, 5),
      ),
      throwsArgumentError,
    );
    expect(
      () => semester.containsDate(DateTime.utc(2026, 10, 5)),
      throwsArgumentError,
    );
  });

  test(
    'semester end is inclusive and pre-anchor dates have no positive week',
    () {
      final semester = Semester(
        id: 's',
        name: 'Synthetic',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 5),
        week1Monday: DateTime(2026, 10, 5),
      );
      final course = Course(
        id: 'c',
        semesterId: 's',
        name: 'Synthetic',
        credits: 1,
        scoreScaleMax: 4,
        slots: [
          CourseSlot(weekday: 1, startMinute: 0, endMinute: 1440, weeks: [1]),
          CourseSlot(weekday: 4, startMinute: 0, endMinute: 60, weeks: [1]),
        ],
      );
      expect(
        occurrencesForDate(course, semester, DateTime(2026, 10, 1)),
        isEmpty,
      );
      final item = occurrencesForDate(
        course,
        semester,
        DateTime(2026, 10, 5),
      ).single;
      expect(item.range.end, DateTime(2026, 10, 6));
    },
  );

  test('calendar weeks span leap day, month and year boundaries', () {
    for (final anchor in [
      DateTime(2024, 2, 26),
      DateTime(2026, 12, 28),
      DateTime(2026, 3, 2),
      DateTime(2026, 10, 26),
    ]) {
      final end = DateTime(anchor.year, anchor.month, anchor.day + 21);
      final semester = Semester(
        id: 's',
        name: 'Synthetic',
        startDate: anchor,
        endDate: end,
        week1Monday: anchor,
      );
      final course = Course(
        id: 'c',
        semesterId: 's',
        name: 'Synthetic',
        credits: 1,
        scoreScaleMax: 4,
        slots: [
          CourseSlot(weekday: 1, startMinute: 0, endMinute: 1440, weeks: [2]),
        ],
      );
      final monday = DateTime(anchor.year, anchor.month, anchor.day + 7);
      final item = occurrencesForDate(course, semester, monday).single;
      expect(item.range.start, monday);
      expect(
        item.range.end,
        DateTime(monday.year, monday.month, monday.day + 1),
      );
      expect(
        occurrencesForDate(
          course,
          semester,
          DateTime(anchor.year, anchor.month, anchor.day + 14),
        ),
        isEmpty,
      );
    }
  });

  test(
    'date-only model rejects years that cannot round trip as YYYY-MM-DD',
    () {
      expect(
        () => Semester(
          id: 's',
          name: 'Synthetic',
          startDate: DateTime(10000),
          endDate: DateTime(10000, 2),
          week1Monday: DateTime(2026, 10, 5),
        ),
        throwsArgumentError,
      );
    },
  );
}
