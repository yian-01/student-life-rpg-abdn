import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../features/academic/presentation/assignment_exam_page.dart';
import '../features/finance/presentation/receipt_fields.dart';
import 'app_data.dart';
import 'cloud/cloud_scope.dart';
import 'data/full_backup.dart';
import 'module_body.dart';

class FullBackupPage extends StatefulWidget {
  const FullBackupPage({super.key});

  @override
  State<FullBackupPage> createState() => _FullBackupPageState();
}

class _FullBackupPageState extends State<FullBackupPage> {
  bool _busy = false;
  String? _message;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      final message = switch (error) {
        FormatException() => error.message,
        StateError() => error.message,
        _ => '操作失败，请检查文件权限和可用空间。',
      };
      setState(() => _message = message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() => _run(() async {
    final backup = await (await AppData.backup()).snapshot();
    final now = backup.createdAt;
    final stamp =
        '${now.year}-${now.month}-${now.day}-${now.hour}${now.minute.toString().padLeft(2, '0')}';
    final saved = await FilePicker.platform.saveFile(
      dialogTitle: '保存 Student Life 备份',
      fileName: 'student-life-$stamp.json',
      bytes: backup.encode(),
      lockParentWindow: true,
    );
    if (mounted && saved != null) setState(() => _message = '完整备份已导出。');
  });

  Future<void> _restore() => _run(() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: false,
      lockParentWindow: true,
    );
    if (picked == null || !mounted) return;
    final path = picked.files.single.path;
    if (path == null) throw const FormatException('无法读取所选文件。');
    final backup = FullBackup.decode(await readBackupFile(File(path)));
    for (final receipt in backup.receipts) {
      await validateReceiptImage(base64Decode(receipt));
    }
    if (!mounted) return;
    const labels = {
      'tasks': '任务',
      'semesters': '学期',
      'courses': '课程（含调停课）',
      'assignments': '作业',
      'exams': '考试',
      'events': '事件',
      'categories': '账目分类',
      'records': '收支记录',
      'budgets': '分类预算',
      'receipts': '票据图片',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('用此备份替换本机数据？'),
        scrollable: true,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('备份时间 · ${formatLocalDateTime(backup.createdAt.toLocal())}'),
            for (final item in labels.entries)
              Text('${item.value} · ${backup.counts[item.key] ?? 0}'),
            const SizedBox(height: 12),
            const Text('确认后将整体替换本机记录，替换前的数据会另存到应用目录。'),
            if (CloudScope.maybeOf(context)?.session != null)
              const Text('这些更改也会在下次同步时发送给同一账号的其他设备。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认替换'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    await (await AppData.backup()).restore(backup);
    if (mounted) setState(() => _message = '数据已恢复。返回各模块即可查看。');
  });

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: ModuleBody(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('用一个文件在设备间手动搬迁任务、学业、日程和账本。备份包含票据图片，请妥善保存。'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.save_alt),
              label: const Text('导出完整备份'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _restore,
              icon: const Icon(Icons.restore),
              label: const Text('从备份文件恢复'),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_message!, semanticsLabel: _message),
              ),
          ],
        ),
      ),
    ),
  );
}
