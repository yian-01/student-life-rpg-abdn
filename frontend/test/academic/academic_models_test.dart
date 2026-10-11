import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/academic/models/course_slot.dart';
import 'package:student_life_rpg/features/academic/models/semester.dart';

void main() {
  group('CourseSlot 校验', () {
    test('接受合法时间段，包含 0 与 1440 边界', () {
      expect(
        CourseSlot(
          weekday: 1,
          startMinute: 0,
          endMinute: 1,
          weeks: [1],
        ).startMinute,
        0,
      );
      expect(
        CourseSlot(
          weekday: 7,
          startMinute: 0,
          endMinute: 1440,
          weeks: [1],
        ).endMinute,
        1440,
      );
    });

    test('拒绝非法 weekday 与非法分钟范围', () {
      for (final weekday in [0, -1, 8, 100]) {
        expect(
          () => CourseSlot(
            weekday: weekday,
            startMinute: 0,
            endMinute: 60,
            weeks: [1],
          ),
          throwsArgumentError,
          reason: 'weekday=$weekday',
        );
      }
      expect(
        () =>
            CourseSlot(weekday: 1, startMinute: -1, endMinute: 60, weeks: [1]),
        throwsArgumentError,
      );
      expect(
        () =>
            CourseSlot(weekday: 1, startMinute: 0, endMinute: 1441, weeks: [1]),
        throwsArgumentError,
      );
      expect(
        () =>
            CourseSlot(weekday: 1, startMinute: 60, endMinute: 60, weeks: [1]),
        throwsArgumentError,
      );
      expect(
        () =>
            CourseSlot(weekday: 1, startMinute: 90, endMinute: 60, weeks: [1]),
        throwsArgumentError,
      );
    });

    test('拒绝空 weeks、非递增、重复与非正整数', () {
      expect(
        () => CourseSlot(weekday: 1, startMinute: 0, endMinute: 60, weeks: []),
        throwsArgumentError,
      );
      expect(
        () => CourseSlot(
          weekday: 1,
          startMinute: 0,
          endMinute: 60,
          weeks: [2, 1],
        ),
        throwsArgumentError,
      );
      expect(
        () => CourseSlot(
          weekday: 1,
          startMinute: 0,
          endMinute: 60,
          weeks: [1, 1],
        ),
        throwsArgumentError,
      );
      expect(
        () => CourseSlot(
          weekday: 1,
          startMinute: 0,
          endMinute: 60,
          weeks: [0, 1],
        ),
        throwsArgumentError,
      );
      expect(
        () => CourseSlot(
          weekday: 1,
          startMinute: 0,
          endMinute: 60,
          weeks: [1, -2],
        ),
        throwsArgumentError,
      );
    });

    test('weeks 构造时复制为不可变列表', () {
      final source = [1, 2, 3];
      final slot = CourseSlot(
        weekday: 1,
        startMinute: 0,
        endMinute: 60,
        weeks: source,
      );
      source.add(4);
      expect(slot.weeks, [1, 2, 3]);
      expect(() => slot.weeks.add(5), throwsUnsupportedError);
    });

    test('JSON 往返保留字段', () {
      final slot = CourseSlot(
        weekday: 3,
        startMinute: 600,
        endMinute: 690,
        weeks: [1, 2, 5],
      );
      final restored = CourseSlot.fromJson(slot.toJson());
      expect(restored.weekday, 3);
      expect(restored.startMinute, 600);
      expect(restored.endMinute, 690);
      expect(restored.weeks, [1, 2, 5]);
    });

    test('JSON 拒绝未知键与错误类型', () {
      final base = CourseSlot(
        weekday: 1,
        startMinute: 0,
        endMinute: 60,
        weeks: [1],
      ).toJson();

      expect(
        () => CourseSlot.fromJson({...base, 'extra': 1}),
        throwsFormatException,
      );
      expect(
        () => CourseSlot.fromJson({...base, 'weekday': '1'}),
        throwsFormatException,
      );
      expect(
        () => CourseSlot.fromJson({
          ...base,
          'weeks': ['1'],
        }),
        throwsFormatException,
      );
      expect(
        () => CourseSlot.fromJson({...base}..remove('weeks')),
        throwsFormatException,
      );
      expect(
        () => CourseSlot.fromJson({
          ...base,
          'weeks': [1, 1],
        }),
        throwsFormatException,
      );
    });
  });

  group('Semester 校验', () {
    test('接受合法学期并包含首尾日期', () {
      final semester = Semester(
        id: 's1',
        name: 'Fall',
        startDate: DateTime(2026, 9, 28),
        endDate: DateTime(2027, 1, 24),
        week1Monday: DateTime(2026, 9, 28),
      );
      expect(semester.containsDate(DateTime(2026, 9, 28)), isTrue);
      expect(semester.containsDate(DateTime(2027, 1, 24)), isTrue);
      expect(semester.containsDate(DateTime(2026, 9, 27)), isFalse);
      expect(semester.containsDate(DateTime(2027, 1, 25)), isFalse);
    });

    test('startDate 晚于 endDate 抛 ArgumentError', () {
      expect(
        () => Semester(
          id: 's1',
          name: 'Fall',
          startDate: DateTime(2026, 10, 1),
          endDate: DateTime(2026, 9, 1),
          week1Monday: DateTime(2026, 9, 28),
        ),
        throwsArgumentError,
      );
    });

    test('week1Monday 不是周一抛 ArgumentError', () {
      for (final day in [
        DateTime(2026, 9, 29),
        DateTime(2026, 9, 30),
        DateTime(2026, 10, 4),
      ]) {
        expect(
          () => Semester(
            id: 's1',
            name: 'Fall',
            startDate: DateTime(2026, 9, 1),
            endDate: DateTime(2027, 1, 24),
            week1Monday: day,
          ),
          throwsArgumentError,
          reason: '$day',
        );
      }
    });

    test('空白 id/name 与非本地午夜日期抛 ArgumentError', () {
      expect(
        () => Semester(
          id: '  ',
          name: 'Fall',
          startDate: DateTime(2026, 9, 28),
          endDate: DateTime(2027, 1, 24),
          week1Monday: DateTime(2026, 9, 28),
        ),
        throwsArgumentError,
      );
      expect(
        () => Semester(
          id: 's1',
          name: 'Fall',
          startDate: DateTime(2026, 9, 28, 8),
          endDate: DateTime(2027, 1, 24),
          week1Monday: DateTime(2026, 9, 28),
        ),
        throwsArgumentError,
      );
      expect(
        () => Semester(
          id: 's1',
          name: 'Fall',
          startDate: DateTime.utc(2026, 9, 28),
          endDate: DateTime(2027, 1, 24),
          week1Monday: DateTime(2026, 9, 28),
        ),
        throwsArgumentError,
      );
    });

    test('JSON 往返保留日期且使用 YYYY-MM-DD', () {
      final semester = Semester(
        id: 's1',
        name: 'Fall',
        startDate: DateTime(2026, 9, 28),
        endDate: DateTime(2027, 1, 24),
        week1Monday: DateTime(2026, 9, 28),
      );
      final json = semester.toJson();
      expect(json['startDate'], '2026-09-28');
      expect(json['endDate'], '2027-01-24');
      expect(json['week1Monday'], '2026-09-28');

      final restored = Semester.fromJson(json);
      expect(restored.startDate, DateTime(2026, 9, 28));
      expect(restored.endDate, DateTime(2027, 1, 24));
      expect(restored.week1Monday, DateTime(2026, 9, 28));
    });

    test('JSON 拒绝非法日历日期、未知键与缺字段', () {
      final base = Semester(
        id: 's1',
        name: 'Fall',
        startDate: DateTime(2026, 9, 28),
        endDate: DateTime(2027, 1, 24),
        week1Monday: DateTime(2026, 9, 28),
      ).toJson();

      for (final invalid in [
        '2026-02-29',
        '2026-10-32',
        '2026-13-01',
        '2026-9-28',
        '2026/09/28',
        '2026-09-28T00:00:00',
        'not-a-date',
        20260928,
        null,
      ]) {
        expect(
          () => Semester.fromJson({...base, 'startDate': invalid}),
          throwsFormatException,
          reason: '$invalid',
        );
      }
      expect(
        () => Semester.fromJson({...base, 'extra': 1}),
        throwsFormatException,
      );
      expect(
        () => Semester.fromJson({...base}..remove('name')),
        throwsFormatException,
      );
      // 周一约束在 JSON 解码层同样转换为 FormatException。
      expect(
        () => Semester.fromJson({...base, 'week1Monday': '2026-09-29'}),
        throwsFormatException,
      );
    });
  });

  group('Course 校验', () {
    test('接受合法课程与空 slots', () {
      final course = Course(
        id: 'c1',
        semesterId: 's1',
        name: 'Math',
        credits: 3,
        scoreScaleMax: 4.0,
        slots: const [],
      );
      expect(course.slots, isEmpty);
      expect(course.gradePoint, isNull);
    });

    test('拒绝非有限或非正 credits', () {
      for (final credits in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
          () => Course(
            id: 'c1',
            semesterId: 's1',
            name: 'Math',
            credits: credits,
            scoreScaleMax: 4.0,
            slots: const [],
          ),
          throwsArgumentError,
          reason: 'credits=$credits',
        );
      }
    });

    test('拒绝越界或非有限 gradePoint', () {
      for (final point in [-0.1, 4.1, double.nan, double.infinity]) {
        expect(
          () => Course(
            id: 'c1',
            semesterId: 's1',
            name: 'Math',
            credits: 3,
            gradePoint: point,
            scoreScaleMax: 4.0,
            slots: const [],
          ),
          throwsArgumentError,
          reason: 'gradePoint=$point',
        );
      }
      expect(
        Course(
          id: 'c1',
          semesterId: 's1',
          name: 'Math',
          credits: 3,
          gradePoint: 0,
          scoreScaleMax: 4.0,
          slots: const [],
        ).gradePoint,
        0,
      );
      expect(
        Course(
          id: 'c1',
          semesterId: 's1',
          name: 'Math',
          credits: 3,
          gradePoint: 4,
          scoreScaleMax: 4.0,
          slots: const [],
        ).gradePoint,
        4,
      );
    });

    test('尊重调用方传入的 scoreScaleMax', () {
      expect(
        () => Course(
          id: 'c1',
          semesterId: 's1',
          name: 'Math',
          credits: 3,
          gradePoint: 4.5,
          scoreScaleMax: 5,
          slots: const [],
        ),
        returnsNormally,
      );
      expect(
        () => Course(
          id: 'c1',
          semesterId: 's1',
          name: 'Math',
          credits: 3,
          gradePoint: 4.5,
          scoreScaleMax: 4,
          slots: const [],
        ),
        throwsArgumentError,
      );
    });

    test('slots 构造时复制为不可变列表', () {
      final slots = [
        CourseSlot(weekday: 1, startMinute: 0, endMinute: 60, weeks: [1]),
      ];
      final course = Course(
        id: 'c1',
        semesterId: 's1',
        name: 'Math',
        credits: 3,
        slots: slots,
        scoreScaleMax: 4.0,
      );
      slots.clear();
      expect(course.slots, hasLength(1));
      expect(() => course.slots.clear(), throwsUnsupportedError);
    });

    test('JSON 往返保留 null 与嵌套 slots', () {
      final course = Course(
        id: 'c1',
        semesterId: 's1',
        name: 'Math',
        credits: 3.5,
        gradePoint: null,
        slots: [
          CourseSlot(
            weekday: 2,
            startMinute: 60,
            endMinute: 120,
            weeks: [1, 3],
          ),
        ],
        scoreScaleMax: 4.0,
      );
      final json = course.toJson();
      // 可空字段 toJson 必须写入 null。
      expect(json.containsKey('gradePoint'), isTrue);
      expect(json['gradePoint'], isNull);

      final restored = Course.fromJson(json, scoreScaleMax: 4.0);
      expect(restored.credits, 3.5);
      expect(restored.gradePoint, isNull);
      expect(restored.slots, hasLength(1));
      expect(restored.slots.first.weeks, [1, 3]);
    });

    test('JSON 缺可空键按 null 处理', () {
      final json = Course(
        id: 'c1',
        semesterId: 's1',
        name: 'Math',
        credits: 3,
        scoreScaleMax: 4.0,
        slots: const [],
      ).toJson()..remove('gradePoint');
      expect(Course.fromJson(json, scoreScaleMax: 4.0).gradePoint, isNull);
    });

    test('JSON 拒绝未知键、嵌套未知键与非法领域值', () {
      final base = Course(
        id: 'c1',
        semesterId: 's1',
        name: 'Math',
        credits: 3,
        slots: [
          CourseSlot(weekday: 1, startMinute: 0, endMinute: 60, weeks: [1]),
        ],
        scoreScaleMax: 4.0,
      ).toJson();

      expect(
        () => Course.fromJson({...base, 'extra': 1}, scoreScaleMax: 4.0),
        throwsFormatException,
      );
      expect(
        () => Course.fromJson({...base, 'credits': 0}, scoreScaleMax: 4.0),
        throwsFormatException,
      );
      expect(
        () => Course.fromJson({...base, 'gradePoint': 9}, scoreScaleMax: 4.0),
        throwsFormatException,
      );
      expect(
        () => Course.fromJson({
          ...base,
          'slots': [
            {'weekday': 1},
          ],
        }, scoreScaleMax: 4.0),
        throwsFormatException,
      );
      final nested = Map<String, dynamic>.from(
        (base['slots']! as List).first as Map<String, dynamic>,
      )..['unknown'] = true;
      expect(
        () => Course.fromJson({
          ...base,
          'slots': [nested],
        }, scoreScaleMax: 4.0),
        throwsFormatException,
      );
    });
  });
}
