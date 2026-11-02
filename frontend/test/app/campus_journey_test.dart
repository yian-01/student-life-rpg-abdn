import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/app_data.dart';
import 'package:student_life_rpg/app/app_routes.dart';
import 'package:student_life_rpg/app/data/campus_data.dart';
import 'package:student_life_rpg/app/data/campus_store.dart';
import 'package:student_life_rpg/app/student_life_app.dart';
import 'package:student_life_rpg/features/academic/models/semester.dart';
import 'package:student_life_rpg/features/academic/presentation/academic_management_page.dart';
import 'package:student_life_rpg/features/gpa/presentation/gpa_page.dart';
import 'package:student_life_rpg/features/schedule/presentation/day_schedule_page.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_task_repository.dart';
import '../support/campus_fixture.dart';

void main() {
  late CampusData data;
  late MemoryCampusDocuments documents;
  setUp(() {
    documents = MemoryCampusDocuments();
    data = CampusData(CampusStore(documents, 'campus.json'));
    AppData.useCampusData(data);
    AppData.useTaskRepository(InMemoryTaskRepository());
  });
  tearDown(() => data.dispose());

  testWidgets(
    'real routes create semester/course, refresh GPA and merge course/event into schedule',
    (tester) async {
      await tester.pumpWidget(
        const StudentLifeApp(initialRoute: AppRoutes.gpa),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GpaPage), findsOneWidget);
      expect(await data.courses.list(), isEmpty);
      await tester.tap(find.byKey(const Key('manage-academic')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-semester')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('semester-name')), '我的学期');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text('我的学期'), findsOneWidget);
      await tester.tap(find.text('课程').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-course')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('course-name')), '算法课程');
      await tester.ensureVisible(find.byKey(const Key('course-point')));
      await tester.enterText(find.byKey(const Key('course-point')), '3.5');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect((await data.courses.list()).single.name, '算法课程');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('GPA：3.50'), findsOneWidget);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.pushNamed(AppRoutes.schedule);
      await tester.pumpAndSettle();
      final now = DateTime.now();
      final days = (8 - now.weekday) % 7;
      for (var i = 0; i < days; i++) {
        await tester.tap(find.byTooltip('后一天'));
        await tester.pumpAndSettle();
      }
      expect(find.text('算法课程'), findsOneWidget);
      final selected = tester
          .widget<DaySchedulePage>(find.byType(DaySchedulePage))
          .controller
          .selectedDate;
      await tester.tap(find.byKey(const Key('manage-events')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-event')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('event-title')), '项目讨论');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect((await data.events.list()).single.title, '项目讨论');
      expect(
        (await data.events.list()).single.range.start,
        DateTime(selected.year, selected.month, selected.day, 9),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      final controller = tester
          .widget<DaySchedulePage>(find.byType(DaySchedulePage))
          .controller;
      expect(
        controller.selectedDate,
        selected,
        reason: 'Management round trip preserves the chosen date',
      );
      final title = find.text('项目讨论');
      await tester.ensureVisible(title);
      expect(title, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'referenced semester deletion shows feedback and keeps the record',
    (tester) async {
      final semester = Semester(
        id: 's',
        name: '学期保护',
        startDate: DateTime(2026, 10, 5),
        endDate: DateTime(2026, 12, 31),
        week1Monday: DateTime(2026, 10, 5),
      );
      await data.semesters.insert(semester);
      await tester.pumpWidget(
        const StudentLifeApp(initialRoute: AppRoutes.academic),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('课程').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-course')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('course-name')), '关联课程');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('学期').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('semester-actions-s')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(await data.semesters.getById('s'), isNotNull);
      expect(find.textContaining('学期可能仍有课程引用'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'persistent finance retains failed input and Dashboard reads the committed record',
    (tester) async {
      await tester.pumpWidget(
        const StudentLifeApp(initialRoute: AppRoutes.finance),
      );
      await tester.pumpAndSettle();
      final amount = find.widgetWithText(TextField, '金额（元）');
      await tester.ensureVisible(amount);
      await tester.enterText(amount, '12.34');
      documents.failWrites = true;
      final add = find.widgetWithText(FilledButton, '添加记录');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(amount).controller!.text, '12.34');
      expect(await data.records.list(), isEmpty);
      documents.failWrites = false;
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(await data.records.list(), hasLength(1));
      expect(tester.widget<TextField>(amount).controller!.text, isEmpty);
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .pushNamed(AppRoutes.dashboard);
      await tester.pumpAndSettle();
      final expense = find.text('支出  ¥12.34');
      await tester.ensureVisible(expense);
      expect(expense, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'corrupt campus data has retry/recovery instead of an empty demo fallback',
    (tester) async {
      documents.documents['campus.json'] = '{bad';
      await tester.pumpWidget(
        const StudentLifeApp(initialRoute: AppRoutes.gpa),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GpaPage), findsNothing);
      expect(find.text('从备份恢复'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(documents.documents['campus.json'], '{bad');
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [const Size(240, 320), const Size(390, 844)]) {
    testWidgets(
      'academic management and course editor fit $size with keyboard',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);
        await data.semesters.insert(
          Semester(
            id: 's',
            name: '小屏学期',
            startDate: DateTime(2026, 10, 5),
            endDate: DateTime(2026, 12, 31),
            week1Monday: DateTime(2026, 10, 5),
          ),
        );
        await tester.pumpWidget(
          const StudentLifeApp(initialRoute: AppRoutes.academic),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AcademicManagementPage), findsOneWidget);
        await tester.tap(find.text('课程').first);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('new-course')));
        await tester.tap(find.byKey(const Key('new-course')));
        await tester.pumpAndSettle();
        tester.view.viewInsets = FakeViewPadding(bottom: size.height * .35);
        await tester.pumpAndSettle();
        final name = find.byKey(const Key('course-name'));
        await tester.ensureVisible(name);
        await tester.enterText(name, '移动端课程');
        final credits = find.byKey(const Key('course-credits'));
        await tester.ensureVisible(credits);
        await tester.enterText(credits, '0');
        final save = find.widgetWithText(FilledButton, '保存');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.text('学分必须是有限正数'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
