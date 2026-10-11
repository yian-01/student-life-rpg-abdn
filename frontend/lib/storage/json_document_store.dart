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
    final backup = File('$path.bak');

    // 崩溃恢复：主文件缺失但备份有效时，先从备份恢复
    if (!await file.exists() && await backup.exists()) {
      final len = await backup.length();
      if (len > 0) {
        await backup.rename(path);
      }
    }

    if (!await file.exists()) return null;
    try {
      return await file.readAsString();
    } on FileSystemException catch (e) {
      throw JsonDocumentStoreIOException('读取 $path 失败: $e');
    }
  }

  Future<void> writeDocument(String path, String content) async {
    final file = File(path);
    final backup = File('$path.bak');
    final tmp = File('$path.tmp');

    try {
      // 若上次写入中途崩溃，先恢复备份，再执行本次写入
      if (!await file.exists() && await backup.exists()) {
        final len = await backup.length();
        if (len > 0) {
          await backup.rename(path);
        }
      }

      // 先写临时文件并 flush
      await tmp.writeAsString(content, flush: true);

      // 主文件存在时，把旧内容转为备份
      if (await file.exists()) {
        if (await backup.exists()) {
          await backup.delete();
        }
        await file.rename('$path.bak');
      }

      // 临时文件替换主文件
      await tmp.rename(path);
    } catch (e) {
      // 失败恢复：主文件丢失且备份有效时，从备份恢复
      if (!await file.exists() && await backup.exists()) {
        final len = await backup.length();
        if (len > 0) {
          await backup.rename(path);
        }
      }
      throw JsonDocumentStoreIOException('写入 $path 失败: $e');
    } finally {
      if (await tmp.exists()) {
        await tmp.delete();
      }
    }
  }
}
