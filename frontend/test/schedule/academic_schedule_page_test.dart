import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/app_data.dart';
import 'package:student_life_rpg/app/app_routes.dart';
import 'package:student_life_rpg/app/app_theme.dart';
import 'package:student_life_rpg/app/data/campus_data.dart';
import 'package:student_life_rpg/app/data/campus_store.dart';
import 'package:student_life_rpg/app/student_life_app.dart';
import 'package:student_life_rpg/features/academic/models/assignment.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/academic/models/course_slot.dart';
import 'package:student_life_rpg/features/academic/models/exam.dart';
import 'package:student_life_rpg/features/academic/models/semester.dart';
import 'package:student_life_rpg/features/academic/presentation/assignment_exam_page.dart';
import 'package:student_life_rpg/features/schedule/controllers/day_schedule_controller.dart';
import 'package:student_life_rpg/features/schedule/controllers/schedule_record_controller.dart';
import 'package:student_life_rpg/features/schedule/models/event.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/presentation/day_schedule_page.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_task_repository.dart';
import 'package:student_life_rpg/shared/models/schedule_item.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';
import 'package:student_life_rpg/shared/presentation/civil_datetime_field.dart';
import '../support/campus_fixture.dart';

final day = DateTime(2028, 2, 28);
TimeRange get times =>
    TimeRange(start: DateTime(2028, 2, 28, 9), end: DateTime(2028, 2, 28, 10));

void main() {
  late CampusData data;
  late MemoryCampusDocuments documents;
  late InMemoryTaskRepository tasks;
  setUp(() {
    documents = MemoryCampusDocuments();
    data = CampusData(CampusStore(documents, 'campus.json'));
    tasks = InMemoryTaskRepository();
    AppData.useCampusData(data);
    AppData.useTaskRepository(tasks);
  });
  Future<void> seed() async {
    await data.semesters.insert(
      Semester(
        id: 'term',
        name: '学期',
        startDate: day,
        endDate: DateTime(2028, 12, 31),
        week1Monday: day,
      ),
    );
    await data.courses.insert(
      Course(
        id: 'course',
        semesterId: 'term',
        name: '课程源',
        credits: 3,
        scoreScaleMax: 4,
        slots: [
          CourseSlot(weekday: 1, startMinute: 540, endMinute: 600, weeks: [1]),
        ],
      ),
    );
  }

  tearDown(() => data.dispose());

  Future<DayScheduleController> open(WidgetTester tester) async {
    await tester.pumpWidget(
      const StudentLifeApp(initialRoute: AppRoutes.schedule),
    );
    await tester.pumpAndSettle();
    final controller = tester
        .widget<DaySchedulePage>(find.byType(DaySchedulePage))
        .controller;
    unawaited(controller.loadDay(day));
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> tapRow(WidgetTester tester, String title) async {
    final scrollable = find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(title),
      180,
      scrollable: scrollable,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text(title)),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  Future<void> changeDate(
    WidgetTester tester,
    String fieldKey,
    DateTime value,
  ) async {
    tester
        .widget<CivilDateTimeField>(find.byKey(Key(fieldKey)))
        .onChanged(value);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'daily schedule creates an assignment for the selected course and date',
    (tester) async {
      await seed();
      await data.courses.insert(
        Course(
          id: 'other-course',
          semesterId: 'term',
          name: '另一门课',
          credits: 3,
          scoreScaleMax: 4,
          slots: [],
        ),
      );
      final controller = await open(tester);
      await tapRow(tester, '新建作业');
      expect(find.byType(AssignmentEditor), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(await data.assignments.list(), isEmpty);

      await tapRow(tester, '新建作业');
      final courseField = find.byKey(const Key('assignment-course'));
      await tester.tap(courseField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('课程源 · 学期').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('assignment-title')),
        '线性代数练习',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      final assignment = (await data.assignments.list()).single;
      expect(assignment.courseId, 'course');
      expect(assignment.dueAt, DateTime(2028, 2, 28, 23, 59));
      expect(controller.selectedDate, day);
      expect(controller.schedule!.assignmentDeadlines.single.id, assignment.id);
      await tapRow(tester, '线性代数练习');
      expect(find.text('作业详情'), findsOneWidget);
    },
  );

  testWidgets(
    'daily schedule explains how to create a course when none exist',
    (tester) async {
      await open(tester);
      await tapRow(tester, '新建作业');
      expect(find.text('先创建一门课程'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '去学期与课程'));
      await tester.pumpAndSettle();
      expect(find.text('学期与课程'), findsOneWidget);
      expect(await data.assignments.list(), isEmpty);
    },
  );

  testWidgets(
    'SC01/SC02 formal route opens exam source; edit date, return and delete refresh correct day',
    (tester) async {
      await seed();
      await data.exams.insert(
        Exam(id: 'exam', courseId: 'course', title: '真实考试', range: times),
      );
      final controller = await open(tester);
      final original = controller.schedule!.items.singleWhere(
        (item) => item.sourceType == ScheduleSourceType.exam,
      );
      await tapRow(tester, '真实考试');
      expect(find.text('考试详情'), findsOneWidget);
      expect(find.text('开始 2028-02-28 09:00'), findsOneWidget);
      expect(find.text('结束 2028-02-28 10:00'), findsOneWidget);
      final edit = tester
          .widget<FilledButton>(find.byKey(const Key('schedule-record-edit')))
          .onPressed!;
      edit();
      edit();
      await tester.pumpAndSettle();
      expect(find.byType(ExamEditor), findsOneWidget);
      await changeDate(tester, 'exam-start', DateTime(2028, 2, 29, 9));
      await changeDate(tester, 'exam-end', DateTime(2028, 2, 29, 10));
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(controller.selectedDate, day);
      expect(
        controller.schedule!.items.any((item) => item.id == original.id),
        isFalse,
      );
      await controller.goToNextDay();
      await tester.pumpAndSettle();
      expect(controller.schedule!.items.single.sourceId, 'exam');
      await tapRow(tester, '真实考试');
      final remove = tester
          .widget<TextButton>(find.byKey(const Key('schedule-record-delete')))
          .onPressed!;
      remove();
      remove();
      await tester.pumpAndSettle();
      expect(find.text('确认删除？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await data.exams.getById('exam'), isNotNull);
      await tester.tap(find.byKey(const Key('schedule-record-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(controller.selectedDate, DateTime(2028, 2, 29));
      expect(controller.schedule!.items, isEmpty);
      expect(await data.exams.list(), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'SC07 assignment details use original repository; cancel preserves, changed date reassigns, delete refreshes',
    (tester) async {
      await seed();
      await data.assignments.insert(
        Assignment(
          id: 'a',
          courseId: 'course',
          title: '独立截止',
          dueAt: DateTime(2028, 2, 28, 18),
        ),
      );
      final controller = await open(tester);
      await tapRow(tester, '独立截止');
      expect(find.text('作业详情'), findsOneWidget);
      await tester.tap(find.byKey(const Key('schedule-record-edit')));
      await tester.pumpAndSettle();
      await changeDate(tester, 'assignment-due', DateTime(2028, 2, 29, 18));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        (await data.assignments.getById('a'))!.dueAt,
        DateTime(2028, 2, 28, 18),
      );
      await tester.tap(find.byKey(const Key('schedule-record-edit')));
      await tester.pumpAndSettle();
      await changeDate(tester, 'assignment-due', DateTime(2028, 2, 29, 18));
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(controller.selectedDate, day);
      expect(controller.schedule!.assignmentDeadlines, isEmpty);
      expect(await tasks.list(), isEmpty);
      await controller.goToNextDay();
      await tester.pumpAndSettle();
      await tapRow(tester, '独立截止');
      await tester.tap(find.byKey(const Key('schedule-record-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(controller.schedule!.assignmentDeadlines, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'SC01 sources select their own details and course has no direct edit/delete',
    (tester) async {
      await seed();
      await data.events.insert(
        Event(id: 'event', title: '事件源', range: times, description: '事件备注'),
      );
      await tasks.insert(
        Task(
          id: 'task',
          title: '任务源',
          estimatedMinutes: 40,
          scheduledRange: times,
        ),
      );
      await data.exams.insert(
        Exam(id: 'exam', courseId: 'course', title: '考试源', range: times),
      );
      await data.assignments.insert(
        Assignment(
          id: 'a',
          courseId: 'course',
          title: '作业源',
          dueAt: DateTime(2028, 2, 28, 23),
        ),
      );
      final controller = await open(tester);
      expect(controller.schedule!.items, hasLength(4));
      await tapRow(tester, '课程源');
      expect(find.text('课程详情'), findsOneWidget);
      expect(find.byKey(const Key('schedule-record-delete')), findsNothing);
      expect(find.byKey(const Key('schedule-record-edit')), findsNothing);
      expect(find.text('进入学期与课程管理'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapRow(tester, '事件源');
      expect(find.text('事件详情'), findsOneWidget);
      expect(find.text('事件备注'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapRow(tester, '任务源');
      expect(find.text('编辑任务'), findsOneWidget);
      expect(find.byType(ExamEditor), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'SC10 corrupt Campus does not hide Task on formal route and cancelling recovery changes nothing',
    (tester) async {
      await seed();
      documents.documents['campus.json'] = '{bad';
      final cold = CampusData(CampusStore(documents, 'campus.json'));
      addTearDown(cold.dispose);
      AppData.useCampusData(cold);
      await tasks.insert(
        Task(id: 'healthy', title: '健康任务', estimatedMinutes: 30),
      );
      await tester.pumpWidget(
        const StudentLifeApp(initialRoute: AppRoutes.schedule),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('schedule-campus-error')), findsOneWidget);
      expect(find.byKey(const Key('schedule-task-error')), findsNothing);
      await tester.scrollUntilVisible(
        find.text('健康任务'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('健康任务'), findsOneWidget);
      expect(find.byKey(const Key('schedule-new-assignment')), findsNothing);
      await tapRow(tester, '恢复学业／事件');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(documents.documents['campus.json'], '{bad');
      expect(find.byKey(const Key('schedule-campus-error')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'SC12 failed real exam save retains input, double click writes once, background return refreshes',
    (tester) async {
      await seed();
      await data.exams.insert(
        Exam(id: 'exam', courseId: 'course', title: '旧标题', range: times),
      );
      final controller = await open(tester);
      await tapRow(tester, '旧标题');
      await tester.tap(find.byKey(const Key('schedule-record-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('exam-title')), '保留的新标题');
      documents.failWrites = true;
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('保存失败'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('exam-title')))
            .controller!
            .text,
        '保留的新标题',
      );
      expect((await data.exams.getById('exam'))!.title, '旧标题');
      documents.failWrites = false;
      final save = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
          .onPressed!;
      save();
      save();
      await tester.pumpAndSettle();
      expect(await data.exams.list(), hasLength(1));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('保留的新标题'), findsOneWidget);
      await data.exams.remove('exam');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        controller.schedule!.items.where(
          (item) => item.sourceType == ScheduleSourceType.exam,
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final width in [320.0, 390.0, 430.0]) {
    testWidgets(
      'SC13 $width mixed list and real exam/assignment dialogs support long text, scale 2, keyboard, validation',
      (tester) async {
        await seed();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);
        final longTitle = '长标题跨模块日程' * 8;
        await data.exams.insert(
          Exam(id: 'exam', courseId: 'course', title: longTitle, range: times),
        );
        await data.assignments.insert(
          Assignment(
            id: 'a',
            courseId: 'course',
            title: '长作业' * 20,
            dueAt: day,
          ),
        );
        final controller = DayScheduleController(
          loader: data.schedule(tasks),
          taskRepository: tasks,
          initialDate: day,
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: DaySchedulePage(
              controller: controller,
              onManageAcademic: () async {},
              onManageEvents: (_) async {},
              onRecover: () async {},
              onRecoverCampus: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Exercise the exact production editors used by schedule details.
        for (final isExam in [true, false]) {
          final context = tester.element(find.byType(DaySchedulePage));
          showDialog<void>(
            context: context,
            builder: (_) => isExam
                ? ExamEditor(repository: data.exams, courseId: 'course')
                : AssignmentEditor(
                    repository: data.assignments,
                    courseId: 'course',
                  ),
          );
          await tester.pumpAndSettle();
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.pumpAndSettle();
          final save = find.widgetWithText(FilledButton, '保存');
          await tester.ensureVisible(save);
          await tester.tap(save);
          await tester.pumpAndSettle();
          final error = find.text(isExam ? '考试名称不能为空' : '作业标题不能为空');
          await tester.ensureVisible(error);
          expect(error.hitTestable(), findsOneWidget);
          final title = find.byKey(
            Key(isExam ? 'exam-title' : 'assignment-title'),
          );
          await tester.ensureVisible(title);
          await tester.enterText(title, longTitle);
          final other = find.byKey(
            Key(isExam ? 'exam-location' : 'assignment-description'),
          );
          await tester.ensureVisible(other);
          await tester.enterText(other, '输入保留');
          await tester.ensureVisible(save);
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          tester.view.viewInsets = const FakeViewPadding();
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test(
    'detail controller guards deletion while pending, reports errors and retries without clearing last record',
    () async {
      final gate = Completer<bool>();
      final repo = _DelayedTasks(gate);
      await repo.insert(Task(id: 'task', title: '详情', estimatedMinutes: 30));
      final controller = ScheduleRecordController<Task>(
        repository: repo,
        id: 'task',
      );
      addTearDown(controller.dispose);
      await controller.load();
      repo.failReads = true;
      await controller.load();
      expect(controller.error, isNotNull);
      expect(controller.record!.title, '详情');
      repo.failReads = false;
      await controller.load();
      expect(controller.error, isNull);
      final first = controller.remove();
      expect(await controller.remove(), isFalse);
      expect(repo.removes, 1);
      gate.completeError(StateError('disk full'));
      expect(await first, isFalse);
      expect(controller.error, contains('删除失败'));
      expect(controller.record!.title, '详情');
    },
  );

  testWidgets(
    'SC13 formal 320 route with all toolbar actions, scale 2 and mixed sources has no overflow',
    (tester) async {
      await seed();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await data.exams.insert(
        Exam(
          id: 'exam',
          courseId: 'course',
          title: '正式考试长标题' * 8,
          range: times,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          onGenerateInitialRoutes: (_) => [
            AppRoutes.generateRoute(
              const RouteSettings(name: AppRoutes.schedule),
            ),
          ],
          onGenerateRoute: AppRoutes.generateRoute,
        ),
      );
      await tester.pumpAndSettle();
      final controller = tester
          .widget<DaySchedulePage>(find.byType(DaySchedulePage))
          .controller;
      unawaited(controller.loadDay(day));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('manage-academic')), findsOneWidget);
      expect(find.byKey(const Key('manage-events')), findsOneWidget);
      expect(find.byTooltip('刷新日程'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _DelayedTasks extends InMemoryTaskRepository {
  _DelayedTasks(this.gate);
  final Completer<bool> gate;
  bool failReads = false;
  int removes = 0;
  @override
  Future<Task?> getById(String id) {
    if (failReads) throw StateError('read failure');
    return super.getById(id);
  }

  @override
  Future<bool> remove(String id) {
    removes++;
    return gate.future;
  }
}
