import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/repositories/file_task_repository.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';

class _FaultFiles extends DocumentFileOperations {
  String? failRenameSource;
  bool failCopy = false;

  @override
  Future<void> rename(File file, String destination) async {
    if (file.path == failRenameSource) {
      failRenameSource = null;
      throw FileSystemException('injected rename failure', file.path);
    }
    await super.rename(file, destination);
  }

  @override
  Future<void> copy(File file, String destination) async {
    if (failCopy) {
      throw FileSystemException('injected restore failure', file.path);
    }
    await super.copy(file, destination);
  }
}

void main() {
  late Directory directory;
  late String path;
  late _FaultFiles files;
  late FileJsonDocumentStore store;

  Task task(String id) => Task(id: id, title: id, estimatedMinutes: 5);
  FileTaskRepository repository() => FileTaskRepository(store, path);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('real_store_fault_');
    path = '${directory.path}/tasks.json';
    files = _FaultFiles();
    store = FileJsonDocumentStore(files: files);
  });

  tearDown(() => directory.delete(recursive: true));

  test(
    'real store replacement failure restores last committed snapshot',
    () async {
      final repo = repository();
      await repo.insert(task('1'));
      await repo.insert(task('2'));
      final committed = await File(path).readAsString();
      files.failRenameSource = '$path.tmp';

      await expectLater(
        repo.insert(task('3')),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(path).readAsString(), committed);
      expect(await File('$path.bak').readAsString(), committed);
      expect(await File('$path.tmp').exists(), isFalse);
      expect((await repository().list()).map((t) => t.id), ['1', '2']);
      await repo.insert(task('4'));
      expect((await repository().list()).map((t) => t.id), ['1', '2', '4']);
    },
  );

  test('failed rollback retains backup for restart recovery', () async {
    final repo = repository();
    await repo.insert(task('1'));
    final committed = await File(path).readAsString();
    files.failRenameSource = '$path.tmp';
    files.failCopy = true;

    await expectLater(
      repo.insert(task('2')),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File(path).exists(), isFalse);
    expect(await File('$path.bak').readAsString(), committed);
    expect((await repository().list()).map((t) => t.id), ['1']);
  });

  test('failed main rotation retains committed file', () async {
    final repo = repository();
    await repo.insert(task('1'));
    files.failRenameSource = path;
    await expectLater(
      repo.insert(task('2')),
      throwsA(isA<FileSystemException>()),
    );
    expect((await repository().list()).map((t) => t.id), ['1']);
  });

  test('repeated corruption preserves both original documents', () async {
    final repo = repository();
    await repo.insert(task('1'));
    await repo.insert(task('2'));
    await File(path).writeAsString('corrupt one');
    await repo.recoverFromBackup();
    await File(path).writeAsString('corrupt two');
    await repo.recoverFromBackup();
    expect(await File('$path.corrupt').readAsString(), 'corrupt one');
    expect(await File('$path.corrupt.1').readAsString(), 'corrupt two');
    expect((await repository().list()).map((t) => t.id), ['1']);
  });
}
