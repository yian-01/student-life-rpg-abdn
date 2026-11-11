import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/app_theme.dart';
import 'package:student_life_rpg/features/academic/models/assignment.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/academic/models/exam.dart';
import 'package:student_life_rpg/features/academic/models/semester.dart';
import 'package:student_life_rpg/features/academic/presentation/assignment_exam_page.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';
import '../support/in_memory_academic_repositories.dart';

import '../support/campus_fixture.dart';

Course _course() => Course(
  id: 'c1',
  semesterId: 's1',
  name: '数据结构',
  credits: 2,
  scoreScaleMax: 4,
  slots: const [],
);

Future<void> _openEditor(WidgetTester tester, Widget editor) async {
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (inner) {
          context = inner;
          return const Scaffold(body: SizedBox());
        },
      ),
    ),
  );
  showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => editor,
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(240, 320), const Size(390, 844)]) {
    testWidgets('作业编辑器在 $size + 键盘下保存按钮可见且能保存', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);

      final repository = InMemoryAssignmentRepository();
      await _openEditor(
        tester,
        AssignmentEditor(repository: repository, courseId: 'c1'),
      );

      tester.view.viewInsets = FakeViewPadding(bottom: size.height * .35);
      await tester.pumpAndSettle();

      final title = find.byKey(const Key('assignment-title'));
      await tester.ensureVisible(title);
      await tester.enterText(title, '窄屏作业');
      final save = find.widgetWithText(FilledButton, '保存');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(await repository.listForCourse('c1'), hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('考试编辑器在 $size + 键盘下保存按钮可见且能保存', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);

      final repository = InMemoryExamRepository();
      await _openEditor(
        tester,
        ExamEditor(repository: repository, courseId: 'c1'),
      );

      tester.view.viewInsets = FakeViewPadding(bottom: size.height * .35);
      await tester.pumpAndSettle();

      final title = find.byKey(const Key('exam-title'));
      await tester.ensureVisible(title);
      await tester.enterText(title, '窄屏考试');
      final save = find.widgetWithText(FilledButton, '保存');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(await repository.listForCourse('c1'), hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('超长标题与描述在窄屏列表里不溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(280, 480);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final data = emptyCampusData();
    await data.semesters.insert(
      Semester(
        id: 's1',
        name: '测试学期',
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2027, 1, 31),
        week1Monday: DateTime(2026, 8, 31),
      ),
    );
    await data.courses.insert(_course());
    await data.assignments.insert(
      Assignment(
        id: 'a1',
        courseId: 'c1',
        title: '这是一个特别长的作业标题' * 6,
        dueAt: DateTime(2026, 11, 10, 18),
        description: '很长的描述文字' * 20,
      ),
    );
    await data.exams.insert(
      Exam(
        id: 'e1',
        courseId: 'c1',
        title: '一个非常非常长的考试名称' * 6,
        range: TimeRange(
          start: DateTime(2026, 12, 1, 23, 30),
          end: DateTime(2026, 12, 2, 0, 30),
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

    expect(find.text('作业'), findsOneWidget);
    expect(find.text('考试'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('考试'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    data.dispose();
  });
}
