import 'package:flutter/material.dart';
import 'data/campus_data.dart';

Future<bool> recoverCampusData(BuildContext context, CampusData data) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('重新读取 / 从备份恢复'),
      content: const Text(
        '重新读取学业、事件和账本。损坏时恢复上一有效备份并保留损坏原件。最近一次修改可能不在备份中，恢复后请核对数据。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('恢复'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  try {
    await data.store.recoverFromBackup();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已重新读取，请核对数据。')));
    }
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('恢复失败，文件已保留，请检查备份和权限。')));
    }
    return false;
  }
}
