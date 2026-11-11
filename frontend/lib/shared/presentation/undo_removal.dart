import 'package:flutter/material.dart';

/// Undo restores a single original entity through its insert-only repository.
void offerRemovalUndo(
  BuildContext context,
  String title,
  Future<void> Function() restore,
) {
  final messenger = ScaffoldMessenger.of(context);
  var restoring = false;
  Future<void> undo() async {
    if (restoring) return;
    restoring = true;
    try {
      await restore();
      if (messenger.mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('已撤销删除')));
      }
    } catch (_) {
      restoring = false;
      if (messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('恢复失败。请检查原关联记录、ID 或存储后重试。'),
            action: SnackBarAction(label: '重试', onPressed: undo),
          ),
        );
      }
    }
  }

  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 8),
      content: Text('已删除「$title」，本次会话可撤销'),
      action: SnackBarAction(label: '撤销', onPressed: undo),
    ),
  );
}
