import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/app_data.dart';
import 'package:student_life_rpg/app/app_routes.dart';
import 'package:student_life_rpg/app/student_life_app.dart';
import 'package:student_life_rpg/features/finance/finance_memory_scope.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/repositories/file_task_repository.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_task_repository.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';

void main() {
  late Directory directory;
  late String path;

  setUp(() async {
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

  testWidgets('Task survives a new repository and is reflected in Dashboard', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final repository = await AppData.tasks();
      await repository.insert(
        Task(id: 'persisted', title: '重启验收任务', estimatedMinutes: 25),
      );
      await repository.setCompleted('persisted', true);
      final reopened = FileTaskRepository(const FileJsonDocumentStore(), path);
      final restored = await reopened.list();
      expect(restored.single.isCompleted, isTrue);
      AppData.useTaskRepository(reopened);
    });
    await tester.pumpWidget(
      const StudentLifeApp(initialRoute: AppRoutes.schedule),
    );
    await tester.pumpAndSettle();
    expect(find.text('重启验收任务'), findsOneWidget);
    expect(
      (await (await AppData.tasks()).getById('persisted'))!.isCompleted,
      isTrue,
    );
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
    expect(find.textContaining('GPA '), findsOneWidget);
    expect(find.textContaining('收入  ¥'), findsOneWidget);
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
    testWidgets('Menu cards fit $size with enlarged text', (tester) async {
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
      expect(find.text('Schedule'), findsOneWidget);
      expect(
        tester.getSize(find.byType(Card).first).width,
        lessThanOrEqualTo(452),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

class _FailedTasks extends InMemoryTaskRepository {
  @override
  Future<List<Task>> list() async => throw const FileSystemException('读取失败');
}
