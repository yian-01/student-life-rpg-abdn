import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'data/full_backup.dart';
import 'data/campus_data.dart';
import 'data/campus_store.dart';

import '../features/schedule/repositories/file_task_repository.dart';
import '../features/schedule/repositories/task_repository.dart';
import '../shared/storage/json_document_store.dart';

abstract final class AppData {
  static Future<Directory>? _directory;

  static Future<Directory> directory() =>
      _directory ??= _openDirectory().catchError((Object error) {
        _directory = null;
        throw error;
      });

  static Future<Directory> _openDirectory() async {
    final path = await getApplicationSupportDirectory();
    await path.create(recursive: true);
    await FullBackupService.recoverInterrupted(path);
    return path;
  }

  static Future<FullBackupService> backup() async {
    final path = await directory();
    final repository = await tasks();
    if (repository is! FileTaskRepository)
      throw StateError('File-backed task repository required');
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

  static Future<CampusData> _openCampus() async {
    final path = await directory();
    return CampusData(
      CampusStore(const FileJsonDocumentStore(), '${path.path}/campus.json'),
    );
  }

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

  static Future<TaskRepository> _openTasks() async {
    final path = await directory();
    return FileTaskRepository(
      const FileJsonDocumentStore(),
      '${path.path}/tasks.json',
    );
  }

  // Tests inject an isolated repository without invoking platform channels.
  static void useTaskRepository(TaskRepository repository) {
    _injected = repository;
    _tasks = null;
  }
}
