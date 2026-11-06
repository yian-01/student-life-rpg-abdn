import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/app_theme.dart';
import 'package:student_life_rpg/features/academic/models/assignment.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/academic/models/exam.dart';
import 'package:student_life_rpg/features/academic/presentation/assignment_exam_page.dart';
import 'package:student_life_rpg/features/academic/presentation/timetable_import_page.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';

import '../support/campus_fixture.dart';

/// 组长验收清单要求覆盖 320/390/430 逻辑宽度、键盘、长文本与放大字体。
/// 这里按"宽度 × 字体缩放"组合跑，确认不溢出、关键按钮仍可点到。

Course _course() => Course(
  id: 'c1',
  semesterId: 's1',
  name: '数据结构与算法（中外合作办学）',
  credits: 3.5,
  scoreScaleMax: 4,
  slots: const [],
);

const _widths = <Size>[Size(320, 568), Size(390, 844), Size(430, 932)];

const _scales = <double>[1.0, 1.3, 2.0];

void _applyView(WidgetTester tester, Size size, double scale) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _seed(WidgetTester tester) async {
  // 种子数据在外部准备，这里只保证类型可用。
}

void main() {
  for (final size in _widths) {
    for (final scale in _scales) {
      testWidgets('作业/考试页在 $size × 字体 $scale 下不溢出', (tester) async {
        _applyView(tester, size, scale);
        final data = await campusWithCourse();
        addTearDown(data.dispose);
        await _seed(tester);

        await data.assignments.insert(
          Assignment(
            id: 'a1',
            courseId: 'c1',
            title: '这是一个特别长的作业标题，用于检查换行与省略号是否正常工作',
            dueAt: DateTime(2026, 11, 10, 18),
            description: '很长的描述文字，用于验证多行截断。' * 4,
          ),
        );
        await data.exams.insert(
          Exam(
            id: 'e1',
            courseId: 'c1',
            title: '跨午夜考试（用于检查跨日标记与长标题共存）',
            range: TimeRange(
              start: DateTime(2026, 11, 3, 23, 30),
              end: DateTime(2026, 11, 4, 0, 30),
            ),
            location: '教学楼 A 座 101 教室（东侧）',
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: AssignmentExamPage(data: data, course: _course()),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('考试'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('导入页在 $size × 字体 $scale 下关键控件可见', (tester) async {
        _applyView(tester, size, scale);
        final data = await campusWithCourse();
        addTearDown(data.dispose);
        final semesters = await data.semesters.list();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: TimetableImportPage(data: data, semesters: semesters),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('timetable-input')), findsOneWidget);
        expect(tester.takeException(), isNull);

        // 窄屏 + 大字号时按钮可能被推出屏幕：滚动后必须仍可点到。
        await tester.scrollUntilVisible(
          find.byKey(const Key('parse-button')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('parse-button')), findsOneWidget);
        expect(tester.takeException(), isNull);

        // 滚动到底，确认没有布局异常。
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
