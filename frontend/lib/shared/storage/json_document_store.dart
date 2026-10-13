import 'dart:io';

/// 存储层抛出的 IO 异常，保留原始错误信息。
class JsonDocumentStoreIOException implements Exception {
  final String message;
  JsonDocumentStoreIOException(this.message);

  @override
  String toString() => message;
}

/// 原始 UTF-8 文档存储接口。
///
/// 职责仅限文件读写：
/// - [readDocument] 文件不存在返回 null；零字节、空白、损坏内容原样返回，
///   由调用方（Repository）判断是否合法。
/// - [writeDocument] 写入时使用临时文件 + flush，再将上一有效主文件保留为
///   `.bak`，最后替换主文件；失败时尽量从 `.bak` 恢复。
///
/// 不做 JSON 解析、schemaVersion/entityType/records 校验——这些由 Repository 负责。
abstract interface class JsonDocumentStore {
  Future<String?> readDocument(String path);

  Future<void> writeDocument(String path, String content);
}

/// 基于本地文件的 [JsonDocumentStore] 实现。
class FileJsonDocumentStore implements JsonDocumentStore {
  const FileJsonDocumentStore();

  @override
  Future<String?> readDocument(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      return await file.readAsString();
    } on FileSystemException catch (e) {
      throw JsonDocumentStoreIOException('读取 $path 失败: $e');
    }
  }

  @override
  Future<void> writeDocument(String path, String content) async {
    final file = File(path);
    final backup = File('$path.bak');
    final tmp = File('$path.tmp');

    try {
      // 1. 写临时文件并 flush
      await tmp.writeAsString(content, flush: true);

      // 2. 主文件存在时，把旧内容转为 .bak（先删旧备份）
      if (await file.exists()) {
        if (await backup.exists()) {
          await backup.delete();
        }
        await file.rename('$path.bak');
      }

      // 3. 临时文件替换主文件
      await tmp.rename(path);
    } catch (e) {
      if (e is JsonDocumentStoreIOException) rethrow;

      // 失败恢复：主文件丢失且备份存在时，从备份恢复
      if (!await file.exists() && await backup.exists()) {
        try {
          await backup.rename(path);
        } on FileSystemException {
          // 恢复失败也不掩盖原始错误
        }
      }
      throw JsonDocumentStoreIOException('写入 $path 失败: $e');
    } finally {
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } on FileSystemException {
          // 清理失败不影响主流程
        }
      }
    }
  }
}
