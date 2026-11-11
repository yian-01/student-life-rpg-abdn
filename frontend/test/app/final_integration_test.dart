import '../support/campus_fixture.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/app_data.dart';
import 'package:student_life_rpg/app/app_routes.dart';
import 'package:student_life_rpg/app/student_life_app.dart';
import 'package:student_life_rpg/features/academic/models/assignment.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/academic/models/exam.dart';
import 'package:student_life_rpg/features/academic/models/semester.dart';
import 'package:student_life_rpg/features/finance/finance_memory_scope.dart';
import 'package:student_life_rpg/features/finance/models/budget.dart';
import 'package:student_life_rpg/features/finance/models/finance_record.dart';
import 'package:student_life_rpg/features/finance/models/finance_type.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/repositories/file_task_repository.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_task_repository.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';

void main() {
  late Directory directory;
  late String path;

  setUp(() async {
    AppData.useCampusData(emptyCampusData());
    directory = await Directory.systemTemp.createTemp('app-integration-');
    path = '${directory.path}/tasks.json';
    AppData.useTaskRepository(
      FileTaskRepository(const FileJsonDocumentStore(), path),
    );
    FinanceMemoryScope.resetShared();
  });
  tearDown(() async {
    FinanceMemoryScope.resetShared();
    await directory.delete(recursive: true);
  });

  test('Task completion survives repository reconstruction', () async {
    final repository = await AppData.tasks();
    await repository.insert(
      Task(id: 'persisted', title: '重启验收任务', estimatedMinutes: 25),
    );
    await repository.setCompleted('persisted', true);
    final reopened = FileTaskRepository(const FileJsonDocumentStore(), path);
    final restored = await reopened.list();
    expect(restored.single.title, '重启验收任务');
    expect(restored.single.isCompleted, isTrue);
  });

  testWidgets('Schedule and Dashboard share task state across completion', (
    tester,
  ) async {
    final repository = InMemoryTaskRepository();
    await repository.insert(
      Task(
        id: 'shared',
        title: '共享任务',
        estimatedMinutes: 25,
        isCompleted: false,
      ),
    );
    AppData.useTaskRepository(repository);
    await tester.pumpWidget(
      const StudentLifeApp(initialRoute: AppRoutes.schedule),
    );
    await tester.pumpAndSettle();
    expect(find.text('共享任务'), findsOneWidget);
    await repository.setCompleted('shared', true);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed(AppRoutes.dashboard);
    await tester.pumpAndSettle();
    expect(find.text('已完成 1 / 1'), findsOneWidget);
    expect(find.text('模块待接入'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Dashboard isolates corrupt task storage from other sections', (
    tester,
  ) async {
    AppData.useTaskRepository(_FailedTasks());
    await tester.pumpWidget(
      const StudentLifeApp(initialRoute: AppRoutes.dashboard),
    );
    await tester.pumpAndSettle();
    expect(find.text('加载失败'), findsOneWidget);
    expect(find.text('暂无已评分课程'), findsOneWidget);
    expect(find.textContaining('收入  ¥'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Dashboard shows empty academic agenda and unset budget states', (
    tester,
  ) async {
    AppData.useTaskRepository(InMemoryTaskRepository());
    await tester.pumpWidget(
      const StudentLifeApp(initialRoute: AppRoutes.dashboard),
    );
    await tester.pumpAndSettle();
    // 作业/考试与预算已接入真实仓库；空数据必须是可信空状态，不能吞成 0。
    expect(find.text('作业与考试'), findsOneWidget);
    expect(find.text('今日暂无作业截止或考试'), findsOneWidget);
    expect(find.text('本月未设置分类预算'), findsOneWidget);
    expect(find.text('本月暂无收支记录（收支为 0）'), findsOneWidget);
    expect(find.text('暂无任务'), findsOneWidget);
    expect(find.text('暂无已评分课程'), findsOneWidget);
    expect(find.text('未接入'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Dashboard reads real assignments, exams and category budgets', (
    tester,
  ) async {
    final campus = emptyCampusData();
    AppData.useCampusData(campus);
    AppData.useTaskRepository(InMemoryTaskRepository());

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 作业与考试要求课程引用有效，先建立学期与课程。
    final week1 = DateTime(
      today.year,
      today.month,
      today.day - today.weekday + 1,
    );
    await campus.semesters.insert(
      Semester(
        id: 's1',
        name: '测试学期',
        startDate: week1,
        endDate: DateTime(week1.year, week1.month + 16),
        week1Monday: week1,
      ),
    );
    await campus.courses.insert(
      Course(
        id: 'c1',
        semesterId: 's1',
        name: '测试课程',
        credits: 3,
        slots: const [],
        scoreScaleMax: 4,
      ),
    );
    await campus.assignments.insert(
      Assignment(
        id: 'a1',
        courseId: 'c1',
        title: '今日截止作业',
        dueAt: today.add(const Duration(hours: 18)),
      ),
    );
    await campus.assignments.insert(
      Assignment(
        id: 'a2',
        courseId: 'c1',
        title: '明天截止作业',
        dueAt: today.add(const Duration(days: 1, hours: 18)),
      ),
    );
    await campus.exams.insert(
      Exam(
        id: 'e1',
        courseId: 'c1',
        title: '今日考试',
        range: TimeRange(
          start: today.add(const Duration(hours: 9)),
          end: today.add(const Duration(hours: 11)),
        ),
      ),
    );
    // 默认种子分类已包含 food（餐饮），直接引用即可。
    await campus.records.insert(
      FinanceRecord(
        id: 'r1',
        categoryId: 'food',
        type: FinanceType.expense,
        amountMinor: 3550,
        occurredAt: today.add(const Duration(hours: 12)),
      ),
    );
    await campus.budgets.put(
      Budget(categoryId: 'food', month: today, amountMinor: 10000),
    );

    await tester.pumpWidget(
      const StudentLifeApp(initialRoute: AppRoutes.dashboard),
    );
    await tester.pumpAndSettle();

    expect(find.text('今日截止作业 1 项 · 今日考试 1 场'), findsOneWidget);
    expect(find.text('作业截止  今日截止作业'), findsOneWidget);
    expect(find.text('作业截止  明天截止作业'), findsNothing);
    expect(find.text('考试  今日考试'), findsOneWidget);
    // 预算只抵扣对应分类支出：100.00 - 35.50 = 64.50。
    expect(find.text('餐饮  预算 ¥100.00 · 已用 ¥35.50 · 剩余 ¥64.50'), findsOneWidget);
    expect(find.text('未接入'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Dashboard reloads the shared repository after a module returns',
    (tester) async {
      AppData.useTaskRepository(InMemoryTaskRepository());
      await tester.pumpWidget(
        const StudentLifeApp(initialRoute: AppRoutes.dashboard),
      );
      await tester.pumpAndSettle();
      expect(find.text('暂无任务'), findsOneWidget);
      await tester.tap(find.text('进入模块').first);
      await tester.pumpAndSettle();
      await (await AppData.tasks()).insert(
        Task(id: 'new', title: '返回刷新', estimatedMinutes: 10),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('已完成 0 / 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [
    const Size(240, 320),
    const Size(390, 844),
    const Size(1600, 900),
  ]) {
    testWidgets('Hall doors fit $size with enlarged text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          initialRoute: AppRoutes.menu,
          onGenerateRoute: AppRoutes.generateRoute,
        ),
      );
      await tester.pumpAndSettle();
      for (final id in ['schedule', 'gpa', 'finance', 'dashboard']) {
        expect(find.byKey(Key('door-$id')), findsOneWidget);
      }
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

class _FailedTasks extends InMemoryTaskRepository {
  @override
  Future<List<Task>> list() async => throw const FileSystemException('读取失败');
}
