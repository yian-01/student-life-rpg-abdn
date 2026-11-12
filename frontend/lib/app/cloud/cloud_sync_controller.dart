import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../app_data.dart';
import '../data/full_backup.dart';
import 'sync_api.dart';
import 'sync_dataset.dart';
import 'sync_journal.dart';

abstract interface class CloudSessionStore {
  Future<CloudSession?> read();
  Future<void> save(CloudSession session);
  Future<void> clear();
}

class SecureCloudSessionStore implements CloudSessionStore {
  const SecureCloudSessionStore();

  static const _storage = FlutterSecureStorage();
  static const _key = 'student-life-cloud-session-v1';

  @override
  Future<CloudSession?> read() async {
    final raw = await _storage.read(key: _key);
    return raw == null ? null : CloudSession.restore(raw);
  }

  @override
  Future<void> save(CloudSession session) =>
      _storage.write(key: _key, value: session.encode());

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class CloudConflict {
  const CloudConflict({
    required this.local,
    required this.other,
    required this.merge,
    required this.guest,
    this.revision,
  });

  final SyncDataset local;
  final SyncDataset other;
  final SyncMerge merge;
  final bool guest;
  final int? revision;
}

class CloudSyncController extends ChangeNotifier {
  CloudSyncController({
    CloudSyncApi? api,
    CloudSessionStore? sessions,
    Future<Directory> Function()? rootDirectory,
    Future<FullBackupService> Function()? activeBackup,
    Future<FullBackupService> Function()? guestBackup,
    void Function(Directory?)? switchDirectory,
  }) : _api = api ?? HttpCloudSyncApi(),
       _sessions = sessions ?? const SecureCloudSessionStore(),
       _rootDirectory = rootDirectory ?? AppData.rootDirectory,
       _activeBackup = activeBackup ?? AppData.backup,
       _guestBackup = guestBackup ?? AppData.guestBackup,
       _switchDirectory = switchDirectory ?? AppData.switchDirectory;

  static const configuredOrigin = String.fromEnvironment('CAMPUS_SYNC_URL');

  final CloudSyncApi _api;
  final CloudSessionStore _sessions;
  final Future<Directory> Function() _rootDirectory;
  final Future<FullBackupService> Function() _activeBackup;
  final Future<FullBackupService> Function() _guestBackup;
  final void Function(Directory?) _switchDirectory;

  CloudSession? _session;
  SyncJournal? _journal;
  int _scope = 0;
  bool _working = false;
  bool _applying = false;
  bool _expired = false;
  bool _guestImported = false;
  bool _safeRoute = false;
  bool _foreground = true;
  DateTime? _lastSync;
  String? _notice;
  CloudConflict? _conflict;

  CloudSession? get session => _session;
  int get scope => _scope;
  bool get working => _working;
  bool get applying => _applying;
  bool get expired => _expired;
  bool get guestImported => _guestImported;
  DateTime? get lastSync => _lastSync;
  String? get notice => _notice;
  CloudConflict? get conflict => _conflict;
  File? get beforePull => _journal?.beforePull;
  File? get otherConflictBackup => _journal?.otherConflictBackup;

  Future<void> initialize() async {
    try {
      final session = await _sessions.read();
      if (session != null) await _open(session, remember: false);
    } catch (_) {
      _notice = '无法读取本机云账号。可以继续使用本机模式，或重新登录。';
    }
  }

  Future<void> _open(CloudSession session, {required bool remember}) async {
    final root = await _rootDirectory();
    final id = sha256.convert(utf8.encode('${session.origin}\n${session.id}'));
    final directory = Directory('${root.path}/cloud-accounts/$id');
    await directory.create(recursive: true);
    await FullBackupService.recoverInterrupted(directory);
    final journal = SyncJournal(directory);
    await journal.recoverApply();
    final imported = await journal.guestImported;
    if (remember) await _sessions.save(session);
    final sameAccount =
        _session?.origin == session.origin && _session?.id == session.id;
    if (!sameAccount) {
      _switchDirectory(directory);
      _scope++;
      _lastSync = null;
      _conflict = null;
    }
    _session = session;
    _journal = journal;
    _expired = false;
    _guestImported = imported;
  }

  Future<void> signIn({
    required String server,
    required String email,
    required String password,
    required bool register,
    String code = '',
  }) => _perform(() async {
    final previous = _session;
    final origin = parseSyncOrigin(server);
    if (previous != null &&
        (origin != previous.origin ||
            email.trim().toLowerCase() != previous.email ||
            register)) {
      throw const FormatException('请先退出当前账号，再切换账号。');
    }
    final authenticated = await _api.authenticate(
      origin,
      email: email.trim(),
      password: password,
      register: register,
      code: code,
    );
    if (previous != null && previous.id != authenticated.id) {
      throw const FormatException('服务器上的账号身份已变化，请退出后重新登录。');
    }
    await _open(authenticated, remember: true);
    _notice = '已登录。可在账号页导入本机 V1.0 数据。';
  });

  Future<void> signOut() => _perform(() async {
    final session = _session;
    if (session == null) return;
    await _sessions.clear();
    _switchDirectory(null);
    _session = null;
    _journal = null;
    _expired = false;
    _conflict = null;
    _lastSync = null;
    _guestImported = false;
    _scope++;
    _notice = '已退出。本机账号副本已隔离，下次登录同一账号可继续同步。';
    unawaited(_revokeQuietly(session));
  });

  Future<void> _revokeQuietly(CloudSession session) async {
    try {
      await _api.revoke(session);
    } catch (_) {
      // An offline sign-out must still remove the device's stored credential.
    }
  }

  void routeChanged({required bool safe}) => _safeRoute = safe;

  void lifecycleChanged({required bool foreground}) {
    _foreground = foreground;
    if (foreground) unawaited(autoSync());
  }

  Future<void> autoSync() async {
    if (_safeRoute && _foreground && _conflict == null) await sync();
  }

  Future<void> sync({SyncChoice? choice, bool whole = false}) async {
    final session = _session;
    final journal = _journal;
    if (session == null || journal == null || _expired || !_safeRoute) return;
    await _perform(() => _sync(session, journal, choice: choice, whole: whole));
  }

  Future<void> _sync(
    CloudSession session,
    SyncJournal journal, {
    SyncChoice? choice,
    bool whole = false,
  }) async {
    await journal.recoverApply();
    await _resumeUpload(session, journal);
    final files = await _activeBackup();
    final base = await journal.readBase();
    final fetched = await _api.fetch(session, knownRevision: base.revision);
    if (fetched.revision < base.revision) {
      throw const FormatException('云端版本早于本机同步记录，请联系管理员。');
    }
    final remote = fetched.unchanged
        ? base.dataset
        : fetched.bytes == null
        ? SyncDataset.empty
        : SyncDataset(FullBackup.decode(fetched.bytes!));
    final local = SyncDataset(await files.snapshot());
    if (!_safeRoute || !_foreground) return;
    final previous = _conflict;
    if (choice != null &&
        (previous == null ||
            previous.guest ||
            previous.revision != fetched.revision ||
            !previous.local.sameData(local) ||
            !previous.other.sameData(remote))) {
      choice = null;
      whole = false;
    }
    final result = SyncMerge.reconcile(
      base.dataset,
      local,
      remote,
      choice: choice,
    );
    final incoming = whole && choice != null
        ? (choice == SyncChoice.local ? local : remote)
        : result.dataset;
    if (incoming == null) {
      _conflict = CloudConflict(
        local: local,
        other: remote,
        merge: result,
        guest: false,
        revision: fetched.revision,
      );
      _notice = '有同步冲突，请在账号页选择保留的版本。';
      return;
    }

    // Check the encoded size before any local replacement.
    if (!incoming.sameData(remote)) incoming.backup.encode();
    if (choice == SyncChoice.local) await journal.saveOtherVersion(remote);
    if (!_safeRoute || !_foreground) return;
    if (!incoming.sameData(local) || fetched.revision != base.revision) {
      _setApplying(true);
      try {
        await journal.apply(
          files,
          previous: local,
          incoming: incoming.sameData(local) ? local : incoming,
          fetched: (revision: fetched.revision, dataset: remote),
        );
      } finally {
        _setApplying(false);
      }
    }
    _conflict = null;
    if (!incoming.sameData(remote)) {
      await journal.startUpload(fetched.revision, incoming);
      if (!await _resumeUpload(session, journal)) {
        _notice = '另一台设备刚更新了数据，将在下次同步时重新合并。';
        return;
      }
    }
    _lastSync = DateTime.now();
    _notice = null;
  }

  Future<bool> _resumeUpload(CloudSession session, SyncJournal journal) async {
    final upload = await journal.pendingUpload();
    if (upload == null) return true;
    final revision = await _api.upload(
      session,
      expectedRevision: upload.revision,
      uploadId: upload.id,
      bytes: upload.bytes,
    );
    await journal.finishUpload(upload, revision);
    return revision != null;
  }

  Future<void> importGuest({SyncChoice? choice, bool whole = false}) async {
    await _perform(() async {
      final journal = _journal;
      if (journal == null || _guestImported || !_safeRoute) return;
      if (_conflict case CloudConflict(guest: false)) {
        _notice = '请先处理当前的云同步冲突。';
        return;
      }
      final files = await _activeBackup();
      final local = SyncDataset(await files.snapshot());
      final guest = SyncDataset(await (await _guestBackup()).snapshot());
      final imported = guest.forGuestImport();
      final previous = _conflict;
      if (choice != null &&
          (previous == null ||
              !previous.guest ||
              !previous.local.sameData(local) ||
              !previous.other.sameData(imported))) {
        choice = null;
        whole = false;
      }
      final result = SyncMerge.reconcile(
        SyncDataset.empty,
        local,
        imported,
        choice: choice,
      );
      final incoming = whole && choice != null
          ? (choice == SyncChoice.local ? local : imported)
          : result.dataset;
      if (incoming == null) {
        _conflict = CloudConflict(
          local: local,
          other: imported,
          merge: result,
          guest: true,
        );
        _notice = '本机旧数据与账号数据有冲突，请选择保留的版本。';
        return;
      }
      if (!_safeRoute || !_foreground) return;
      _setApplying(true);
      try {
        if (!incoming.sameData(local)) {
          // The existing backup transaction keeps the pre-import account
          // copy. The original guest dataset remains in its own directory.
          incoming.backup.encode();
          await files.restore(
            incoming.backup,
            expected: local.backup,
            committedMarker: journal.beforePull,
          );
        }
        await journal.markGuestImported();
        _guestImported = true;
        _conflict = null;
        _notice = guest.sameData(SyncDataset.empty)
            ? '本机没有待导入的 V1.0 数据。'
            : '本机 V1.0 数据已复制到当前账号。';
      } finally {
        _setApplying(false);
      }
    });
    if (_guestImported) await autoSync();
  }

  void cancelGuestImport() {
    if (_conflict?.guest ?? false) {
      _conflict = null;
      _notice = '已取消导入。';
      notifyListeners();
    }
  }

  void _setApplying(bool value) {
    _applying = value;
    notifyListeners();
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_working) return;
    _working = true;
    notifyListeners();
    try {
      await action();
    } on SyncApiException catch (error) {
      if (error.code == 'session_expired') _expired = true;
      _notice = error.message;
    } on LocalBackupChanged {
      _notice = '本机数据刚有更新，稍后将按最新内容同步。';
    } on TimeoutException {
      _notice = '同步超时。本机修改已保留，联网后可重试。';
    } on SocketException {
      _notice = '暂时连不上云端。本机修改已保留。';
    } on HandshakeException {
      _notice = '无法验证云同步服务的 HTTPS 证书。';
    } on FileSystemException {
      _notice = '无法读写本机同步文件。请检查磁盘空间或重启后再试。';
    } on FormatException catch (error) {
      _notice = error.message.startsWith(RegExp(r'[\u4e00-\u9fff]'))
          ? error.message
          : '数据或云端响应未通过校验，当前副本已保留。';
    } catch (_) {
      _notice = '操作未完成。请检查本机数据或重启后再试。';
    } finally {
      _working = false;
      notifyListeners();
    }
  }
}
