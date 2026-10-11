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
    if (!await file.exists() && await _isValid(backup)) {
      // ignore: avoid_print
      print('[JsonDocumentStore] 检测到主文件缺失，正在从备份恢复: $path');
      await backup.rename(path);
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
      if (!await file.exists() && await _isValid(backup)) {
        // ignore: avoid_print
        print('[JsonDocumentStore] 检测到主文件缺失，正在从备份恢复: $path');
        await backup.rename(path);
      }

      // 主文件存在时，检查是否损坏；损坏则禁止直接覆盖
      if (await file.exists()) {
        if (!await _isValid(file)) {
          // 主文件损坏，尝试从备份恢复
          if (await _isValid(backup)) {
            // ignore: avoid_print
            print('[JsonDocumentStore] 检测到主文件损坏，正在从备份恢复: $path');
            await backup.rename(path);
            // 恢复后终止本次保存，要求重试，避免覆盖损坏文件
            throw JsonDocumentStoreIOException(
              '检测到主文件损坏，已从备份恢复，请重新提交保存操作: $path',
            );
          }
          // 备份不存在或无效，无法恢复
          throw JsonDocumentStoreIOException('主文件损坏且无有效备份，拒绝覆盖: $path');
        }
      }

      // 先写临时文件并 flush
      await tmp.writeAsString(content, flush: true);

      // 主文件存在且有效时，把旧内容转为备份
      if (await file.exists()) {
        if (await backup.exists()) {
          await backup.delete();
        }
        await file.rename('$path.bak');
      }

      // 临时文件替换主文件
      await tmp.rename(path);
    } catch (e) {
      // 如果是我们主动抛出的业务异常，直接重新抛出，不包装
      if (e is JsonDocumentStoreIOException) rethrow;

      // 失败恢复：主文件丢失且备份有效时，从备份恢复
      if (!await file.exists() && await _isValid(backup)) {
        // ignore: avoid_print
        print('[JsonDocumentStore] 检测到写入失败，正在从备份恢复: $path');
        await backup.rename(path);
      }
      throw JsonDocumentStoreIOException('写入 $path 失败: $e');
    } finally {
      if (await tmp.exists()) {
        await tmp.delete();
      }
    }
  }

  // 验证文档/备份是否为有效内容：存在且非空（不含纯空白）
  Future<bool> _isValid(File file) async {
    if (!await file.exists()) return false;
    try {
      final length = await file.length();
      if (length == 0) return false;
      final content = await file.readAsString();
      return content.trim().isNotEmpty;
    } on FileSystemException {
      return false;
    }
  }
}
