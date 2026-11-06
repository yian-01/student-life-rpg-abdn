import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/academic/models/course_slot.dart';
import 'package:student_life_rpg/features/academic/models/semester.dart';
import 'package:student_life_rpg/features/academic/presentation/academic_editors.dart';
import 'package:student_life_rpg/features/academic/services/semester_week_guard.dart';

/// Issue #31 / A13：周次上界必须跟随所选学期的实际周数，
/// 不能再用固定 1000 当上限。
Semester _semester({
  required DateTime start,
  required DateTime end,
  required DateTime week1Monday,
}) => Semester(
  id: 'sem-test',
  name: '测试学期',
  startDate: start,
  endDate: end,
  week1Monday: week1Monday,
);

void main() {
  group('Semester.lastValidWeek：以 week1Monday 为锚', () {
    test('五周学期（10-26 至 11-29）合法周次为 1–5', () {
      final semester = _semester(
        start: DateTime(2026, 10, 26),
        end: DateTime(2026, 11, 29),
        week1Monday: DateTime(2026, 10, 26),
      );
      expect(semester.firstValidWeek, 1);
      expect(semester.lastValidWeek, 5);
      expect(semester.hasSchedulableWeeks, isTrue);
      expect(semester.weekRangeLabel, '1–5 周');
    });

    test('学期最后一天是周中时，该周仍算合法（部分周）', () {
      // 2026-10-26 为第 1 周周一；11-04 落在第 2 周（周三）。
      final semester = _semester(
        start: DateTime(2026, 10, 26),
        end: DateTime(2026, 11, 4),
        week1Monday: DateTime(2026, 10, 26),
      );
      expect(semester.lastValidWeek, 2);
    });

    test('week1Monday 早于开学日时，第 1 周为部分周仍合法', () {
      // 锚点 10-19 早于开学 10-26；10-26 属于第 2 周。
      // 第 6 周周一 = 11-23（≤ 结束日 11-29，合法）；
      // 第 7 周周一 = 11-30（> 结束日，非法）。故上界为 6。
      final semester = _semester(
        start: DateTime(2026, 10, 26),
        end: DateTime(2026, 11, 29),
        week1Monday: DateTime(2026, 10, 19),
      );
      expect(semester.firstValidWeek, 1);
      expect(semester.lastValidWeek, 6);
      expect(semester.hasSchedulableWeeks, isTrue);
    });

    test('week1Monday 晚于结束日期时没有可用周次', () {
      final semester = _semester(
        start: DateTime(2026, 10, 5),
        end: DateTime(2026, 10, 20),
        week1Monday: DateTime(2026, 10, 26),
      );
      expect(semester.lastValidWeek, 0);
      expect(semester.hasSchedulableWeeks, isFalse);
      expect(semester.weekRangeLabel, '无可用周次');
    });

    test('只有一天且是周一锚点时，只有第 1 周', () {
      final semester = _semester(
        start: DateTime(2026, 10, 26),
        end: DateTime(2026, 10, 26),
        week1Monday: DateTime(2026, 10, 26),
      );
      expect(semester.lastValidWeek, 1);
    });
  });

  group('parseCourseWeeks：带学期上界', () {
    final semester = _semester(
      start: DateTime(2026, 10, 26),
      end: DateTime(2026, 11, 29),
      week1Monday: DateTime(2026, 10, 26),
    );
    final maxWeek = semester.lastValidWeek; // 5

    test('A13 回归：五周学期下 1-999 必须被拒绝', () {
      expect(
        () => parseCourseWeeks('1-999', maxWeek: maxWeek),
        throwsFormatException,
      );
    });

    test('超过上界的单个周次与范围都被拒绝', () {
      for (final bad in ['6', '1-6', '5-6', '2,7']) {
        expect(
          () => parseCourseWeeks(bad, maxWeek: maxWeek),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    test('最后合法周可保存，范围内组合正常', () {
      expect(parseCourseWeeks('5', maxWeek: maxWeek), [5]);
      expect(parseCourseWeeks('1-5', maxWeek: maxWeek), [1, 2, 3, 4, 5]);
      expect(parseCourseWeeks('1,3,5', maxWeek: maxWeek), [1, 3, 5]);
    });

    test('仍保留 0、倒序、重复的拒绝', () {
      for (final bad in ['0', '3-1', '1,1,3', '1-3,3', '1,x', '']) {
        expect(
          () => parseCourseWeeks(bad, maxWeek: maxWeek),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    test('学期没有可用周次时，任何周次都拒绝', () {
      final empty = _semester(
        start: DateTime(2026, 10, 5),
        end: DateTime(2026, 10, 20),
        week1Monday: DateTime(2026, 10, 26),
      );
      expect(empty.lastValidWeek, 0);
      expect(
        () => parseCourseWeeks('1', maxWeek: empty.lastValidWeek),
        throwsFormatException,
      );
    });

    test('中文逗号同样按分隔符处理', () {
      expect(parseCourseWeeks('1，3', maxWeek: maxWeek), [1, 3]);
    });
  });

  group('parseCourseWeeks：不带学期上界时的结构校验', () {
    test('仍接受合法的范围与枚举', () {
      expect(parseCourseWeeks('1-3,5,7'), [1, 2, 3, 5, 7]);
    });

    test('保留 1000 这个绝对上限，荒谬输入仍拒绝', () {
      for (final bad in ['', '3-1', '0', '1-3,3', '1-9999999', '1,x']) {
        expect(() => parseCourseWeeks(bad), throwsFormatException, reason: bad);
      }
    });
  });

  group('parseCourseWeeks：单周与双周', () {
    test('1-16单 只取奇数周', () {
      expect(parseCourseWeeks('1-16单'), [
        for (var week = 1; week <= 15; week += 2) week,
      ]);
    });

    test('1-16双 只取偶数周', () {
      expect(parseCourseWeeks('1-16双'), [
        for (var week = 2; week <= 16; week += 2) week,
      ]);
    });

    test('括号写法与全角括号同样接受', () {
      expect(parseCourseWeeks('1-8(单)'), [1, 3, 5, 7]);
      expect(parseCourseWeeks('1-8（双）'), [2, 4, 6, 8]);
    });

    test('单双周仍受学期上界约束', () {
      expect(
        () => parseCourseWeeks('1-16单', maxWeek: 5),
        throwsFormatException,
      );
      expect(parseCourseWeeks('1-5单', maxWeek: 5), [1, 3, 5]);
    });

    test('重复的单周写法被拒绝', () {
      expect(() => parseCourseWeeks('1-8单,1-8单'), throwsFormatException);
    });

    test('区间里没有符合条件的周次时明确报错', () {
      expect(() => parseCourseWeeks('2-2单'), throwsFormatException);
      expect(() => parseCourseWeeks('1-1双'), throwsFormatException);
    });

    test('单双周与普通周次可混写，结果排序', () {
      expect(parseCourseWeeks('1-6单,2,9'), [1, 2, 3, 5, 9]);
    });

    test('混写时与普通区间重叠仍按重复拒绝', () {
      expect(
        () => parseCourseWeeks('1-6单,2-4'),
        throwsFormatException,
        reason: '第 3 周同时被 1-6单 与 2-4 覆盖',
      );
    });
  });

  group('coursesOutsideSemesterWeeks：缩短学期/换学期前的校验', () {
    Course course(String id, String semesterId, String name, List<int> weeks) =>
        Course(
          id: id,
          semesterId: semesterId,
          name: name,
          credits: 2,
          scoreScaleMax: 4,
          slots: [
            CourseSlot(
              weekday: 1,
              startMinute: 540,
              endMinute: 600,
              weeks: weeks,
            ),
          ],
        );

    test('时段都在学期范围内时返回空', () {
      final semester = _semester(
        start: DateTime(2026, 10, 26),
        end: DateTime(2026, 11, 29),
        week1Monday: DateTime(2026, 10, 26),
      );
      final courses = [
        course('c1', semester.id, '数据结构', [1, 3, 5]),
        course('c2', semester.id, '数学', [1, 2, 3, 4, 5]),
      ];
      expect(coursesOutsideSemesterWeeks(semester, courses), isEmpty);
    });

    test('缩短学期后越界的课程被点名，返回顺序与传入一致', () {
      final original = _semester(
        start: DateTime(2026, 10, 26),
        end: DateTime(2026, 11, 29),
        week1Monday: DateTime(2026, 10, 26),
      );
      // 把结束日期提前到 11-15，合法周次从 5 周缩到 3 周。
      final shortened = _semester(
        start: DateTime(2026, 10, 26),
        end: DateTime(2026, 11, 15),
        week1Monday: DateTime(2026, 10, 26),
      );
      expect(original.lastValidWeek, 5);
      expect(shortened.lastValidWeek, 3);

      final courses = [
        course('c1', shortened.id, '数据结构', [1, 3]),
        course('c2', shortened.id, '数学分析', [1, 5]),
        course('c3', shortened.id, '大学物理', [4]),
      ];
      expect(coursesOutsideSemesterWeeks(shortened, courses), ['数学分析', '大学物理']);
    });

    test('只统计本学期的课程，别的学期不受影响', () {
      final semester = _semester(
        start: DateTime(2026, 10, 26),
        end: DateTime(2026, 11, 15),
        week1Monday: DateTime(2026, 10, 26),
      );
      final courses = [
        course('c1', semester.id, '本学期课程', [1, 2]),
        course('c2', 'other-semester', '别的学期课程', [1, 2, 3, 4, 5, 6]),
      ];
      expect(coursesOutsideSemesterWeeks(semester, courses), isEmpty);
    });

    test('校验函数不修改传入的课程数据', () {
      final semester = _semester(
        start: DateTime(2026, 10, 26),
        end: DateTime(2026, 11, 15),
        week1Monday: DateTime(2026, 10, 26),
      );
      final target = course('c1', semester.id, '超范围课程', [1, 5]);
      final before = target.toJson().toString();
      expect(coursesOutsideSemesterWeeks(semester, [target]), ['超范围课程']);
      expect(target.toJson().toString(), before);
      expect(target.slots.single.weeks, [1, 5]);
    });

    test('学期完全没有可用周次时，任何有时段的课程都算越界', () {
      final empty = _semester(
        start: DateTime(2026, 10, 5),
        end: DateTime(2026, 10, 20),
        week1Monday: DateTime(2026, 10, 26),
      );
      expect(empty.lastValidWeek, 0);
      final courses = [
        course('c1', empty.id, '受影响课程', [1]),
      ];
      expect(coursesOutsideSemesterWeeks(empty, courses), ['受影响课程']);
    });
  });
}
