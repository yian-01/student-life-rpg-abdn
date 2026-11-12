import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../data/full_backup.dart';
import 'sync_dataset.dart';

typedef SyncBase = ({int revision, SyncDataset dataset});
typedef PendingUpload = ({String id, int revision, Uint8List bytes});

class SyncJournal {
  SyncJournal(this.directory);
  final Directory directory;

  File get _base => _file('cloud-base');
  File get _staged => _file('cloud-base-staged');
  File get _applied => _file('cloud-apply-committed');
  File get _upload => _file('cloud-upload-pending');
  File get _imported => _file('cloud-guest-imported');

  File get beforePull => _file('before-cloud-sync.json');
  File get otherConflictBackup => _file('before-cloud-conflict.json');

  File _file(String name) => File('${directory.path}/$name');

  Future<bool> get guestImported => _imported.exists();

  Future<void> markGuestImported() => _write(_imported, const []);

  Future<SyncBase> readBase() async {
    if (!await _base.exists()) return (revision: 0, dataset: SyncDataset.empty);
    final saved = await _read(_base);
    return (
      revision: int.parse(saved.header),
      dataset: SyncDataset(FullBackup.decode(saved.bytes)),
    );
  }

  Future<void> recoverApply() async {
    if (await _applied.exists()) {
      if (await _staged.exists()) await _staged.rename(_base.path);
      if (await _applied.length() == 0) {
        await _applied.delete();
      } else {
        await _applied.rename(beforePull.path);
      }
    } else {
      await _remove(_staged);
    }
  }

  /// FullBackupService renames its rollback journal as the commit marker only
  /// after both live files have been saved. Startup first recovers those files,
  /// then uses this marker to decide whether to promote the staged cloud base.
  Future<void> apply(
    FullBackupService files, {
    required SyncDataset previous,
    required SyncDataset incoming,
    required SyncBase fetched,
  }) async {
    await _write(
      _staged,
      fetched.dataset.backup.encode(),
      '${fetched.revision}',
    );
    await files.restore(
      incoming.backup,
      expected: previous.backup,
      committedMarker: _applied,
    );
    await recoverApply();
  }

  Future<void> saveOtherVersion(SyncDataset data) =>
      _write(otherConflictBackup, data.backup.encode());

  Future<void> startUpload(int expected, SyncDataset dataset) async {
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await _write(_upload, dataset.backup.encode(), '$expected:$id');
  }

  Future<PendingUpload?> pendingUpload() async {
    if (!await _upload.exists()) return null;
    final saved = await _read(_upload);
    final parts = saved.header.split(':');
    if (parts.length != 2 || !RegExp(r'^[0-9a-f]{32}$').hasMatch(parts[1])) {
      throw const FormatException('待上传记录损坏。');
    }
    return (revision: int.parse(parts[0]), id: parts[1], bytes: saved.bytes);
  }

  Future<void> finishUpload(PendingUpload upload, int? revision) async {
    if (revision != null) await _write(_base, upload.bytes, '$revision');
    await _remove(_upload);
  }

  static Future<void> _remove(File file) async {
    if (await file.exists()) await file.delete();
  }

  static Future<void> _write(
    File file,
    List<int> bytes, [
    String? header,
  ]) async {
    final staged = File('${file.path}.tmp');
    final output = await staged.open(mode: FileMode.write);
    try {
      if (header != null) {
        await output.writeString('$header\n', encoding: ascii);
      }
      await output.writeFrom(bytes);
      await output.flush();
    } finally {
      await output.close();
    }
    await staged.rename(file.path);
  }

  static Future<({String header, Uint8List bytes})> _read(File file) async {
    final length = await file.length();
    if (length > maxBackupBytes + 64) {
      throw const FormatException('同步记录超过大小上限。');
    }
    final bytes = await file.readAsBytes();
    final separator = bytes.indexOf(10);
    if (separator < 1 || separator > 64 || bytes.length > maxBackupBytes + 64) {
      throw const FormatException('同步记录损坏。');
    }
    return (
      header: ascii.decode(Uint8List.sublistView(bytes, 0, separator)),
      bytes: Uint8List.sublistView(bytes, separator + 1),
    );
  }
}
