import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/academic/models/course_slot.dart';
import 'package:student_life_rpg/features/academic/models/semester.dart';
import 'package:student_life_rpg/features/academic/services/course_occurrence_service.dart';
import 'package:student_life_rpg/shared/models/schedule_item.dart';

import 'fixtures.dart';

void main() {
  final semester = syntheticSemester();
  final math = syntheticMathCourse();
  final english = syntheticEnglishCourse();

  // 学期锚点 week1Monday = 2026-10-05（周一），故：
  //   2026-10-05 第 1 周周一（有数学）
  //   2026-10-12 第 2 周周一（无数学）
  //   2026-10-19 第 3 周周一（有数学）
  //   2026-10-26 第 4 周周一（无数学）
  //   2026-11-02 第 5 周周一（有数学）
  group('issue #10 验收：指定日期的课次', () {
    test('数学单周 weeks=[1,3,5]：10-05 有、10-12 无、10-19 有', () {
      expect(
        occurrencesForDate(math, semester, DateTime(2026, 10, 5)),
        hasLength(1),
        reason: '2026-10-05 是第 1 周周一，在 weeks [1,3,5] 内',
      );
      expect(
        occurrencesForDate(math, semester, DateTime(2026, 10, 12)),
        isEmpty,
        reason: '2026-10-12 是第 2 周，不在 weeks [1,3,5]',
      );
      expect(
        occurrencesForDate(math, semester, DateTime(2026, 10, 19)),
        hasLength(1),
        reason: '2026-10-19 是第 3 周周一，在 weeks [1,3,5] 内',
      );
      expect(
        occurrencesForDate(math, semester, DateTime(2026, 10, 26)),
        isEmpty,
        reason: '2026-10-26 是第 4 周，不在 weeks [1,3,5]',
      );
      expect(
        occurrencesForDate(math, semester, DateTime(2026, 11, 2)),
        hasLength(1),
        reason: '2026-11-02 是第 5 周周一，在 weeks [1,3,5] 内',
      );
    });

    test('英语每周：10-07 与 10-14 都有', () {
      expect(
        occurrencesForDate(english, semester, DateTime(2026, 10, 7)),
        hasLength(1),
        reason: '2026-10-07 是第 1 周周三',
      );
      expect(
        occurrencesForDate(english, semester, DateTime(2026, 10, 14)),
        hasLength(1),
        reason: '2026-10-14 是第 2 周周三',
      );
      expect(
        occurrencesForDate(english, semester, DateTime(2026, 10, 21)),
        hasLength(1),
        reason: '2026-10-21 是第 3 周周三',
      );
    });

    test('学期外与星期不匹配返回空列表', () {
      // 学期前（2026-09-28 是周一，但在学期开始 2026-10-05 之前）
      expect(
        occurrencesForDate(math, semester, DateTime(2026, 9, 28)),
        isEmpty,
      );
      // 学期后
      expect(
        occurrencesForDate(english, semester, DateTime(2027, 2, 3)),
        isEmpty,
      );
      // 周一但周次不在 weeks [1,3,5]（2026-10-12 是第 2 周）
      expect(
        occurrencesForDate(math, semester, DateTime(2026, 10, 12)),
        isEmpty,
      );
      // 周四，两个课程都不匹配
      expect(
        occurrencesForDate(math, semester, DateTime(2026, 10, 8)),
        isEmpty,
      );
      expect(
        occurrencesForDate(english, semester, DateTime(2026, 10, 8)),
        isEmpty,
      );
    });

    test('学期首尾当天按周次规则处理', () {
      // 首日 2026-10-05 既是学期开始，也是第 1 周周一，在 weeks [1,3,5] 内。
      expect(
        occurrencesForDate(math, semester, DateTime(2026, 10, 5)),
        hasLength(1),
        reason: '学期首日属于第 1 周，且 weeks 含 1',
      );
      // 末日 2027-01-24 是周日，两者都不匹配。
      expect(
        occurrencesForDate(math, semester, DateTime(2027, 1, 24)),
        isEmpty,
      );
      // 末日当天属于第 17 周，已超出英语 weeks [1..16]。
      expect(
        occurrencesForDate(english, semester, DateTime(2027, 1, 24)),
        isEmpty,
      );
    });
  });

  group('课次输出结构', () {
    test('sourceType/sourceId/title/range 正确且保留原值', () {
      final items = occurrencesForDate(math, semester, DateTime(2026, 10, 5));
      final item = items.single;

      expect(item.sourceType, ScheduleSourceType.course);
      expect(item.sourceId, 'course-math');
      expect(item.title, '高等数学（合成数据）');
      expect(item.range.start, DateTime(2026, 10, 5, 8));
      expect(item.range.end, DateTime(2026, 10, 5, 9, 40));
      expect(item.id, 'course:course-math:0:20261005');
    });

    test('输入日期带时间时归一为当天', () {
      final withTime = occurrencesForDate(
        math,
        semester,
        DateTime(2026, 10, 5, 23, 59, 59),
      );
      final atMidnight = occurrencesForDate(
        math,
        semester,
        DateTime(2026, 10, 5),
      );
      expect(withTime.single.id, atMidnight.single.id);
      expect(withTime.single.range.start, DateTime(2026, 10, 5, 8));
    });

    test('1440 分钟表示次日 00:00，跨日不截断', () {
      final night = syntheticCrossDayCourse();
      // 第 1 周的周日是 2026-10-11。
      final items = occurrencesForDate(night, semester, DateTime(2026, 10, 11));
      final item = items.single;
      expect(item.range.start, DateTime(2026, 10, 11, 23, 30));
      expect(item.range.end, DateTime(2026, 10, 12));
      expect(item.id, 'course:course-night:0:20261011');
    });

    test('0 分钟起点合法', () {
      final course = Course(
        id: 'c-midnight',
        semesterId: semester.id,
        name: '零点课',
        credits: 1,
        slots: [
          CourseSlot(
            weekday: DateTime.monday,
            startMinute: 0,
            endMinute: 60,
            weeks: [1],
          ),
        ],
        scoreScaleMax: 4.0,
      );
      final item = occurrencesForDate(
        course,
        semester,
        DateTime(2026, 10, 5),
      ).single;
      expect(item.range.start, DateTime(2026, 10, 5));
      expect(item.range.end, DateTime(2026, 10, 5, 1));
    });

    test('多个匹配 slot 的 ID 不碰撞并保留 slotIndex', () {
      final course = Course(
        id: 'c-multi',
        semesterId: semester.id,
        name: '多段课',
        credits: 2,
        slots: [
          CourseSlot(
            weekday: DateTime.monday,
            startMinute: 480,
            endMinute: 540,
            weeks: [1],
          ),
          CourseSlot(
            weekday: DateTime.monday,
            startMinute: 600,
            endMinute: 660,
            weeks: [1],
          ),
          CourseSlot(
            weekday: DateTime.tuesday,
            startMinute: 480,
            endMinute: 540,
            weeks: [1],
          ),
        ],
        scoreScaleMax: 4.0,
      );
      final items = occurrencesForDate(course, semester, DateTime(2026, 10, 5));
      expect(items, hasLength(2));
      expect(items.map((item) => item.id), [
        'course:c-multi:0:20261005',
        'course:c-multi:1:20261005',
      ]);
      expect(items.map((item) => item.id).toSet(), hasLength(2));
    });

    test('sourceId 保留原值，ID 中的 courseId 做 URI 编码', () {
      final course = Course(
        id: 'cs 101/甲',
        semesterId: semester.id,
        name: '特殊 ID 课程',
        credits: 1,
        slots: [
          CourseSlot(
            weekday: DateTime.monday,
            startMinute: 0,
            endMinute: 60,
            weeks: [1],
          ),
        ],
        scoreScaleMax: 4.0,
      );
      final item = occurrencesForDate(
        course,
        semester,
        DateTime(2026, 10, 5),
      ).single;

      expect(item.sourceId, 'cs 101/甲');
      expect(item.id, 'course:${Uri.encodeComponent('cs 101/甲')}:0:20261005');
      expect(item.id.contains(' '), isFalse);
      expect(item.id.contains('/'), isFalse);
    });

    test('semesterId 与 semester.id 不一致时拒绝', () {
      final other = Semester(
        id: 'sem-other',
        name: 'Other',
        startDate: DateTime(2026, 10, 5),
        endDate: DateTime(2027, 1, 24),
        week1Monday: DateTime(2026, 10, 5),
      );
      expect(
        () => occurrencesForDate(math, other, DateTime(2026, 10, 5)),
        throwsArgumentError,
      );
    });

    test('slots 为空返回空列表', () {
      final course = Course(
        id: 'c-empty',
        semesterId: semester.id,
        name: '无课时课程',
        credits: 1,
        scoreScaleMax: 4.0,
        slots: const [],
      );
      expect(
        occurrencesForDate(course, semester, DateTime(2026, 10, 5)),
        isEmpty,
      );
    });
  });

  group('算法不修改输入且结果不可变', () {
    test('重复调用返回相同结果，输入保持原值', () {
      final before = math.toJson();
      final weeksBefore = List<int>.from(math.slots.first.weeks);

      final first = occurrencesForDate(math, semester, DateTime(2026, 10, 5));
      final second = occurrencesForDate(math, semester, DateTime(2026, 10, 5));

      expect(first.single.id, second.single.id);
      expect(first.single.range.start, second.single.range.start);
      expect(math.toJson().toString(), before.toString());
      expect(math.slots.first.weeks, weeksBefore);
    });

    test('返回列表不可修改', () {
      final items = occurrencesForDate(math, semester, DateTime(2026, 10, 5));
      expect(() => items.clear(), throwsUnsupportedError);
    });
  });

  group('周次按日历差计算', () {
    test('同一 ISO 周内不同日期属于同一周次', () {
      // 第 5 周：2026-11-02（周一）至 2026-11-08（周日）。
      final weekly = Course(
        id: 'c-weekly',
        semesterId: semester.id,
        name: '每周课',
        credits: 1,
        slots: [
          for (final weekday in [
            DateTime.monday,
            DateTime.tuesday,
            DateTime.wednesday,
            DateTime.thursday,
            DateTime.friday,
            DateTime.saturday,
            DateTime.sunday,
          ])
            CourseSlot(
              weekday: weekday,
              startMinute: 0,
              endMinute: 60,
              weeks: [5],
            ),
        ],
        scoreScaleMax: 4.0,
      );
      final days = [
        DateTime(2026, 11, 2),
        DateTime(2026, 11, 3),
        DateTime(2026, 11, 4),
        DateTime(2026, 11, 5),
        DateTime(2026, 11, 6),
        DateTime(2026, 11, 7),
        DateTime(2026, 11, 8),
      ];
      for (final day in days) {
        expect(
          occurrencesForDate(weekly, semester, day),
          hasLength(1),
          reason: '$day 应属于第 5 周',
        );
      }
      // 第 6 周首日不再是第 5 周。
      expect(
        occurrencesForDate(weekly, semester, DateTime(2026, 11, 9)),
        isEmpty,
      );
    });
  });
}
