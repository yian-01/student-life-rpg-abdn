import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/repositories/file_task_repository.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';

/// 可注入故障的假 Store：用内存 Map 模拟文件，可配置在第几次写入、哪个阶段抛异常。
class _FakeStore implements JsonDocumentStore {
  final Map<String, String> _files = {};

  /// 第 N 次 writeDocument 触发故障（从 1 开始）；null 表示永不故障。
  int? failOnWriteNumber;

  /// 故障阶段：'backup' = 备份后、替换主文件前；'replace' = 主文件替换时。
  String failStage = 'replace';

  int _writeCount = 0;

  @override
  Future<String?> readDocument(String path) async => _files[path];

  @override
  Future<void> writeDocument(String path, String content) async {
    _writeCount++;
    final shouldFail =
        failOnWriteNumber != null && _writeCount == failOnWriteNumber;

    // 模拟：写临时文件
    final tmpPath = '$path.tmp';
    _files[tmpPath] = content;

    // 模拟：主文件存在时转为 .bak
    final bakPath = '$path.bak';
    if (_files.containsKey(path)) {
      _files[bakPath] = _files[path]!;
      _files.remove(path);
    }

    if (shouldFail && failStage == 'backup') {
      // 备份完成、替换主文件前失败
      _files.remove(tmpPath);
      // 与真实 FileJsonDocumentStore 一致：主文件丢失且备份存在时从备份恢复
      if (!_files.containsKey(path) && _files.containsKey(bakPath)) {
        _files[path] = _files.remove(bakPath)!;
      }
      throw const FileSystemException('模拟：备份后替换前失败');
    }

    if (shouldFail && failStage == 'replace') {
      // 主文件替换失败
      _files.remove(tmpPath);
      throw const FileSystemException('模拟：主文件替换失败');
    }

    // 模拟：临时文件替换主文件
    _files[path] = content;
    _files.remove(tmpPath);
  }
}

void main() {
  late Directory tempDir;
  late String filePath;
  late JsonDocumentStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('task_repo_test_');
    filePath = '${tempDir.path}/tasks.json';
    store = const FileJsonDocumentStore();
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

  test('空白 ID 抛 ArgumentError', () async {
    final repo = newRepo();
    await expectLater(repo.getById('   '), throwsA(isA<ArgumentError>()));
    await expectLater(repo.remove(''), throwsA(isA<ArgumentError>()));
    await expectLater(
      repo.setCompleted('\t', true),
      throwsA(isA<ArgumentError>()),
    );
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

  // ---------- 损坏数据测试 ----------
  test('有效 records=[] 时 list 返回空列表', () async {
    await File(
      filePath,
    ).writeAsString('{"schemaVersion":1,"entityType":"Task","records":[]}');
    final repo = newRepo();
    expect(await repo.list(), isEmpty);
  });

  test('顶层未知字段被拒绝', () async {
    await File(filePath).writeAsString(
      '{"schemaVersion":1,"entityType":"Task","records":[],"extra":"bad"}',
    );
    final repo = newRepo();
    await expectLater(repo.list(), throwsA(isA<FormatException>()));
  });

  test('零字节文件被视为损坏并抛 FormatException', () async {
    await File(filePath).writeAsString('');
    final repo = newRepo();
    await expectLater(repo.list(), throwsA(isA<FormatException>()));
  });

  test('空白文件被视为损坏并抛 FormatException', () async {
    await File(filePath).writeAsString('   \n\t  ');
    final repo = newRepo();
    await expectLater(repo.list(), throwsA(isA<FormatException>()));
  });

  test('损坏 JSON 文档抛 FormatException', () async {
    await File(
      filePath,
    ).writeAsString('{"schemaVersion":1,"entityType":"Task",');
    final repo = newRepo();
    await expectLater(repo.list(), throwsA(isA<FormatException>()));
  });

  test('schemaVersion 不正确抛 FormatException', () async {
    await File(
      filePath,
    ).writeAsString('{"schemaVersion":99,"entityType":"Task","records":[]}');
    final repo = newRepo();
    await expectLater(repo.list(), throwsA(isA<FormatException>()));
  });

  test('entityType 不正确抛 FormatException', () async {
    await File(
      filePath,
    ).writeAsString('{"schemaVersion":1,"entityType":"project","records":[]}');
    final repo = newRepo();
    await expectLater(repo.list(), throwsA(isA<FormatException>()));
  });

  test('records 中存在非对象条目抛 FormatException', () async {
    await File(filePath).writeAsString(
      '{"schemaVersion":1,"entityType":"Task","records":["hello"]}',
    );
    final repo = newRepo();
    await expectLater(repo.list(), throwsA(isA<FormatException>()));
  });

  test('records 中存在重复 ID 抛 FormatException', () async {
    await File(filePath).writeAsString(
      '{"schemaVersion":1,"entityType":"Task","records":['
      '{"id":"1","title":"a","estimatedMinutes":10,"isCompleted":false,'
      '"dueAt":null,"scheduledRange":null},'
      '{"id":"1","title":"b","estimatedMinutes":10,"isCompleted":false,'
      '"dueAt":null,"scheduledRange":null}'
      ']}',
    );
    final repo = newRepo();
    await expectLater(repo.list(), throwsA(isA<FormatException>()));
  });

  // ---------- 备份恢复测试 ----------
  test('重启后从经过完整校验的备份恢复', () async {
    // 先写入有效数据，再制造 .bak
    final repo = newRepo();
    await repo.insert(newTask('persist', title: '备份任务'));

    // 读取主文件内容作为备份
    final mainContent = await File(filePath).readAsString();
    // 制造一个损坏的主文件 + 有效的 .bak
    await File(filePath).writeAsString('损坏的内容');
    await File('$filePath.bak').writeAsString(mainContent);

    // 重新创建 Repository，应从 .bak 恢复
    final restartedRepo = newRepo();
    final all = await restartedRepo.list();
    expect(all.length, 1);
    expect(all.first.id, 'persist');
    expect(all.first.title, '备份任务');

    // 损坏原件应归档为 .corrupt；有效 .bak 必须保留不被覆盖
    final corruptContent = await File('$filePath.corrupt').readAsString();
    expect(corruptContent, '损坏的内容');
    final bakContent = await File('$filePath.bak').readAsString();
    expect(bakContent, mainContent);
  });

  test('非空但非法的备份被拒绝', () async {
    await File(filePath).writeAsString('损坏的主文件');
    await File('$filePath.bak').writeAsString('{非空但非法的备份}');

    final repo = newRepo();
    await expectLater(repo.list(), throwsA(isA<FormatException>()));

    // 损坏的原文件仍保留
    expect(await File(filePath).readAsString(), '损坏的主文件');
  });

  test('主文件损坏且无备份时抛 FormatException', () async {
    await File(filePath).writeAsString('损坏的主文件');
    final repo = newRepo();
    await expectLater(repo.list(), throwsA(isA<FormatException>()));
  });

  test('主文件丢失但备份存在时从备份恢复', () async {
    final repo = newRepo();
    await repo.insert(newTask('persist'));
    // 第二次写入才会产生 .bak（保留上一版内容）
    await repo.insert(newTask('second'));

    // 删除主文件，保留 .bak（.bak 中是 [persist]）
    await File(filePath).delete();

    final restartedRepo = newRepo();
    final all = await restartedRepo.list();
    expect(all.length, 1);
    expect(all.first.id, 'persist');
  });

  // ---------- 保存失败与队列测试 ----------
  test('保存失败时保留旧内存状态且磁盘数据完整', () async {
    final repo = newRepo();
    await repo.insert(newTask('1'));

    // 用同名目录阻塞临时文件路径，使保存失败；主文件仍可读
    await Directory('$filePath.tmp').create();

    await expectLater(
      repo.insert(newTask('2')),
      throwsA(isA<FileSystemException>()),
    );

    // 内存中应仍然只有任务1
    final all = await repo.list();
    expect(all.length, 1);
    expect(all.first.id, '1');

    // 重新创建 Repository 验证磁盘数据未损坏
    final restartedRepo = newRepo();
    final diskAll = await restartedRepo.list();
    expect(diskAll.length, 1);
    expect(diskAll.first.id, '1');

    await Directory('$filePath.tmp').delete();
  });

  test('一次保存失败后，队列仍可继续成功保存', () async {
    final fakeStore = _FakeStore();
    final repo = FileTaskRepository(fakeStore, filePath);

    // 第一次写入成功
    await repo.insert(newTask('1'));

    // 第二次写入（insert '2'）触发故障
    fakeStore.failOnWriteNumber = 2;
    fakeStore.failStage = 'replace';

    await expectLater(
      repo.insert(newTask('2')),
      throwsA(isA<FileSystemException>()),
    );

    // 队列仍可继续：第三次写入应成功
    fakeStore.failOnWriteNumber = null;
    await repo.insert(newTask('3'));

    final all = await repo.list();
    expect(all.map((t) => t.id), containsAll(['1', '3']));
    expect(all.any((t) => t.id == '2'), isFalse);
  });

  test('备份后、替换主文件前失败时，旧数据仍可恢复', () async {
    final fakeStore = _FakeStore();
    final repo = FileTaskRepository(fakeStore, filePath);

    await repo.insert(newTask('1'));

    // 第二次写入在备份后、替换前失败
    fakeStore.failOnWriteNumber = 2;
    fakeStore.failStage = 'backup';

    await expectLater(
      repo.insert(newTask('2')),
      throwsA(isA<FileSystemException>()),
    );

    // 主文件应已从备份恢复（仍包含任务1）
    expect(await fakeStore.readDocument(filePath), isNotNull);

    // 重新创建 Repository 验证磁盘数据可恢复（避免命中旧内存缓存）
    final restartedRepo = FileTaskRepository(fakeStore, filePath);
    final all = await restartedRepo.list();
    expect(all.length, 1);
    expect(all.first.id, '1');
  });

  test('主文件替换失败时，旧数据保留在备份中并可恢复', () async {
    final fakeStore = _FakeStore();
    final repo = FileTaskRepository(fakeStore, filePath);

    await repo.insert(newTask('1'));

    fakeStore.failOnWriteNumber = 2;
    fakeStore.failStage = 'replace';

    await expectLater(
      repo.insert(newTask('2')),
      throwsA(isA<FileSystemException>()),
    );

    // 重新创建 Repository 验证磁盘数据可恢复
    final restartedRepo = FileTaskRepository(fakeStore, filePath);
    final all = await restartedRepo.list();
    expect(all.length, 1);
    expect(all.first.id, '1');
  });

  test('并发插入不丢记录', () async {
    final repo = newRepo();
    final futures = <Future<void>>[];
    for (var i = 1; i <= 20; i++) {
      futures.add(repo.insert(newTask('$i')));
    }
    await Future.wait(futures);

    final all = await repo.list();
    expect(all.length, 20);
    expect(all.map((t) => t.id).toSet().length, 20);
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

    final restartedRepo = newRepo();
    final all = await restartedRepo.list();
    expect(all.length, 2);
    expect(all.map((t) => t.id), containsAll(['persist', 'persist2']));
  });

  // ---------- 真实 Store 故障与运行期间保护测试 ----------
  test('真实 Store：备份路径被目录占用时主文件不变', () async {
    final repo = newRepo();
    await repo.insert(newTask('1'));
    // 第二次写入产生 .bak（保留任务1）
    await repo.insert(newTask('2'));

    // 现在：主文件=任务1+2，.bak=任务1

    // 把 .bak 变成非空目录，使 writeDocument 的 backup.delete() 失败
    await File('$filePath.bak').delete();
    final bakDir = Directory('$filePath.bak');
    await bakDir.create();
    await File('${bakDir.path}/dummy.txt').writeAsString('x');

    // 尝试保存应失败
    await expectLater(
      repo.insert(newTask('3')),
      throwsA(isA<FileSystemException>()),
    );

    // 主文件内容应不变；重新创建 Repository 验证
    final restartedRepo = newRepo();
    final all = await restartedRepo.list();
    expect(all.length, 2);
    expect(all.map((t) => t.id), containsAll(['1', '2']));
  });

  test('runtime corruption blocks mutation until explicit recovery', () async {
    final repo = newRepo();
    await repo.insert(newTask('1'));
    await repo.insert(newTask('2'));
    final backup = await File('$filePath.bak').readAsString();
    await File(filePath).writeAsString('external corruption');

    await expectLater(repo.insert(newTask('3')), throwsFormatException);
    expect(await File(filePath).readAsString(), 'external corruption');
    expect(await File('$filePath.bak').readAsString(), backup);
    expect((await repo.list()).map((t) => t.id), ['1', '2']);

    await repo.recoverFromBackup();
    expect(
      await File('$filePath.corrupt').readAsString(),
      'external corruption',
    );
    expect(await File('$filePath.bak').readAsString(), backup);
    // The backup is the previous successful snapshot: task 1, not task 2.
    expect((await repo.list()).map((t) => t.id), ['1']);
    await repo.insert(newTask('3'));
    expect((await newRepo().list()).map((t) => t.id), ['1', '3']);
  });

  test('failed explicit recovery retains cache and can retry', () async {
    final repo = newRepo();
    await repo.insert(newTask('1'));
    await repo.insert(newTask('2'));
    await File(filePath).writeAsString('damaged');
    await Directory('$filePath.tmp').create();
    await expectLater(
      repo.recoverFromBackup(),
      throwsA(isA<FileSystemException>()),
    );
    expect((await repo.list()).map((t) => t.id), ['1', '2']);
    await Directory('$filePath.tmp').delete();
    await repo.recoverFromBackup();
    expect((await newRepo().list()).map((t) => t.id), ['1']);
    expect(await File('$filePath.corrupt').readAsString(), 'damaged');
  });

  test('主文件损坏且恢复失败后仍可重试，不丢失有效数据', () async {
    final repo = newRepo();
    await repo.insert(newTask('1'));

    // 制造损坏主文件 + 有效 .bak
    final mainContent = await File(filePath).readAsString();
    await File(filePath).writeAsString('损坏');
    await File('$filePath.bak').writeAsString(mainContent);

    // 阻塞 tmp 路径，使恢复写入失败
    await Directory('$filePath.tmp').create();

    // 第一次恢复应失败
    final repo1 = newRepo();
    await expectLater(repo1.list(), throwsA(isA<FileSystemException>()));

    // 不丢失最后有效数据：Store 的失败恢复会把 .bak 内容写回主文件，
    // 因此主文件或 .bak 中必有一份有效内容。
    final mainExists = await File(filePath).exists();
    final bakExists = await File('$filePath.bak').exists();
    expect(mainExists || bakExists, isTrue);
    if (mainExists) {
      expect(await File(filePath).readAsString(), mainContent);
    } else {
      expect(await File('$filePath.bak').readAsString(), mainContent);
    }

    // 解除阻塞后重试应成功读取旧记录
    await Directory('$filePath.tmp').delete();
    final repo2 = newRepo();
    final all = await repo2.list();
    expect(all.length, 1);
    expect(all.first.id, '1');

    // 损坏原件已归档为 .corrupt，未被静默丢弃
    expect(await File('$filePath.corrupt').readAsString(), '损坏');
  });
}
