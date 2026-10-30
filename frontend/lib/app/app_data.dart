import 'package:path_provider/path_provider.dart';

import '../features/schedule/repositories/file_task_repository.dart';
import '../features/schedule/repositories/task_repository.dart';
import '../shared/storage/json_document_store.dart';

abstract final class AppData {
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
