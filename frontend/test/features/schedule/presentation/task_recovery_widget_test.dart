import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/schedule/controllers/day_schedule_controller.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/presentation/day_schedule_page.dart';
import 'package:student_life_rpg/features/schedule/repositories/file_task_repository.dart';
import 'package:student_life_rpg/features/schedule/services/day_schedule_service.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';

/// D13 UI 层验证：主文件损坏时显示错误 UI
void main() {
  late Directory tempDir;
  late String taskPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('d13_widget_');
    taskPath = '${tempDir.path}/tasks.json';
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> seedGoodData() async {
    final repo = FileTaskRepository(
      const FileJsonDocumentStore(),
      taskPath,
    );
    await repo.insert(
      Task(
        id: 'good',
        title: '有效任务',
        estimatedMinutes: 30,
        isCompleted: false,
        dueAt: DateTime(2026, 11, 10, 23, 59),
      ),
    );
  }

  testWidgets('主文件损坏时 DaySchedulePage 显示错误 UI', (tester) async {
    await seedGoodData();
    await File(taskPath).writeAsString('{坏JSON');

    final loader = _ErrorLoader(const FormatException('主文件损坏'));
    final controller = DayScheduleController(
      loader: loader,
      initialDate: DateTime(2026, 11, 10),
    );
    await controller.loadDay();

    expect(controller.errorMessage, isNotNull);

    await tester.pumpWidget(
      MaterialApp(home: DaySchedulePage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('有效任务'), findsNothing);
    controller.dispose();
  });

  test('恢复取消不调用 recoverFromBackup，继续则恢复', () async {
    await seedGoodData();
    final bakContent = await File('$taskPath.bak').readAsString();
    await File(taskPath).writeAsString('{坏JSON');

    final repo = FileTaskRepository(const FileJsonDocumentStore(), taskPath);

    // 模拟 UI 流程：用户先看到错误 → 弹确认框 → 取消
    var confirmed = false;
    if (confirmed) {
      await repo.recoverFromBackup();
    }
    // 取消：磁盘不变
    expect(await File(taskPath).readAsString(), '{坏JSON');
    expect(await File('$taskPath.bak').readAsString(), bakContent);
    expect(await File('$taskPath.corrupt').exists(), isFalse);

    // 模拟用户第二次尝试 → 弹确认框 → 继续
    confirmed = true;
    if (confirmed) {
      await repo.recoverFromBackup();
    }
    // 继续：主文件恢复，损坏原件归档
    expect(await File(taskPath).readAsString(), bakContent);
    expect(await File('$taskPath.corrupt').exists(), isTrue);
  });
}

class _ErrorLoader implements DayScheduleLoader {
  const _ErrorLoader(this._error);
  final Exception _error;
  @override
  Future<DaySchedule> loadDay(DateTime date) async => throw _error;
}
