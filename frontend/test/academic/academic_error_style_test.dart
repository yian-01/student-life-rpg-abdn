import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/app_theme.dart';
import 'package:student_life_rpg/features/academic/models/assignment.dart';
import 'package:student_life_rpg/features/academic/presentation/academic_management_page.dart';

import '../support/campus_fixture.dart';

/// 验收反馈：删除被引用课程时，原因只显示为普通文字，没有错误样式。
/// 这里锁定"错误提示必须用错误色 + 图标"，避免回归。
void main() {
  testWidgets('删除被引用的课程时，原因以错误样式显示', (tester) async {
    final data = await campusWithCourse();
    addTearDown(data.dispose);
    await data.assignments.insert(
      Assignment(
        id: 'a1',
        courseId: 'c1',
        title: '第一章习题',
        dueAt: DateTime(2026, 11, 10, 18),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AcademicManagementPage(data: data),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('课程').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('course-actions-c1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    final errorRow = find.byKey(const Key('academic-error'));
    expect(errorRow, findsOneWidget, reason: '错误提示必须显式渲染');

    final text = tester.widget<Text>(
      find.descendant(of: errorRow, matching: find.byType(Text)),
    );
    expect(text.data, contains('仍有 1 条作业引用'));
    expect(
      text.style?.color,
      AppTheme.light.colorScheme.error,
      reason: '错误原因使用错误色，不能是普通正文色',
    );

    // 课程与作业都必须保留，不能被删掉一半。
    expect(await data.courses.getById('c1'), isNotNull);
    expect(await data.assignments.list(), hasLength(1));
  });
}
