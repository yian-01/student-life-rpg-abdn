import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/academic/models/assignment.dart';
import 'package:student_life_rpg/features/academic/models/exam.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';

void main() {
  group('Assignment', () {
    test('接受合法作业并保留微秒精度', () {
      final dueAt = DateTime(2026, 10, 20, 23, 59, 59, 123, 456);
      final assignment = Assignment(
        id: 'a1',
        courseId: 'c1',
        title: '第一章习题',
        dueAt: dueAt,
      );
      expect(assignment.dueAt, dueAt);
      expect(assignment.description, isNull);
    });

    test('空白 ID/courseId/title 与 UTC 时间抛 ArgumentError', () {
      final dueAt = DateTime(2026, 10, 20, 12);
      for (final blank in ['', '   ', '\t\n']) {
        expect(
          () => Assignment(id: blank, courseId: 'c1', title: 't', dueAt: dueAt),
          throwsArgumentError,
        );
        expect(
          () => Assignment(id: 'a1', courseId: blank, title: 't', dueAt: dueAt),
          throwsArgumentError,
        );
        expect(
          () =>
              Assignment(id: 'a1', courseId: 'c1', title: blank, dueAt: dueAt),
          throwsArgumentError,
        );
      }
      expect(
        () => Assignment(
          id: 'a1',
          courseId: 'c1',
          title: 't',
          dueAt: dueAt.toUtc(),
        ),
        throwsArgumentError,
      );
    });

    test('JSON 往返保留时间与微秒，可空字段写出 null', () {
      final assignment = Assignment(
        id: 'a1',
        courseId: 'c1',
        title: '第一章习题',
        dueAt: DateTime(2026, 10, 20, 23, 59, 59, 123, 456),
        description: null,
      );
      final json = assignment.toJson();
      expect(json['description'], isNull);
      expect(json['dueAt'], '2026-10-20T23:59:59.123456');

      final restored = Assignment.fromJson(json);
      expect(restored.dueAt, assignment.dueAt);
      expect(restored.dueAt.microsecond, 456);
      expect(restored.description, isNull);
    });

    test('JSON 缺 description 按 null 处理', () {
      final json = Assignment(
        id: 'a1',
        courseId: 'c1',
        title: 't',
        dueAt: DateTime(2026, 10, 20, 12),
      ).toJson()..remove('description');
      expect(Assignment.fromJson(json).description, isNull);
    });

    test('JSON 拒绝未知键、缺失字段与非法时间', () {
      final base = Assignment(
        id: 'a1',
        courseId: 'c1',
        title: 't',
        dueAt: DateTime(2026, 10, 20, 12),
      ).toJson();

      expect(
        () => Assignment.fromJson({...base, 'extra': 1}),
        throwsFormatException,
      );
      expect(
        () => Assignment.fromJson({...base}..remove('dueAt')),
        throwsFormatException,
      );
      expect(
        () => Assignment.fromJson({...base, 'id': 1}),
        throwsFormatException,
      );
      for (final invalid in [
        '2026-02-29T08:00:00',
        '2026-10-32T08:00:00',
        '2026-10-20T24:00:00',
        '2026-10-20T08:60:00',
        '2026-10-20T08:00:60',
        '2026-10-20T08:00:00Z',
        '2026-10-20T08:00:00+08:00',
        '2026-10-20',
        null,
        123,
      ]) {
        expect(
          () => Assignment.fromJson({...base, 'dueAt': invalid}),
          throwsFormatException,
          reason: '$invalid',
        );
      }
    });
  });

  group('Exam', () {
    TimeRange sampleRange() => TimeRange(
      start: DateTime(2026, 11, 10, 9),
      end: DateTime(2026, 11, 10, 11),
    );

    test('接受合法考试', () {
      final exam = Exam(
        id: 'e1',
        courseId: 'c1',
        title: '期中考试',
        range: sampleRange(),
        location: 'A101',
      );
      expect(exam.range.start, DateTime(2026, 11, 10, 9));
      expect(exam.location, 'A101');
    });

    test('空白 ID/courseId/title 抛 ArgumentError', () {
      for (final blank in ['', '   ']) {
        expect(
          () =>
              Exam(id: blank, courseId: 'c1', title: 't', range: sampleRange()),
          throwsArgumentError,
        );
        expect(
          () =>
              Exam(id: 'e1', courseId: blank, title: 't', range: sampleRange()),
          throwsArgumentError,
        );
        expect(
          () => Exam(
            id: 'e1',
            courseId: 'c1',
            title: blank,
            range: sampleRange(),
          ),
          throwsArgumentError,
        );
      }
    });

    test('JSON 往返保留 range 与可空 location', () {
      final exam = Exam(
        id: 'e1',
        courseId: 'c1',
        title: '期中考试',
        range: sampleRange(),
        location: null,
      );
      final json = exam.toJson();
      expect(json['location'], isNull);

      final restored = Exam.fromJson(json);
      expect(restored.range.start, DateTime(2026, 11, 10, 9));
      expect(restored.range.end, DateTime(2026, 11, 10, 11));
      expect(restored.location, isNull);
    });

    test('JSON 缺 location 按 null 处理', () {
      final json = Exam(
        id: 'e1',
        courseId: 'c1',
        title: 't',
        range: sampleRange(),
      ).toJson()..remove('location');
      expect(Exam.fromJson(json).location, isNull);
    });

    test('JSON 拒绝未知键、嵌套未知键与非法 range', () {
      final base = Exam(
        id: 'e1',
        courseId: 'c1',
        title: 't',
        range: sampleRange(),
      ).toJson();

      expect(() => Exam.fromJson({...base, 'extra': 1}), throwsFormatException);
      expect(
        () => Exam.fromJson({...base}..remove('range')),
        throwsFormatException,
      );
      expect(
        () => Exam.fromJson({...base, 'range': 'not-an-object'}),
        throwsFormatException,
      );
      expect(
        () => Exam.fromJson({
          ...base,
          'range': {
            'start': '2026-11-10T11:00:00',
            'end': '2026-11-10T09:00:00',
          },
        }),
        throwsFormatException,
      );
      expect(
        () => Exam.fromJson({
          ...base,
          'range': {
            'start': '2026-11-10T09:00:00',
            'end': '2026-11-10T11:00:00',
            'extra': true,
          },
        }),
        throwsFormatException,
      );
    });
  });
}
