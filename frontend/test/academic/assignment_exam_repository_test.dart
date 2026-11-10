import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/academic/models/assignment.dart';
import 'package:student_life_rpg/features/academic/models/exam.dart';
import 'package:student_life_rpg/features/academic/repositories/assignment_repository.dart';
import 'package:student_life_rpg/features/academic/repositories/exam_repository.dart';
import 'package:student_life_rpg/features/academic/services/course_reference_guard.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';

Assignment _assignment(String id, String courseId, DateTime dueAt) =>
    Assignment(id: id, courseId: courseId, title: '作业 $id', dueAt: dueAt);

Exam _exam(String id, String courseId, DateTime start, DateTime end) => Exam(
  id: id,
  courseId: courseId,
  title: '考试 $id',
  range: TimeRange(start: start, end: end),
);

void main() {
  group('InMemoryAssignmentRepository', () {
    test('基本增删改查与 StateError 语义', () async {
      final repo = InMemoryAssignmentRepository();
      await repo.insert(_assignment('a1', 'c1', DateTime(2026, 11, 10, 18)));

      expect((await repo.getById('a1'))?.id, 'a1');
      expect(await repo.getById('missing'), isNull);
      expect(
        () => repo.insert(_assignment('a1', 'c1', DateTime(2026, 11, 11))),
        throwsStateError,
      );
      expect(
        () => repo.update(_assignment('a2', 'c1', DateTime(2026, 11, 12))),
        throwsStateError,
      );
      expect(await repo.remove('missing'), isFalse);
      expect(await repo.remove('a1'), isTrue);
      expect(await repo.list(), isEmpty);
    });

    test('listForCourse 只返回该课程并按截止时间升序', () async {
      final repo = InMemoryAssignmentRepository();
      await repo.insert(_assignment('a1', 'c1', DateTime(2026, 11, 20)));
      await repo.insert(_assignment('a2', 'c1', DateTime(2026, 11, 10)));
      await repo.insert(_assignment('a3', 'c2', DateTime(2026, 11, 15)));

      final rows = await repo.listForCourse('c1');
      expect(rows.map((row) => row.id), ['a2', 'a1']);
      expect(
        () => rows.add(_assignment('a9', 'c1', DateTime(2026, 12, 1))),
        throwsUnsupportedError,
      );
    });

    test('空白 ID 抛 ArgumentError，list 不可修改', () async {
      final repo = InMemoryAssignmentRepository();
      for (final blank in ['', '   ']) {
        expect(() => repo.getById(blank), throwsArgumentError);
        expect(() => repo.remove(blank), throwsArgumentError);
        expect(() => repo.listForCourse(blank), throwsArgumentError);
      }
      await repo.insert(_assignment('a1', 'c1', DateTime(2026, 11, 10)));
      final rows = await repo.list();
      expect(() => rows.clear(), throwsUnsupportedError);
    });
  });

  group('InMemoryExamRepository', () {
    test('listForCourse 只返回该课程并按开始时间升序', () async {
      final repo = InMemoryExamRepository();
      await repo.insert(
        _exam('e1', 'c1', DateTime(2026, 12, 1, 9), DateTime(2026, 12, 1, 11)),
      );
      await repo.insert(
        _exam(
          'e2',
          'c1',
          DateTime(2026, 11, 20, 9),
          DateTime(2026, 11, 20, 11),
        ),
      );
      await repo.insert(
        _exam(
          'e3',
          'c2',
          DateTime(2026, 11, 25, 9),
          DateTime(2026, 11, 25, 11),
        ),
      );

      expect((await repo.listForCourse('c1')).map((row) => row.id), [
        'e2',
        'e1',
      ]);
      expect(await repo.list(), hasLength(3));
    });

    test('重复 insert 与未知 update 抛 StateError', () async {
      final repo = InMemoryExamRepository();
      final exam = _exam(
        'e1',
        'c1',
        DateTime(2026, 12, 1, 9),
        DateTime(2026, 12, 1, 11),
      );
      await repo.insert(exam);
      expect(() => repo.insert(exam), throwsStateError);
      expect(
        () => repo.update(
          _exam(
            'e2',
            'c1',
            DateTime(2026, 12, 2, 9),
            DateTime(2026, 12, 2, 11),
          ),
        ),
        throwsStateError,
      );
    });

    test('跨日的 23:30–次日 00:30 可保存', () async {
      final repo = InMemoryExamRepository();
      final exam = _exam(
        'e1',
        'c1',
        DateTime(2026, 11, 3, 23, 30),
        DateTime(2026, 11, 4, 0, 30),
      );
      await repo.insert(exam);
      final restored = await repo.getById('e1');
      expect(restored?.range.start, DateTime(2026, 11, 3, 23, 30));
      expect(restored?.range.end, DateTime(2026, 11, 4, 0, 30));
    });
  });

  group('ensureCourseDeletable：课程被引用时阻止删除', () {
    test('没有任何引用时放行', () async {
      final assignments = InMemoryAssignmentRepository();
      final exams = InMemoryExamRepository();
      await expectLater(
        ensureCourseDeletable(
          courseId: 'c1',
          courseName: '数据结构',
          assignments: assignments,
          exams: exams,
        ),
        completes,
      );
    });

    test('只有作业引用时，错误信息给出作业条数', () async {
      final assignments = InMemoryAssignmentRepository();
      final exams = InMemoryExamRepository();
      await assignments.insert(_assignment('a1', 'c1', DateTime(2026, 11, 10)));
      await assignments.insert(_assignment('a2', 'c1', DateTime(2026, 11, 11)));

      await expectLater(
        ensureCourseDeletable(
          courseId: 'c1',
          courseName: '数据结构',
          assignments: assignments,
          exams: exams,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            '课程「数据结构」仍有 2 条作业引用，请先删除相关记录。',
          ),
        ),
      );
    });

    test('作业与考试同时引用时两类数量都出现', () async {
      final assignments = InMemoryAssignmentRepository();
      final exams = InMemoryExamRepository();
      await assignments.insert(_assignment('a1', 'c1', DateTime(2026, 11, 10)));
      await exams.insert(
        _exam('e1', 'c1', DateTime(2026, 12, 1, 9), DateTime(2026, 12, 1, 11)),
      );

      await expectLater(
        ensureCourseDeletable(
          courseId: 'c1',
          courseName: '数据结构',
          assignments: assignments,
          exams: exams,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('1 条作业、1 场考试'),
          ),
        ),
      );
    });

    test('别的课程的引用不影响本课程，且校验不删除任何数据', () async {
      final assignments = InMemoryAssignmentRepository();
      final exams = InMemoryExamRepository();
      await assignments.insert(_assignment('a1', 'c2', DateTime(2026, 11, 10)));

      await expectLater(
        ensureCourseDeletable(
          courseId: 'c1',
          courseName: '数据结构',
          assignments: assignments,
          exams: exams,
        ),
        completes,
      );
      expect(await assignments.list(), hasLength(1));
    });
  });
}
