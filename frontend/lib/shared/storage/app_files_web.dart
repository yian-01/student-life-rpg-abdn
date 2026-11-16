import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

@JS('studentLifeStart')
external JSPromise<JSString> _start();

@JS('studentLifeFile')
external JSPromise<JSAny?> _fileOperation(
  JSString operation,
  JSString path,
  JSString? destination,
  JSUint8Array? bytes,
);

Future<String?> initializeAppStorage() async {
  try {
    return switch ((await _start().toDart).toDart) {
      'ready' => null,
      'already-open' => '请关闭同一浏览器中的其他 Student Life 页面，然后刷新。',
      _ => '当前浏览器无法访问应用存储。请通过 HTTPS 使用最新版 Edge、Chrome 或 Safari。',
    };
  } catch (_) {
    return '无法打开浏览器存储。请检查站点存储设置后刷新。';
  }
}

Future<Directory> applicationSupportDirectory() async => Directory('/student-life');

class FileSystemException implements Exception {
  const FileSystemException(this.message, [this.path]);
  final String message;
  final String? path;
}

enum FileSystemEntityType { notFound, file, directory }

abstract class FileSystemEntity {
  const FileSystemEntity(this.path);
  final String path;

  static Future<FileSystemEntityType> type(String path) async {
    final result = await _run('type', path) as JSString;
    return switch (result.toDart) {
      'directory' => FileSystemEntityType.directory,
      'file' => FileSystemEntityType.file,
      _ => FileSystemEntityType.notFound,
    };
  }

  static Future<JSAny?> _run(
    String operation,
    String path, {
    String? destination,
    Uint8List? bytes,
  }) async {
    try {
      return await _fileOperation(
        operation.toJS,
        path.toJS,
        destination?.toJS,
        bytes?.toJS,
      ).toDart;
    } catch (_) {
      throw FileSystemException('浏览器存储操作失败。', path);
    }
  }
}

class Directory extends FileSystemEntity {
  const Directory(super.path);

  Future<bool> exists() async =>
      await FileSystemEntity.type(path) == FileSystemEntityType.directory;

  Future<Directory> create({bool recursive = false}) async {
    if (recursive) {
      final separator = path.lastIndexOf('/');
      if (separator > 0) {
        await Directory(path.substring(0, separator)).create(recursive: true);
      }
    }
    await FileSystemEntity._run('mkdir', path);
    return this;
  }

  Future<Directory> rename(String destination) async {
    await FileSystemEntity._run('rename', path, destination: destination);
    return Directory(destination);
  }

  Future<void> delete({bool recursive = false}) async {
    await FileSystemEntity._run('delete', path);
  }

  Stream<FileSystemEntity> list({bool followLinks = true}) async* {
    final entries = await FileSystemEntity._run('list', path) as JSArray<JSString>;
    for (final entry in entries.toDart) {
      final child = '$path/${entry.toDart}';
      yield await FileSystemEntity.type(child) == FileSystemEntityType.directory
          ? Directory(child)
          : File(child);
    }
  }
}

class File extends FileSystemEntity {
  const File(super.path);

  Future<bool> exists() async =>
      await FileSystemEntity.type(path) == FileSystemEntityType.file;

  Future<void> delete() async {
    await FileSystemEntity._run('delete', path);
  }

  Future<File> rename(String destination) async {
    await FileSystemEntity._run('rename', path, destination: destination);
    return File(destination);
  }

  Future<File> copy(String destination) async {
    await FileSystemEntity._run('copy', path, destination: destination);
    return File(destination);
  }

  Future<Uint8List> readAsBytes() async {
    final bytes = await FileSystemEntity._run('read', path) as JSUint8Array;
    return bytes.toDart;
  }

  Future<int> length() async => (await readAsBytes()).length;

  Stream<List<int>> openRead([int start = 0, int? end]) async* {
    final bytes = await readAsBytes();
    yield Uint8List.sublistView(bytes, start, math.min(end ?? bytes.length, bytes.length));
  }

  Future<String> readAsString() async => utf8.decode(await readAsBytes());

  Future<File> writeAsString(String contents, {bool flush = false}) =>
      writeAsBytes(utf8.encode(contents), flush: flush);

  Future<File> writeAsBytes(List<int> contents, {bool flush = false}) async {
    final bytes = contents is Uint8List ? contents : Uint8List.fromList(contents);
    await FileSystemEntity._run('write', path, bytes: bytes);
    return this;
  }
}
