import 'dart:io';

class JsonDocumentStoreIOException implements Exception {
  final String message;
  JsonDocumentStoreIOException(this.message);

  @override
  String toString() => message;
}

/// 基于本地文件的 JSON 文档存储。
class JsonDocumentStore {
  factory JsonDocumentStore.fromPath(String path) => JsonDocumentStore._();

  JsonDocumentStore._();

  // 冻结契约接口：文件不存在返回 null，不解析内容
  Future<String?> readDocument(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      return await file.readAsString();
    } on FileSystemException catch (e) {
      throw JsonDocumentStoreIOException('读取 $path 失败: $e');
    }
  }

  Future<void> writeDocument(String path, String content) async {
    final file = File(path);
    try {
      await file.writeAsString(content, flush: true);
    } on FileSystemException catch (e) {
      throw JsonDocumentStoreIOException('写入 $path 失败: $e');
    }
  }
}
