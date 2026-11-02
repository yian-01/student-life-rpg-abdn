import 'package:path_provider/path_provider.dart';
import 'data/campus_data.dart';
import 'data/campus_store.dart';

import '../features/schedule/repositories/file_task_repository.dart';
import '../features/schedule/repositories/task_repository.dart';
import '../shared/storage/json_document_store.dart';

abstract final class AppData {
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
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return CampusData(
      CampusStore(
        const FileJsonDocumentStore(),
        '${directory.path}/campus.json',
      ),
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
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return FileTaskRepository(
      const FileJsonDocumentStore(),
      '${directory.path}/tasks.json',
    );
  }

  // Tests inject an isolated repository without invoking platform channels.
  static void useTaskRepository(TaskRepository repository) {
    _injected = repository;
    _tasks = null;
  }
}
