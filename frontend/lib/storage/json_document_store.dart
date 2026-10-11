import 'dart:convert';
import 'dart:io';

/// 存储错误基础类。
sealed class JsonDocumentStoreException implements Exception {
  final String message;
  final Object? cause;

  JsonDocumentStoreException(this.message, [this.cause]);

  @override
  String toString() =>
      '$runtimeType: $message${cause == null ? '' : ' (cause: $cause)'}';
}

/// 文档内容损坏或非法 JSON。
class JsonDocumentCorruptedException extends JsonDocumentStoreException {
  JsonDocumentCorruptedException(super.message, [super.cause]);
}

/// 存储 I/O 失败。
class JsonDocumentStoreIOException extends JsonDocumentStoreException {
  JsonDocumentStoreIOException(super.message, [super.cause]);
}

/// 文档 ID 不合法。
class InvalidDocumentIdException extends JsonDocumentStoreException {
  InvalidDocumentIdException(super.message);
}

/// 基于本地文件系统的 JSON 文档存储。
class JsonDocumentStore {
  final Directory _directory;

  JsonDocumentStore(Directory directory) : _directory = directory;

  factory JsonDocumentStore.fromPath(String path) =>
      JsonDocumentStore(Directory(path));

  String get path => _directory.path;

  Future<void> initialize() async {
    try {
      await _directory.create(recursive: true);
    } on FileSystemException catch (e) {
      throw JsonDocumentStoreIOException('无法创建存储目录 ${_directory.path}', e);
    }
  }

  void _validateId(String id) {
    if (id.isEmpty ||
        id.contains('/') ||
        id.contains('\\') ||
        id.contains('..')) {
      throw InvalidDocumentIdException('非法的文档 ID: $id');
    }
  }

  File _fileFor(String id) => File('${_directory.path}/$id.json');

  Future<void> write(String id, Map<String, dynamic> data) async {
    _validateId(id);
    await initialize();

    final target = _fileFor(id);
    final temp = File(
      '${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );

    try {
      await temp.writeAsString(jsonEncode(data), flush: true);
      if (target.existsSync()) await target.delete();
      await temp.rename(target.path);
    } on JsonUnsupportedObjectError catch (e) {
      throw JsonDocumentCorruptedException('文档 $id 包含无法 JSON 编码的数据', e);
    } on FileSystemException catch (e) {
      throw JsonDocumentStoreIOException('无法写入文档 $id', e);
    }
  }

  Future<Map<String, dynamic>> read(String id) async {
    _validateId(id);
    final file = _fileFor(id);
    try {
      if (!file.existsSync()) {
        throw JsonDocumentCorruptedException('文档 $id 不存在');
      }
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw JsonDocumentCorruptedException('文档 $id 根结构不是 JSON 对象');
      }
      return decoded;
    } on FormatException catch (e) {
      throw JsonDocumentCorruptedException('文档 $id JSON 解析失败', e);
    } on FileSystemException catch (e) {
      throw JsonDocumentStoreIOException('无法读取文档 $id', e);
    }
  }

  Future<void> delete(String id) async {
    _validateId(id);
    final file = _fileFor(id);
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException catch (e) {
      throw JsonDocumentStoreIOException('无法删除文档 $id', e);
    }
  }

  Future<bool> exists(String id) async {
    _validateId(id);
    return _fileFor(id).exists();
  }
}
