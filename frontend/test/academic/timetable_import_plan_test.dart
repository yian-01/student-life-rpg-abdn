import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/academic/models/course_slot.dart';
import 'package:student_life_rpg/features/academic/services/period_time_table.dart';
import 'package:student_life_rpg/features/academic/services/timetable_import.dart';
import 'package:student_life_rpg/features/academic/services/timetable_import_plan.dart';

/// 构造一小段课表文本，避免测试依赖完整夹具。
String _text(List<String> courseLines) =>
    ['星期一', '5-7', ...courseLines].join('\n');

String _courseLine({
  required String name,
  required String weeks,
  required String credits,
  String classCode = '(2026-2027-1)-DLH58271-CS0202',
}) =>
    '$name 周数：$weeks 校区:南海 上课地点：教C402 教师 ：周国靖 '
    '教学班：$classCode 教学班组成：25软件工程2班 考核方式：考试 选课备注：  '
    '课程学时组成：理论:48 周学时：3 总学时：48 学分：$credits';

TimetableParseResult _parse(List<String> lines) =>
    parseTimetableText(_text(lines));

Course _existing({
  String id = 'c1',
  String name = '数据结构与算法',
  double credits = 2,
  double? gradePoint,
  List<CourseSlot>? slots,
}) => Course(
  id: id,
  semesterId: 's1',
  name: name,
  credits: credits,
  gradePoint: gradePoint,
  slots: slots ?? const [],
  scoreScaleMax: 4,
);

void main() {
  final periods = PeriodTimeTable.scnuNanhai;

  group('buildImportPlan', () {
    test('学期内没有同名课程时标记为新增', () {
      final plan = buildImportPlan(
        parsed: _parse([
          _courseLine(name: '数据结构与算法*', weeks: '1-16周', credits: '3.5'),
        ]),
        existingCourses: const [],
        semesterId: 's1',
        scoreScaleMax: 4,
      );
      expect(plan.createCount, 1);
      expect(plan.items.single.action, ImportAction.create);
      expect(plan.pending, hasLength(1));
      expect(plan.summary, contains('新增 1 门'));
    });

    test('已有同名课程且时段不同时只更新时段', () {
      final plan = buildImportPlan(
        parsed: _parse([
          _courseLine(name: '数据结构与算法*', weeks: '1-16周', credits: '3.5'),
        ]),
        existingCourses: [_existing(gradePoint: 3.7)],
        semesterId: 's1',
        scoreScaleMax: 4,
      );
      expect(plan.updateCount, 1);
      expect(plan.items.single.existing?.id, 'c1');
      expect(plan.items.single.reason, contains('保留原学分与成绩'));
    });

    test('时段完全一致视为无变化，不产生写入', () {
      final range = periods.rangeFor(5, 7)!;
      final plan = buildImportPlan(
        parsed: _parse([
          _courseLine(name: '数据结构与算法*', weeks: '1-16周', credits: '3.5'),
        ]),
        existingCourses: [
          _existing(
            slots: [
              CourseSlot(
                weekday: 1,
                startMinute: range.$1,
                endMinute: range.$2,
                weeks: List<int>.generate(16, (i) => i + 1),
              ),
            ],
          ),
        ],
        semesterId: 's1',
        scoreScaleMax: 4,
      );
      expect(plan.unchangedCount, 1);
      expect(plan.pending, isEmpty);
    });

    test('缺学分的课程被标记为需修正，不默填 1 学分', () {
      final plan = buildImportPlan(
        parsed: _parse([
          _courseLine(name: '数据结构与算法*', weeks: '1-16周', credits: ''),
        ]),
        existingCourses: const [],
        semesterId: 's1',
        scoreScaleMax: 4,
      );
      expect(plan.blockedCount, 1);
      final item = plan.items.single;
      expect(item.action, ImportAction.blocked);
      expect(item.parsed.credits, isNull);
      expect(item.reason, contains('没有给出学分'));
      expect(item.selected, isFalse, reason: '需修正的条目默认不勾选');
    });

    test('课表内同名课程只导入第一门', () {
      final plan = buildImportPlan(
        parsed: _parse([
          _courseLine(name: '数据结构与算法*', weeks: '1-16周', credits: '3.5'),
          _courseLine(
            name: '数据结构与算法*',
            weeks: '2周',
            credits: '3.5',
            classCode: 'OTHER',
          ),
        ]),
        existingCourses: const [],
        semesterId: 's1',
        scoreScaleMax: 4,
      );
      expect(plan.createCount, 1);
      expect(plan.blockedCount, 1);
      expect(plan.items.last.reason, contains('同名'));
    });

    test('其他学期的同名课程不参与比对', () {
      final other = Course(
        id: 'c9',
        semesterId: 's2',
        name: '数据结构与算法',
        credits: 3,
        slots: const [],
        scoreScaleMax: 4,
      );
      final plan = buildImportPlan(
        parsed: _parse([
          _courseLine(name: '数据结构与算法*', weeks: '1-16周', credits: '3.5'),
        ]),
        existingCourses: [other],
        semesterId: 's1',
        scoreScaleMax: 4,
      );
      expect(plan.createCount, 1, reason: '不同学期应视作不同课程');
    });
  });

  group('coursesFromPlan', () {
    test('保留已有成绩与手动改动的学分', () {
      final plan = buildImportPlan(
        parsed: _parse([
          _courseLine(name: '数据结构与算法*', weeks: '1-16周', credits: '3.5'),
        ]),
        existingCourses: [_existing(credits: 2, gradePoint: 3.7)],
        semesterId: 's1',
        scoreScaleMax: 4,
      );
      final courses = coursesFromPlan(plan, scoreScaleMax: 4);
      expect(courses, hasLength(1));
      expect(courses.single.id, 'c1', reason: '更新应复用原 ID');
      expect(courses.single.gradePoint, 3.7, reason: '已有成绩不被覆盖');
      expect(courses.single.credits, 2, reason: '已有学分不被导入覆盖');
      expect(courses.single.slots, hasLength(1));
    });

    test('预览修正的学分优先生效', () {
      final plan = buildImportPlan(
        parsed: _parse([
          _courseLine(name: '数据结构与算法*', weeks: '1-16周', credits: ''),
        ]),
        existingCourses: const [],
        semesterId: 's1',
        scoreScaleMax: 4,
      );
      // 需修正的条目未勾选时不会写入。
      expect(coursesFromPlan(plan, scoreScaleMax: 4), isEmpty);

      plan.items.single.selected = true;
      final courses = coursesFromPlan(
        plan,
        scoreScaleMax: 4,
        creditsOverrides: {'数据结构与算法': 3.5},
      );
      expect(courses, hasLength(1));
      expect(courses.single.credits, 3.5);
      expect(courses.single.gradePoint, isNull, reason: '新课程未评分');
    });

    test('未勾选的条目不会被写入', () {
      final plan = buildImportPlan(
        parsed: _parse([
          _courseLine(name: '数据结构与算法*', weeks: '1-16周', credits: '3.5'),
        ]),
        existingCourses: const [],
        semesterId: 's1',
        scoreScaleMax: 4,
      );
      plan.items.single.selected = false;
      expect(coursesFromPlan(plan, scoreScaleMax: 4), isEmpty);
    });
  });
}
