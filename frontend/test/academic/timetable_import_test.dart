import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/academic/services/period_time_table.dart';
import 'package:student_life_rpg/features/academic/services/timetable_import.dart';

/// 真实数据夹具：从华南师范大学教务系统课表页复制出来的文本，
/// 姓名与学号已替换为占位值。用于验证解析器面对真实格式的表现。
String _sample() =>
    File('test/academic/fixtures/scnu_timetable_sample.txt').readAsStringSync();

ParsedCourse _find(List<ParsedCourse> courses, String name) =>
    courses.firstWhere((course) => course.name == name);

void main() {
  group('PeriodTimeTable', () {
    test('第 5–7 节换算为 14:00–16:20', () {
      final range = PeriodTimeTable.scnuNanhai.rangeFor(5, 7);
      expect(range, isNotNull);
      expect(range!.$1, 14 * 60);
      expect(range.$2, 16 * 60 + 20);
    });

    test('第 9–11 节换算为 19:00–21:20', () {
      final range = PeriodTimeTable.scnuNanhai.rangeFor(9, 11);
      expect(range!.$1, 19 * 60);
      expect(range.$2, 21 * 60 + 20);
    });

    test('未定义的节次返回 null，不猜测', () {
      expect(PeriodTimeTable.scnuNanhai.rangeFor(1, 12), isNull);
      expect(PeriodTimeTable.scnuNanhai.rangeFor(3, 1), isNull);
    });
  });

  group('parseTimetableText：真实课表', () {
    late TimetableParseResult result;

    setUpAll(() {
      result = parseTimetableText(_sample());
    });

    test('识别出 11 门课程、合计 29.5 学分', () {
      expect(
        result.courses,
        hasLength(11),
        reason:
            '实际解析 ${result.courses.length} 门：'
            '${result.courses.map((c) => '${c.name}｜${c.classCode}').join(' /// ')}',
      );
      final total = result.courses.fold<double>(
        0,
        (sum, course) => sum + (course.credits ?? 0),
      );
      expect(total, closeTo(29.5, 0.001));
    });

    test('同名理论课与实验课合并为一门，学分不重复计算', () {
      final dsa = result.courses
          .where((course) => course.name == '数据结构与算法')
          .toList();
      expect(dsa, hasLength(1), reason: '理论与实验应由教学班基号合并');
      expect(dsa.single.credits, 3.5);
      expect(dsa.single.slots, hasLength(2), reason: '周一 5-7 节与 8-8 节是两个时段');
      expect(dsa.single.slots.first.weekday, 1);
      expect(dsa.single.slots.first.startMinute, 14 * 60);
      expect(dsa.single.slots.first.endMinute, 16 * 60 + 20);
    });

    test('实验课单独成段时仍归入同一门课', () {
      final java = _find(result.courses, 'JAVA语言程序设计');
      expect(java.credits, 4.0);
      expect(java.slots.map((slot) => slot.weekday).toSet(), {
        2,
        4,
        5,
      }, reason: '周二、周四、周五都有安排');
    });

    test('多段周数正确展开：1-4周,6-12周 不含第 5 周', () {
      final java = _find(result.courses, 'JAVA语言程序设计');
      final tuesday = java.slots.firstWhere(
        (slot) => slot.weekday == 2 && slot.startMinute == 8 * 60 + 30,
      );
      expect(tuesday.weeks.contains(4), isTrue);
      expect(tuesday.weeks.contains(5), isFalse, reason: '第 5 周被跳过');
      expect(tuesday.weeks.contains(6), isTrue);
      expect(tuesday.weeks.contains(12), isTrue);
      expect(tuesday.weeks.contains(13), isFalse);
    });

    test('零散单周：4周,8周,12周', () {
      // 毛泽东思想周三 5-7 节含单周记录，合并后应覆盖 1–16。
      final mao = _find(result.courses, '毛泽东思想和中国特色社会主义理论体系概论');
      final merged = mao.slots.firstWhere(
        (slot) => slot.weekday == 3 && slot.startMinute == 14 * 60,
      );
      expect(merged.weeks, List<int>.generate(16, (i) => i + 1));
    });

    test('【调】标记被识别，课程名里的标记被去除', () {
      final mao = _find(result.courses, '毛泽东思想和中国特色社会主义理论体系概论');
      expect(mao.adjusted, isTrue);
      expect(mao.name.contains('【调】'), isFalse);
    });

    test('只上两周的课程（13-14周）', () {
      final policy = _find(result.courses, '形势与政策');
      expect(policy.slots, hasLength(1));
      expect(policy.slots.single.weeks, [13, 14]);
      expect(policy.credits, 2.0);
    });

    test('同一时段不同周次的记录合并周次（概率论 2-4 与 5-17）', () {
      final probability = _find(result.courses, '概率论与数理统计');
      expect(probability.slots, hasLength(1), reason: '周四 9-11 节只有一段时间');
      expect(
        probability.slots.single.weeks,
        List<int>.generate(16, (i) => i + 2),
        reason: '2–17 周连续',
      );
      expect(probability.slots.single.startMinute, 19 * 60);
    });

    test('无固定时间的其他课程仍导入学分，但没有时段', () {
      final labour = _find(result.courses, '大学生劳动教育理论和实践(2)');
      expect(labour.slots, isEmpty);
      expect(labour.credits, 1.0);
    });

    test('课程名里的括号与特殊字符不被破坏', () {
      expect(
        result.courses.map((course) => course.name),
        containsAll(<String>['大学体育（3）', '基础英语（3）', '学术英语（3）']),
      );
      expect(
        result.courses.map((course) => course.name),
        contains('探索人工智能：计算的奥秘'),
      );
    });

    test('所有时段都落在节次时刻表的合法范围内', () {
      for (final course in result.courses) {
        for (final slot in course.slots) {
          expect(slot.weekday, inInclusiveRange(1, 7));
          expect(slot.startMinute, lessThan(slot.endMinute));
          expect(slot.weeks, isNotEmpty);
          expect(slot.weeks, orderedEquals([...slot.weeks]..sort()));
          expect(slot.weeks.toSet(), hasLength(slot.weeks.length));
        }
      }
    });
  });

  group('异常输入：不伪装成功', () {
    test('空文本解析出 0 门课程且不抛异常', () {
      final result = parseTimetableText('');
      expect(result.courses, isEmpty);
    });

    test('与课表无关的文本解析出 0 门课程', () {
      final result = parseTimetableText('这是一段随便的文字\n没有任何课程信息');
      expect(result.courses, isEmpty);
    });

    test('格式不支持的课程行记入 issues 而不是静默丢弃', () {
      final result = parseTimetableText('星期一\n5-7\n某课程 周数：?? 学分：3.0');
      expect(result.courses, isEmpty);
      expect(result.issues, isNotEmpty);
    });
  });

  group('toCourses：写入领域模型', () {
    test('缺学分的课程被跳过而不是默填 1 学分', () {
      final parsed = parseTimetableText(_sample()).courses;
      final courses = toCourses(
        parsed: [
          ...parsed,
          ParsedCourse(name: '无学分课程', classCode: 'x', slots: const []),
        ],
        semesterId: 's1',
        scoreScaleMax: 4,
      );
      expect(courses.map((course) => course.name), isNot(contains('无学分课程')));
      expect(courses, hasLength(parsed.length));
    });

    test('导入的课程一律未评分、绑定到目标学期', () {
      final courses = toCourses(
        parsed: parseTimetableText(_sample()).courses,
        semesterId: 'semester-2026-fall',
        scoreScaleMax: 4,
      );
      for (final course in courses) {
        expect(course.gradePoint, isNull);
        expect(course.semesterId, 'semester-2026-fall');
        expect(course.credits, greaterThan(0));
      }
    });

    test('课程 ID 稳定且互不重复', () {
      final parsed = parseTimetableText(_sample()).courses;
      final first = toCourses(
        parsed: parsed,
        semesterId: 's1',
        scoreScaleMax: 4,
      ).map((course) => course.id).toList();
      final second = toCourses(
        parsed: parsed,
        semesterId: 's1',
        scoreScaleMax: 4,
      ).map((course) => course.id).toList();
      expect(first, second, reason: '同一份课表解析两次结果应一致');
      expect(first.toSet(), hasLength(first.length));
    });
  });
}
