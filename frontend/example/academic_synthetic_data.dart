import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/academic/models/course_slot.dart';
import 'package:student_life_rpg/features/academic/models/semester.dart';

/// 学术模块测试共用的合成数据。
///
/// Issue #10 要求“提供数学单周与英语每周合成课程、学期与期望输出”，
/// 并明确“演示规则标明合成数据”。本文件即该合成数据来源。
///
/// 学期锚点：week1Monday = 2026-10-05（周一），即第 1 周周一；
/// 学期自 2026-10-05 起，至 2027-01-24 止（含首尾）。
/// 由此可推：
///   10-05 第 1 周、10-12 第 2 周、10-19 第 3 周、
///   10-26 第 4 周、11-02 第 5 周。
///
/// 数学为单周课程 weeks=[1,3,5]（第 1、3、5 周有课），
/// 因此 10-05 有课、10-12 无课、10-19 有课，与 Issue 正文一致；
/// 英语为每周课程 weeks=[1..16]（第 1 至 16 周每周有课）。
const _year = 2026;

/// 第 1 周周一，作为课次周次计算的唯一锚点。
DateTime syntheticWeek1Monday({int year = _year}) => DateTime(year, 10, 5);

/// 合成学期；[year] 可偏移以构造学期外日期。
Semester syntheticSemester({int year = _year}) => Semester(
  id: 'sem-2026-fall',
  name: '2026 秋季学期（合成数据）',
  startDate: DateTime(year, 10, 5),
  endDate: DateTime(year + 1, 1, 24),
  week1Monday: syntheticWeek1Monday(year: year),
);

/// 数学：单周（第 1、3、5 周）周一 08:00-09:40。
Course syntheticMathCourse({int year = _year}) => Course(
  id: 'course-math',
  semesterId: syntheticSemester(year: year).id,
  name: '高等数学（合成数据）',
  credits: 5,
  gradePoint: 3.7,
  slots: [
    CourseSlot(
      weekday: DateTime.monday,
      startMinute: 8 * 60,
      endMinute: 9 * 60 + 40,
      weeks: const [1, 3, 5],
    ),
  ],
  scoreScaleMax: 4.0,
);

/// 英语：每周三 10:00-11:30，覆盖第 1 至 16 周。
Course syntheticEnglishCourse({int year = _year}) => Course(
  id: 'course-english',
  semesterId: syntheticSemester(year: year).id,
  name: '大学英语（合成数据）',
  credits: 3,
  gradePoint: null,
  slots: [
    CourseSlot(
      weekday: DateTime.wednesday,
      startMinute: 10 * 60,
      endMinute: 11 * 60 + 30,
      weeks: List<int>.generate(16, (index) => index + 1),
    ),
  ],
  scoreScaleMax: 4.0,
);

/// 跨日课程：周日 23:30 至 24:00（次日 00:00），第 1 周。
///
/// 契约明确 1440 分钟表示次日 00:00，用于覆盖该边界。
/// 第 1 周的周日为 2026-10-11，次日 00:00 即 2026-10-12。
Course syntheticCrossDayCourse({int year = _year}) => Course(
  id: 'course-night',
  semesterId: syntheticSemester(year: year).id,
  name: '夜间自习（合成数据）',
  credits: 1,
  slots: [
    CourseSlot(
      weekday: DateTime.sunday,
      startMinute: 23 * 60 + 30,
      endMinute: 1440,
      weeks: const [1],
    ),
  ],
  scoreScaleMax: 4.0,
);
