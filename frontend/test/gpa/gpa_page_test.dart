import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/gpa/composition/gpa_composition.dart';
import 'package:student_life_rpg/features/gpa/presentation/gpa_page.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'gpa_controller_test.dart' show ControlledRepository;
import 'gpa_calculator_test.dart' show course;

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  for (var i = 0; i < 20 && finder.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView).first, const Offset(0, -180));
    await tester.pumpAndSettle();
  }
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'real Course edit refreshes GPA and callback, null differs from zero',
    (tester) async {
      final composition = GpaComposition.inMemoryDemo();
      await tester.pumpWidget(
        MaterialApp(home: GpaPage(composition: composition)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('仅存内存'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('edit-demo-english')));
      await tester.enterText(find.byType(TextFormField), 'NaN');
      await tap(tester, find.text('保存'));
      expect(find.text('请输入范围内的有限数字'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '0');
      await tap(tester, find.text('保存'));
      expect(
        (await composition.courseRepository.getById(
          'demo-english',
        ))!.gradePoint,
        0,
      );
      expect((await composition.loadGpa()).gradedCourseCount, 3);
      expect(find.text('GPA：1.85'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('edit-demo-english')));
      await tester.enterText(find.byType(TextFormField), '');
      await tap(tester, find.text('保存'));
      expect(
        (await composition.courseRepository.getById(
          'demo-english',
        ))!.gradePoint,
        isNull,
      );
      expect(find.text('绩点：未评分'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      await tap(tester, find.byType(DropdownButtonFormField<String>));
      await tap(tester, find.text('2027春季').last);
      expect(find.text('GPA：0.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('loading, read error, retry and empty data are distinct', (
    tester,
  ) async {
    final repo = ControlledRepository();
    final pending = Completer<List<Course>>();
    repo.onList = () => pending.future;
    await tester.pumpWidget(
      MaterialApp(
        home: GpaPage(
          composition: GpaComposition(courseRepository: repo, scoreScaleMax: 4),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    pending.completeError(StateError('read'));
    await tester.pumpAndSettle();
    expect(find.text('GPA 读取或保存失败，请重试。'), findsOneWidget);
    expect(find.text('暂无课程'), findsNothing);
    repo.onList = null;
    repo.items = [];
    await tap(tester, find.text('重试'));
    expect(find.text('暂无课程'), findsOneWidget);
    expect(find.text('GPA：暂无已评分课程'), findsOneWidget);
  });

  testWidgets(
    'write failure stays visible and leaves the real input unchanged',
    (tester) async {
      final repo = ControlledRepository()..writeFailure = StateError('write');
      await tester.pumpWidget(
        MaterialApp(
          home: GpaPage(
            composition: GpaComposition(
              courseRepository: repo,
              scoreScaleMax: 4,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const ValueKey('edit-a')));
      await tester.enterText(find.byType(TextFormField), '0');
      await tap(tester, find.text('保存'));
      expect(find.text('GPA 读取或保存失败，请重试。'), findsOneWidget);
      expect(repo.items.first.gradePoint, 4);
      repo.writeFailure = null;
      await tap(tester, find.text('重试'));
      expect(find.text('GPA：4.00'), findsOneWidget);
    },
  );

  testWidgets('long text, small window and grade dialog do not overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(240, 320);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repo = ControlledRepository()
      ..items = [course('很长的课程名称' * 15, point: 3, semester: '很长的学期名称' * 15)];
    await tester.pumpWidget(
      MaterialApp(
        home: GpaPage(
          composition: GpaComposition(courseRepository: repo, scoreScaleMax: 4),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tap(tester, find.text('编辑成绩'));
    expect(tester.takeException(), isNull);
    await tap(tester, find.text('取消'));
    expect(tester.takeException(), isNull);
  });
}
