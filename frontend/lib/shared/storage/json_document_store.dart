import 'dart:io';

/// 原始 UTF-8 文档存储接口。
///
/// 职责仅限文件读写：
/// - [readDocument] 文件不存在返回 null；零字节、空白、损坏内容原样返回，
///   由调用方（Repository）判断是否合法。
/// - [writeDocument] 写入时使用临时文件 + flush，再将上一有效主文件保留为
///   `.bak`，最后替换主文件；失败时尽量从 `.bak` 恢复。
///
/// 不做 JSON 解析、schemaVersion/entityType/records 校验——这些由 Repository 负责。
/// 文件故障保留原始 [FileSystemException]，不包装为自定义异常。
abstract interface class JsonDocumentStore {
  Future<String?> readDocument(String path);

  Future<void> writeDocument(String path, String content);
}

/// 基于本地文件的 [JsonDocumentStore] 实现。
class FileJsonDocumentStore implements JsonDocumentStore {
  const FileJsonDocumentStore({this.files = const DocumentFileOperations()});

  final DocumentFileOperations files;

  @override
  Future<String?> readDocument(String path) async {
    final file = File(path);
    if (!await files.exists(file)) return null;
    // 文件故障（权限、损坏等）保留原始 FileSystemException，不包装。
    return await files.read(file);
  }

  @override
  Future<void> writeDocument(String path, String content) async {
    final file = File(path);
    final backup = File('$path.bak');
    final tmp = File('$path.tmp');

    try {
      // 1. 写临时文件并 flush
      await files.writeAndFlush(tmp, content);

      // 2. 主文件存在时，把旧内容转为 .bak（先删旧备份）
      if (await files.exists(file)) {
        if (await files.exists(backup)) {
          await files.delete(backup);
        }
        await files.rename(file, '$path.bak');
      }

      // 3. 临时文件替换主文件
      await files.rename(tmp, path);
    } on FileSystemException {
      // 失败恢复：主文件丢失且备份存在时，从备份恢复
      if (!await files.exists(file) && await files.exists(backup)) {
        try {
          await files.copy(backup, path);
        } on FileSystemException {
          // 恢复失败也不掩盖原始错误
        }
      }
      rethrow;
    } finally {
      if (await files.exists(tmp)) {
        try {
          await files.delete(tmp);
        } on FileSystemException {
          // 清理失败不影响主流程
        }
      }
    }
  }
}

/// Injectable file operations; production and fault tests use the same store
/// algorithm. Tests override a single operation while retaining real files.
class DocumentFileOperations {
  const DocumentFileOperations();

  Future<bool> exists(File file) => file.exists();
  Future<String> read(File file) => file.readAsString();
  Future<void> writeAndFlush(File file, String content) async {
    await file.writeAsString(content, flush: true);
  }

  Future<void> rename(File file, String destination) async {
    await file.rename(destination);
  }

  Future<void> copy(File file, String destination) async {
    await file.copy(destination);
  }

  Future<void> delete(File file) async {
    await file.delete();
  }
}
