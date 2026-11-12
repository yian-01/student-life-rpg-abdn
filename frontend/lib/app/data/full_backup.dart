import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../features/schedule/repositories/file_task_repository.dart';
import '../../shared/storage/json_document_store.dart';
import 'campus_store.dart';

const maxBackupBytes = 64 * 1024 * 1024;

class FullBackup {
  FullBackup._(
    this.createdAt,
    this.campus,
    this.tasks,
    this.counts,
    this.receipts,
  );

  final DateTime createdAt;
  final String campus;
  final String tasks;
  final Map<String, int> counts;
  final List<String> receipts;

  static FullBackup validate(DateTime createdAt, String campus, String tasks) {
    final document = CampusStore.validateBackupDocument(campus);
    final taskRows = FileTaskRepository.validateBackupDocument(tasks);
    final receipts = (document['records'] as List)
        .cast<Map<String, dynamic>>()
        .map((record) => record['receipt'])
        .whereType<String>()
        .toList();
    return FullBackup._(
      createdAt,
      jsonEncode(document),
      tasks,
      Map.unmodifiable({
        'tasks': taskRows.length,
        for (final table in CampusStore.tables)
          table: (document[table] as List).length,
        'receipts': receipts.length,
      }),
      List.unmodifiable(receipts),
    );
  }

  Uint8List encode() {
    final payload = jsonEncode({
      'createdAt': createdAt.toUtc().toIso8601String(),
      'campus': campus,
      'tasks': tasks,
    });
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'student-life-backup',
          'version': 1,
          'payload': payload,
          'sha256': sha256.convert(utf8.encode(payload)).toString(),
        }),
      ),
    );
    if (bytes.length > maxBackupBytes) {
      throw const FormatException('备份超过 64 MB，请减少票据后重试。');
    }
    return bytes;
  }

  factory FullBackup.decode(Uint8List bytes) {
    if (bytes.length > maxBackupBytes) {
      throw const FormatException('备份超过 64 MB。');
    }
    final envelope = jsonDecode(utf8.decode(bytes));
    if (envelope is! Map<String, dynamic> ||
        envelope.length != 4 ||
        envelope['format'] != 'student-life-backup' ||
        envelope['version'] != 1 ||
        envelope['payload'] is! String) {
      throw const FormatException('备份格式或版本不受支持。');
    }
    final payload = envelope['payload'] as String;
    if (sha256.convert(utf8.encode(payload)).toString() != envelope['sha256']) {
      throw const FormatException('备份校验失败，文件可能损坏。');
    }
    final data = jsonDecode(payload);
    if (data is! Map<String, dynamic> ||
        data.length != 3 ||
        data['createdAt'] is! String ||
        data['campus'] is! String ||
        data['tasks'] is! String) {
      throw const FormatException('备份缺少必要的数据。');
    }
    return FullBackup.validate(
      DateTime.parse(data['createdAt'] as String),
      data['campus'] as String,
      data['tasks'] as String,
    );
  }
}

Future<Uint8List> readBackupFile(File file) async {
  final length = await file.length();
  if (length > maxBackupBytes) {
    throw const FormatException('备份超过 64 MB。');
  }
  final fileHandle = await file.open();
  try {
    final bytes = await fileHandle.read(length + 1);
    if (bytes.length > maxBackupBytes) {
      throw const FormatException('备份超过 64 MB。');
    }
    if (bytes.length != length || (await fileHandle.read(1)).isNotEmpty) {
      throw const FormatException('读取时备份文件发生变化，请重新选择。');
    }
    return bytes;
  } finally {
    await fileHandle.close();
  }
}

/// The journal holds the complete previous dataset before either live document
/// is replaced. Until the journal is retired, restart replays the previous set.
class FullBackupService {
  const FullBackupService(this.directory, this.campus, this.tasks);

  final Directory directory;
  final CampusStore campus;
  final FileTaskRepository tasks;

  static File _journal(Directory directory) =>
      File('${directory.path}/restore-pending.json');

  Future<FullBackup> snapshot() => campus.withBackupLock(
    (campusRaw, _) => tasks.withBackupLock(
      (taskRaw, _) async =>
          FullBackup.validate(DateTime.now(), campusRaw, taskRaw),
    ),
  );

  Future<void> restore(
    FullBackup incoming, {
    FullBackup? expected,
    File? committedMarker,
  }) => campus.withBackupLock(
    (campusRaw, replaceCampus) => tasks.withBackupLock((
      taskRaw,
      replaceTasks,
    ) async {
      final journal = _journal(directory);
      if (await journal.exists()) throw StateError('请重启应用，完成上一次恢复。');
      final previous = FullBackup.validate(DateTime.now(), campusRaw, taskRaw);
      if (expected != null &&
          (previous.campus != expected.campus ||
              previous.tasks != expected.tasks)) {
        throw const LocalBackupChanged();
      }
      if (committedMarker != null &&
          previous.campus == incoming.campus &&
          previous.tasks == incoming.tasks) {
        final stagedMarker = File('${committedMarker.path}.tmp');
        await stagedMarker.writeAsString('', flush: true);
        await stagedMarker.rename(committedMarker.path);
        return;
      }
      final staged = File('${journal.path}.tmp');
      await staged.writeAsBytes(previous.encode(), flush: true);
      await staged.rename(journal.path);

      final safetyPath =
          '${directory.path}/before-restore-${DateTime.now().microsecondsSinceEpoch}.json';
      try {
        await replaceCampus(incoming.campus);
        await replaceTasks(incoming.tasks);
        await journal.rename(committedMarker?.path ?? safetyPath);
      } catch (_) {
        try {
          await replaceCampus(previous.campus);
          await replaceTasks(previous.tasks);
          await journal.delete();
        } catch (_) {
          campus.suspendAfterFailedRestore();
          tasks.suspendAfterFailedRestore();
          throw StateError('替换中断，请重启应用以恢复替换前的数据。');
        }
        rethrow;
      }
    }),
  );

  static Future<void> recoverInterrupted(Directory directory) async {
    final journal = _journal(directory);
    if (!await journal.exists()) return;
    final previous = FullBackup.decode(await readBackupFile(journal));
    const files = FileJsonDocumentStore();
    await files.writeDocument('${directory.path}/campus.json', previous.campus);
    await files.writeDocument('${directory.path}/tasks.json', previous.tasks);
    await journal.delete();
  }
}

class LocalBackupChanged implements Exception {
  const LocalBackupChanged();
}
