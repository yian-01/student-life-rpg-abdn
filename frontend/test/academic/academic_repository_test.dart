import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/academic/models/semester.dart';
import 'package:student_life_rpg/features/academic/repositories/course_repository.dart';
import 'package:student_life_rpg/features/academic/repositories/semester_repository.dart';

Semester _semester(String id) => Semester(
  id: id,
  name: 'Fall',
  startDate: DateTime(2026, 9, 28),
  endDate: DateTime(2027, 1, 24),
  week1Monday: DateTime(2026, 9, 28),
);

Course _course(String id, String semesterId) => Course(
  id: id,
  semesterId: semesterId,
  name: 'Math',
  credits: 3,
  scoreScaleMax: 4.0,
  slots: const [],
);

/// 按组合根接线方式构造一对互相引用的仓库。
({InMemorySemesterRepository semesters, InMemoryCourseRepository courses})
_pair() {
  late final InMemorySemesterRepository semesters;
  final courses = InMemoryCourseRepository(
    semesterExists: (id) => semesters.exists(id),
  );
  semesters = InMemorySemesterRepository(
    isReferenced: courses.hasCoursesForSemester,
  );
  return (semesters: semesters, courses: courses);
}

void main() {
  group('InMemorySemesterRepository', () {
    test('insert/getById/list 基本行为', () async {
      final repo = InMemorySemesterRepository(isReferenced: (_) async => false);
      await repo.insert(_semester('s1'));

      expect((await repo.getById('s1'))?.id, 's1');
      expect(await repo.getById('missing'), isNull);
      expect(await repo.list(), hasLength(1));
    });

    test('list 返回不可变副本，外部修改不影响仓库', () async {
      final repo = InMemorySemesterRepository(isReferenced: (_) async => false);
      await repo.insert(_semester('s1'));

      final first = await repo.list();
      expect(() => first.add(_semester('s2')), throwsUnsupportedError);
      expect(await repo.list(), hasLength(1));
    });

    test('重复 insert 抛 StateError，未知 update 抛 StateError', () async {
      final repo = InMemorySemesterRepository(isReferenced: (_) async => false);
      await repo.insert(_semester('s1'));

      expect(() => repo.insert(_semester('s1')), throwsStateError);
      expect(() => repo.update(_semester('s2')), throwsStateError);
    });

    test('update 同 ID 覆盖且不改变 ID', () async {
      final repo = InMemorySemesterRepository(isReferenced: (_) async => false);
      await repo.insert(_semester('s1'));

      final renamed = Semester(
        id: 's1',
        name: 'Spring',
        startDate: DateTime(2026, 9, 28),
        endDate: DateTime(2027, 1, 24),
        week1Monday: DateTime(2026, 9, 28),
      );
      await repo.update(renamed);
      expect((await repo.getById('s1'))?.name, 'Spring');
      expect(await repo.list(), hasLength(1));
    });

    test('remove 未知 ID 返回 false，已知返回 true', () async {
      final repo = InMemorySemesterRepository(isReferenced: (_) async => false);
      await repo.insert(_semester('s1'));

      expect(await repo.remove('missing'), isFalse);
      expect(await repo.remove('s1'), isTrue);
      expect(await repo.list(), isEmpty);
    });

    test('空白 ID 抛 ArgumentError，且 ID 保留原值', () async {
      final repo = InMemorySemesterRepository(isReferenced: (_) async => false);
      for (final blank in ['', '   ', '\t\n']) {
        expect(() => repo.getById(blank), throwsArgumentError);
        expect(() => repo.insert(_semester(blank)), throwsArgumentError);
        expect(() => repo.remove(blank), throwsArgumentError);
      }

      await repo.insert(_semester(' s1 '));
      expect((await repo.getById(' s1 '))?.id, ' s1 ');
    });
  });

  group('InMemoryCourseRepository', () {
    test('insert 要求学期存在', () async {
      final semesters = InMemorySemesterRepository(
        isReferenced: (_) async => false,
      );
      final courses = InMemoryCourseRepository(
        semesterExists: semesters.exists,
      );

      expect(() => courses.insert(_course('c1', 's1')), throwsStateError);

      await semesters.insert(_semester('s1'));
      await courses.insert(_course('c1', 's1'));
      expect(await courses.list(), hasLength(1));
    });

    test('update 不得改到不存在的学期', () async {
      final semesters = InMemorySemesterRepository(
        isReferenced: (_) async => false,
      );
      final courses = InMemoryCourseRepository(
        semesterExists: semesters.exists,
      );
      await semesters.insert(_semester('s1'));
      await courses.insert(_course('c1', 's1'));

      expect(() => courses.update(_course('c1', 's2')), throwsStateError);
      expect((await courses.getById('c1'))?.semesterId, 's1');
    });

    test('重复 insert 与未知 update 抛 StateError', () async {
      final courses = InMemoryCourseRepository(
        semesterExists: (_) async => true,
      );
      await courses.insert(_course('c1', 's1'));

      expect(() => courses.insert(_course('c1', 's1')), throwsStateError);
      expect(() => courses.update(_course('c2', 's1')), throwsStateError);
    });

    test('listForSemester 按学期筛选', () async {
      final courses = InMemoryCourseRepository(
        semesterExists: (_) async => true,
      );
      await courses.insert(_course('c1', 's1'));
      await courses.insert(_course('c2', 's1'));
      await courses.insert(_course('c3', 's2'));

      final s1 = await courses.listForSemester('s1');
      expect(s1.map((course) => course.id), ['c1', 'c2']);
      expect(() => s1.add(_course('c4', 's1')), throwsUnsupportedError);
    });

    test('remove 未知返回 false', () async {
      final courses = InMemoryCourseRepository(
        semesterExists: (_) async => true,
      );
      await courses.insert(_course('c1', 's1'));

      expect(await courses.remove('missing'), isFalse);
      expect(await courses.remove('c1'), isTrue);
    });
  });

  group('引用保护', () {
    test('有课程引用时禁止删除学期', () async {
      final pair = _pair();
      await pair.semesters.insert(_semester('s1'));
      await pair.courses.insert(_course('c1', 's1'));

      expect(() => pair.semesters.remove('s1'), throwsStateError);
      expect(await pair.semesters.list(), hasLength(1));
    });

    test('课程删除后学期可以删除', () async {
      final pair = _pair();
      await pair.semesters.insert(_semester('s1'));
      await pair.courses.insert(_course('c1', 's1'));

      await pair.courses.remove('c1');
      expect(await pair.semesters.remove('s1'), isTrue);
      expect(await pair.semesters.list(), isEmpty);
    });

    test('其他学期的课程不阻止本学期删除', () async {
      final pair = _pair();
      await pair.semesters.insert(_semester('s1'));
      await pair.semesters.insert(_semester('s2'));
      await pair.courses.insert(_course('c1', 's2'));

      // s2 有课程引用，删除被拒绝。
      await expectLater(pair.semesters.remove('s2'), throwsStateError);
      // s1 没有课程引用，可以删除；这次删除不应影响 s2。
      expect(await pair.semesters.remove('s1'), isTrue);
      expect((await pair.semesters.list()).map((s) => s.id), ['s2']);
      // s2 依然受引用保护。
      await expectLater(pair.semesters.remove('s2'), throwsStateError);
    });
  });
}
