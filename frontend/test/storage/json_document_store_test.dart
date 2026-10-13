import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';

void main() {
  late Directory tempDir;
  late JsonDocumentStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('json_doc_test_');
    store = const FileJsonDocumentStore();
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('读取不存在的文档返回 null', () async {
    final result = await store.readDocument('${tempDir.path}/not_exist.json');
    expect(result, isNull);
  });

  test('零字节文件原样返回空字符串，不视为不存在', () async {
    final path = '${tempDir.path}/empty.json';
    await File(path).writeAsString('');
    final result = await store.readDocument(path);
    expect(result, '');
  });

  test('空白文件原样返回，不视为不存在', () async {
    final path = '${tempDir.path}/blank.json';
    await File(path).writeAsString('   \n\t  ');
    final result = await store.readDocument(path);
    expect(result, '   \n\t  ');
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

  test('临时文件写入失败时抛 FileSystemException', () async {
    final badPath = '${tempDir.path}/no_such_dir/task.json';
    await expectLater(
      store.writeDocument(badPath, '内容'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('备份路径冲突时抛异常且主文件不受影响', () async {
    final path = '${tempDir.path}/task1.json';
    await store.writeDocument(path, '旧内容');

    // 把 .bak 位置变成一个目录，模拟备份不可写
    await Directory('${tempDir.path}/task1.json.bak').create();

    await expectLater(
      store.writeDocument(path, '新内容'),
      throwsA(isA<FileSystemException>()),
    );
    final data = await store.readDocument(path);
    expect(data, contains('旧内容'));
  });

  test('主文件丢失且备份存在时，writeDocument 从备份恢复', () async {
    final path = '${tempDir.path}/task1.json';
    await store.writeDocument(path, '内容A');
    await store.writeDocument(path, '内容B');

    // 主文件丢失但 .bak 存在
    await File(path).delete();

    await store.writeDocument(path, '内容C');
    // 恢复后旧备份（内容A）成为主文件，再被新写入转为 .bak
    final data = await store.readDocument(path);
    expect(data, contains('内容C'));
  });
}
