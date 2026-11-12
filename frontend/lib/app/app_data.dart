import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'data/full_backup.dart';
import 'data/campus_data.dart';
import 'data/campus_store.dart';

import '../features/schedule/repositories/file_task_repository.dart';
import '../features/schedule/repositories/task_repository.dart';
import '../features/schedule/services/focus_timer.dart';
import '../shared/storage/json_document_store.dart';

abstract final class AppData {
  static final focusTimer = FocusTimer();
  static Future<Directory>? _root;
  static Future<Directory>? _guest;
  static Directory? _accountDirectory;

  static Future<Directory> rootDirectory() =>
      _root ??= _openDirectory().catchError((Object error) {
        _root = null;
        throw error;
      });

  static void switchDirectory(Directory? accountDirectory) {
    _accountDirectory = accountDirectory;
    _campus = null;
    _tasks = null;
    focusTimer.configure(const Duration(minutes: 25));
  }

  static Future<Directory> directory() async =>
      _accountDirectory ?? await _guestDirectory();

  static Future<Directory> _guestDirectory() =>
      _guest ??= _recoverGuest().catchError((Object error) {
        _guest = null;
        throw error;
      });

  static Future<Directory> _recoverGuest() async {
    final path = await rootDirectory();
    await FullBackupService.recoverInterrupted(path);
    return path;
  }

  static Future<Directory> _openDirectory() async {
    final path = await getApplicationSupportDirectory();
    await path.create(recursive: true);
    return path;
  }

  static Future<FullBackupService> guestBackup() async {
    final path = await _guestDirectory();
    return FullBackupService(path, _campusAt(path).store, _tasksAt(path));
  }

  static Future<FullBackupService> backup() async {
    final path = await directory();
    final repository = await tasks();
    if (repository is! FileTaskRepository) {
      throw StateError('File-backed task repository required');
    }
    return FullBackupService(path, (await campus()).store, repository);
  }

  static Future<CampusData>? _campus;
  static CampusData? _injectedCampus;

  static Future<CampusData> campus() {
    final injected = _injectedCampus;
    if (injected != null) return Future.value(injected);
    return _campus ??= _openCampus().catchError((Object error) {
      _campus = null;
      throw error;
    });
  }

  static Future<CampusData> _openCampus() async => _campusAt(await directory());

  static CampusData _campusAt(Directory path) => CampusData(
    CampusStore(const FileJsonDocumentStore(), '${path.path}/campus.json'),
  );

  static void useCampusData(CampusData data) {
    _injectedCampus = data;
    _campus = null;
  }

  static Future<TaskRepository>? _tasks;
  static TaskRepository? _injected;

  static Future<TaskRepository> tasks() {
    final injected = _injected;
    if (injected != null) return Future.value(injected);
    return _tasks ??= _openTasks().catchError((Object error) {
      _tasks = null;
      throw error;
    });
  }

  static Future<TaskRepository> _openTasks() async =>
      _tasksAt(await directory());

  static FileTaskRepository _tasksAt(Directory path) => FileTaskRepository(
    const FileJsonDocumentStore(),
    '${path.path}/tasks.json',
  );

  // Tests inject an isolated repository without invoking platform channels.
  static void useTaskRepository(TaskRepository repository) {
    _injected = repository;
    _tasks = null;
  }
}
