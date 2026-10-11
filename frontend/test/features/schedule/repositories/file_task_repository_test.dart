import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/repositories/file_task_repository.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';
import 'package:student_life_rpg/storage/json_document_store.dart';

void main() {
  late Directory tempDir;
  late String filePath;
  late JsonDocumentStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('task_repo_test_');
    filePath = '${tempDir.path}/tasks.json';
    store = JsonDocumentStore.fromPath(tempDir.path);
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  FileTaskRepository newRepo() => FileTaskRepository(store, filePath);

  Task newTask(
    String id, {
    String title = '任务',
    int minutes = 30,
    bool completed = false,
  }) {
    return Task(
      id: id,
      title: title,
      estimatedMinutes: minutes,
      isCompleted: completed,
      dueAt: DateTime(2026, 10, 12, 10, 0),
      scheduledRange: TimeRange(
        start: DateTime(2026, 10, 12, 9, 0),
        end: DateTime(2026, 10, 12, 10, 0),
      ),
    );
  }

  // ---------- 基础 CRUD ----------
  test('首次无文件时 list 返回空列表', () async {
    final repo = newRepo();
    expect(await repo.list(), isEmpty);
  });

  test('插入后可从 list/getById 读取', () async {
    final repo = newRepo();
    await repo.insert(newTask('1'));
    expect((await repo.list()).length, 1);
    expect((await repo.getById('1'))?.id, '1');
  });

  test('update 修改任务字段', () async {
    final repo = newRepo();
    await repo.insert(newTask('1', title: '旧标题'));
    await repo.update(newTask('1', title: '新标题'));
    expect((await repo.getById('1'))?.title, '新标题');
  });

  test('remove 成功返回 true，删除后返回 false', () async {
    final repo = newRepo();
    await repo.insert(newTask('1'));
    expect(await repo.remove('1'), isTrue);
    expect(await repo.remove('1'), isFalse);
  });

  test('插入重复 ID 抛 StateError', () async {
    final repo = newRepo();
    await repo.insert(newTask('1'));
    await expectLater(repo.insert(newTask('1')), throwsStateError);
  });

  test('更新不存在的 ID 抛 StateError', () async {
    final repo = newRepo();
    await expectLater(repo.update(newTask('9')), throwsStateError);
  });

  // ---------- 组长要求的故障测试 ----------
  test('有效 records=[] 时 list 返回空列表', () async {
    await File(
      filePath,
    ).writeAsString('{"schemaVersion":1,"entityType":"task","records":[]}');
    final repo = newRepo();
    expect(await repo.list(), isEmpty);
  });

  test('零字节文件被视为损坏并抛异常', () async {
    await File(filePath).writeAsString('');
    final repo = newRepo();
    await expectLater(
      repo.list(),
      throwsA(isA<JsonDocumentStoreIOException>()),
    );
  });

  test('空白文件被视为损坏并抛异常', () async {
    await File(filePath).writeAsString('   \n\t  ');
    final repo = newRepo();
    await expectLater(
      repo.list(),
      throwsA(isA<JsonDocumentStoreIOException>()),
    );
  });

  test('损坏 JSON 文档抛异常', () async {
    await File(
      filePath,
    ).writeAsString('{"schemaVersion":1,"entityType":"task",');
    final repo = newRepo();
    await expectLater(
      repo.list(),
      throwsA(isA<JsonDocumentStoreIOException>()),
    );
  });

  test('schemaVersion 不正确抛异常', () async {
    await File(
      filePath,
    ).writeAsString('{"schemaVersion":99,"entityType":"task","records":[]}');
    final repo = newRepo();
    await expectLater(
      repo.list(),
      throwsA(isA<JsonDocumentStoreIOException>()),
    );
  });

  test('entityType 不正确抛异常', () async {
    await File(
      filePath,
    ).writeAsString('{"schemaVersion":1,"entityType":"project","records":[]}');
    final repo = newRepo();
    await expectLater(
      repo.list(),
      throwsA(isA<JsonDocumentStoreIOException>()),
    );
  });

  test('records 中存在非对象条目抛异常', () async {
    await File(filePath).writeAsString(
      '{"schemaVersion":1,"entityType":"task","records":["hello"]}',
    );
    final repo = newRepo();
    await expectLater(
      repo.list(),
      throwsA(isA<JsonDocumentStoreIOException>()),
    );
  });

  test('保存失败时保留旧内存状态', () async {
    final repo = newRepo();
    await repo.insert(newTask('1'));

    // 删除原文件并用同名目录占位，使后续保存失败
    final file = File(filePath);
    await file.delete();
    await Directory(filePath).create();

    await expectLater(
      repo.insert(newTask('2')),
      throwsA(isA<JsonDocumentStoreIOException>()),
    );

    // 内存中应仍然只有任务1
    final all = await repo.list();
    expect(all.length, 1);
    expect(all.first.id, '1');
  });

  test('连续插入多条记录不丢失', () async {
    final repo = newRepo();
    for (var i = 1; i <= 10; i++) {
      await repo.insert(newTask('$i', title: '任务$i'));
    }
    final all = await repo.list();
    expect(all.length, 10);
    expect(all.map((t) => t.id), containsAll(['1', '5', '10']));
  });

  test('重新创建 Repository 后读取成功', () async {
    final repo = newRepo();
    await repo.insert(newTask('persist'));
    await repo.insert(newTask('persist2'));

    // 重新创建 repository，模拟应用重启
    final restartedRepo = newRepo();
    final all = await restartedRepo.list();
    expect(all.length, 2);
    expect(all.map((t) => t.id), containsAll(['persist', 'persist2']));
  });
}
