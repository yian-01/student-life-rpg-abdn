import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/storage/json_document_store.dart';

void main() {
  late Directory tempDir;
  late JsonDocumentStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('json_doc_test_');
    store = JsonDocumentStore(tempDir);
    await store.initialize();
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('写入和读取文档', () async {
    await store.write('task1', {'name': '测试任务'});
    final data = await store.read('task1');
    expect(data['name'], '测试任务');
  });

  test('读取损坏的 JSON 抛出 CorruptedException', () async {
    final file = File('${tempDir.path}/bad.json');
    await file.writeAsString('{not valid json');
    expect(
      () => store.read('bad'),
      throwsA(isA<JsonDocumentCorruptedException>()),
    );
  });

  test('非法 ID 抛出 InvalidDocumentIdException', () {
    expect(
      () => store.write('a/b', {}),
      throwsA(isA<InvalidDocumentIdException>()),
    );
  });

  test('删除文档', () async {
    await store.write('del', {});
    await store.delete('del');
    expect(await store.exists('del'), false);
  });
}
