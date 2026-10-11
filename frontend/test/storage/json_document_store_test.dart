import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/storage/json_document_store.dart';

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

  test('读取损坏的 JSON 不抛异常（冻结契约）', () async {
    final file = File('${tempDir.path}/bad.json');
    await file.writeAsString('{not valid json');
    final result = await store.readDocument('${tempDir.path}/bad.json');
    expect(result, isNotNull);
  });
}
