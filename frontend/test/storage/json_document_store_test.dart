import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';

void main() {
  late Directory tempDir;
  late JsonDocumentStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('json_doc_test_');
    store = JsonDocumentStore.fromPath(tempDir.path);
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('读取不存在的文档返回 null', () async {
    final result = await store.readDocument('${tempDir.path}/not_exist.json');
    expect(result, isNull);
  });

  test('写入和读取文档', () async {
    final path = '${tempDir.path}/task1.json';
    await store.writeDocument(path, '{"name":"测试任务"}');
    final data = await store.readDocument(path);
    expect(data, contains('测试任务'));
  });

  test('写入时保留 .bak 备份', () async {
    final path = '${tempDir.path}/task1.json';
    await store.writeDocument(path, '旧内容');
    await store.writeDocument(path, '新内容');

    final backupData = await store.readDocument(
      '${tempDir.path}/task1.json.bak',
    );
    expect(backupData, contains('旧内容'));
  });

  test('主文件缺失时从 .bak 自动恢复', () async {
    final path = '${tempDir.path}/task1.json';
    await store.writeDocument(path, '旧内容');
    await store.writeDocument(path, '新内容');

    // 模拟崩溃：备份存在但主文件丢失
    await File(path).delete();

    final recovered = await store.readDocument(path);
    expect(recovered, contains('旧内容'));
  });

  test('临时文件写入失败时抛异常且不破坏主文件', () async {
    final badPath = '${tempDir.path}/no_such_dir/task.json';
    await expectLater(
      store.writeDocument(badPath, '内容'),
      throwsA(isA<JsonDocumentStoreIOException>()),
    );
  });

  test('备份路径冲突时抛异常且主文件不受影响', () async {
    final path = '${tempDir.path}/task1.json';
    await store.writeDocument(path, '旧内容');

    // 把 .bak 位置变成一个目录，模拟备份不可写
    await Directory('${tempDir.path}/task1.json.bak').create();

    await expectLater(
      store.writeDocument(path, '新内容'),
      throwsA(isA<JsonDocumentStoreIOException>()),
    );
    final data = await store.readDocument(path);
    expect(data, contains('旧内容'));
  });
}
