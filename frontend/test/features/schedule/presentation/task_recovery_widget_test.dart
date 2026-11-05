import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/schedule/controllers/day_schedule_controller.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/presentation/day_schedule_page.dart';
import 'package:student_life_rpg/features/schedule/repositories/file_task_repository.dart';
import 'package:student_life_rpg/features/schedule/services/day_schedule_service.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';

/// D13 UI 层验证：主文件损坏时必须显示可识别错误 UI，且恢复只在用户确认后发生。
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

  /// 写入两次，让 Store 生成 `.bak`（首次写入主文件时不会产生备份）。
  Future<void> seedGoodData() async {
    final repo = FileTaskRepository(const FileJsonDocumentStore(), taskPath);
    for (final id in ['t1', 't2']) {
      await repo.insert(
        Task(
          id: id,
          title: '有效任务$id',
          estimatedMinutes: 30,
          isCompleted: false,
          dueAt: DateTime(2026, 11, 10, 23, 59),
        ),
      );
    }
  }

  testWidgets('主文件损坏时显示错误 UI，不静默复活旧数据', (tester) async {
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
    await tester.pump();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.textContaining('日程加载失败'), findsOneWidget);
    // 未恢复前不展示旧数据
    expect(find.textContaining('有效任务'), findsNothing);

    controller.dispose();
  });

  test('用户取消后不写盘，确认后从备份恢复并归档损坏原件', () async {
    await seedGoodData();
    final bakContent = await File('$taskPath.bak').readAsString();
    await File(taskPath).writeAsString('{坏JSON');

    final repo = FileTaskRepository(const FileJsonDocumentStore(), taskPath);

    // 取消：磁盘完全不变
    expect(await File(taskPath).readAsString(), '{坏JSON');
    expect(await File('$taskPath.bak').readAsString(), bakContent);
    expect(await File('$taskPath.corrupt').exists(), isFalse);

    // 确认：恢复为备份内容，损坏原件归档
    await repo.recoverFromBackup();
    expect(await File(taskPath).readAsString(), bakContent);
    expect(await File('$taskPath.corrupt').readAsString(), '{坏JSON');

    // 恢复后可正常读取，且读到备份版本的记录
    final items = await repo.list();
    expect(items, hasLength(1));
    expect(items.single.id, 't1');
  });
}

class _ErrorLoader implements DayScheduleLoader {
  const _ErrorLoader(this._error);
  final Exception _error;
  @override
  Future<DaySchedule> loadDay(DateTime date) async => throw _error;
}
