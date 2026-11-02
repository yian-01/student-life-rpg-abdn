import 'package:flutter/material.dart';
import 'app_data.dart';
import 'data/campus_data.dart';

/// A failed open has retry/recovery, never an in-memory production fallback.
class CampusDataHost extends StatefulWidget {
  const CampusDataHost({super.key, required this.title, required this.builder});
  final String title;
  final Widget Function(BuildContext context, CampusData data) builder;
  @override
  State<CampusDataHost> createState() => _CampusDataHostState();
}

class _CampusDataHostState extends State<CampusDataHost> {
  late Future<CampusData> _future = _open();
  bool _recovering = false;
  String? _error;
  Future<CampusData> _open() async {
    final data = await AppData.campus();
    await data.store.initialize();
    return data;
  }

  Future<void> _recover() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新读取 / 从备份恢复'),
        content: const Text(
          '将重新读取学业、事件和账本数据。主文件损坏时恢复上一有效备份，损坏原件会保留。最近一次修改可能不在备份中，请恢复后核对数据。',
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
    if (confirmed != true || !mounted) return;
    setState(() {
      _recovering = true;
      _error = null;
    });
    try {
      await (await AppData.campus()).store.recoverFromBackup();
      if (mounted) setState(() => _future = _open());
    } catch (_) {
      if (mounted) setState(() => _error = '恢复失败，文件已保留。请检查存储权限及备份。');
    } finally {
      if (mounted) setState(() => _recovering = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CampusData>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasData && !snapshot.hasError) {
        return widget.builder(context, snapshot.data!);
      }
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: snapshot.hasError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error ?? '无法读取本地数据。请重试或从有效备份恢复。',
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: _recovering
                            ? null
                            : () => setState(() => _future = _open()),
                        child: const Text('重试'),
                      ),
                      TextButton(
                        onPressed: _recovering ? null : _recover,
                        child: const Text('从备份恢复'),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      );
    },
  );
}
