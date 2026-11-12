import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/full_backup.dart';
import 'cloud_scope.dart';
import 'cloud_sync_controller.dart';
import 'sync_dataset.dart';

class CloudPage extends StatefulWidget {
  const CloudPage({super.key});

  static const route = '/account-sync';

  @override
  State<CloudPage> createState() => _CloudPageState();
}

class _CloudPageState extends State<CloudPage> {
  final _form = GlobalKey<FormState>();
  final _server = TextEditingController(
    text: CloudSyncController.configuredOrigin,
  );
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _register = false;

  @override
  void dispose() {
    _server.dispose();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _authenticate(CloudSyncController cloud) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final password = _password.text;
    _password.clear();
    FocusScope.of(context).unfocus();
    await cloud.signIn(
      server: cloud.session?.origin.toString() ?? _server.text,
      email: cloud.session?.email ?? _email.text,
      password: password,
      register: cloud.session == null && _register,
      code: _code.text.trim(),
    );
  }

  Future<bool> _confirm(String title, String detail, String label) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(detail),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(label),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _resolve(
    CloudSyncController cloud,
    CloudConflict conflict,
    SyncChoice choice,
  ) async {
    final whole = conflict.merge.invalidReferences;
    final version = choice == SyncChoice.local
        ? '本机'
        : conflict.guest
        ? 'V1.0 旧数据'
        : '云端';
    if (whole &&
        !await _confirm(
          '保留完整版本？',
          '两边的课程、分类或关联记录无法直接合并。选择后会以「$version」为准，另一版会留有可导出的备份。',
          '使用$version',
        )) {
      return;
    }
    if (!mounted || cloud.conflict != conflict) return;
    if (conflict.guest) {
      await cloud.importGuest(choice: choice, whole: whole);
    } else {
      await cloud.sync(choice: choice, whole: whole);
    }
  }

  Future<void> _download(FullBackup backup, String name) async {
    try {
      final selected = await FilePicker.platform.saveFile(
        dialogTitle: '保存同步备份',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: backup.encode(),
      );
      if (!mounted || selected == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('同步备份已保存。')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法保存同步备份，请换一个位置重试。')));
    }
  }

  Future<void> _downloadSaved(File file, String name) async {
    try {
      final backup = FullBackup.decode(await readBackupFile(file));
      if (mounted) await _download(backup, name);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法读取同步备份。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloud = CloudScope.maybeOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('账号与同步')),
      body: cloud == null
          ? const Center(child: Text('当前环境未启用云同步。'))
          : ListenableBuilder(
              listenable: cloud,
              builder: (context, _) => SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        if (cloud.working) const LinearProgressIndicator(),
                        if (cloud.notice != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(cloud.notice!),
                            ),
                          ),
                        if (cloud.session == null || cloud.expired)
                          _signInForm(cloud)
                        else
                          ..._accountDetails(cloud),
                        if (cloud.session != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: cloud.working
                                  ? null
                                  : () async {
                                      final confirmed = await _confirm(
                                        '退出当前账号？',
                                        '退出后返回本机模式。当前账号的离线修改会保存在独立目录，下次登录同一账号可以继续同步。',
                                        '退出账号',
                                      );
                                      if (confirmed && mounted)
                                        await cloud.signOut();
                                    },
                              child: const Text('退出账号'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _signInForm(CloudSyncController cloud) {
    final active = cloud.session;
    final register = active == null && _register;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            active != null ? '重新登录 ${active.email}' : '在两台设备使用同一账号',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (active == null) ...[
            TextFormField(
              controller: _server,
              enabled: !cloud.working,
              decoration: const InputDecoration(
                labelText: '云同步服务',
                hintText: 'https://sync.example.com',
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              validator: (value) =>
                  value?.trim().isEmpty ?? true ? '请输入服务地址' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _email,
              enabled: !cloud.working,
              decoration: const InputDecoration(labelText: '邮箱'),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              validator: (value) =>
                  value?.trim().isEmpty ?? true ? '请输入邮箱' : null,
            ),
            const SizedBox(height: 10),
          ],
          TextFormField(
            controller: _password,
            enabled: !cloud.working,
            decoration: const InputDecoration(labelText: '密码'),
            obscureText: true,
            autocorrect: false,
            validator: (value) =>
                (value?.runes.length ?? 0) < 12 ? '密码至少需要 12 个字符' : null,
          ),
          if (register) ...[
            const SizedBox(height: 10),
            TextFormField(
              controller: _code,
              enabled: !cloud.working,
              decoration: const InputDecoration(labelText: '注册邀请码（如有）'),
              obscureText: true,
              autocorrect: false,
            ),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: cloud.working ? null : () => _authenticate(cloud),
            child: Text(register ? '注册并登录' : '登录'),
          ),
          if (active == null)
            TextButton(
              onPressed: cloud.working
                  ? null
                  : () => setState(() => _register = !register),
              child: Text(register ? '已有账号，返回登录' : '注册账号'),
            ),
        ],
      ),
    );
  }

  List<Widget> _accountDetails(CloudSyncController cloud) {
    final conflict = cloud.conflict;
    final lastSync = cloud.lastSync;
    final beforePull = cloud.beforePull;
    final otherBackup = cloud.otherConflictBackup;
    return [
      Card(
        child: ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: Text(cloud.session!.email),
          subtitle: Text(
            '${cloud.session!.origin.host}\n'
            '${lastSync == null ? "尚未完成本轮同步" : "上次同步 ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(lastSync))}"}',
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('应用在前台，返回房间或停留在此页时会自动同步。离线编辑会先保存在本机。'),
      ),
      if (conflict == null)
        FilledButton.icon(
          onPressed: cloud.working ? null : () => cloud.sync(),
          icon: const Icon(Icons.sync),
          label: const Text('立即同步'),
        )
      else
        _conflictCard(cloud, conflict),
      if (!cloud.guestImported && conflict == null)
        OutlinedButton.icon(
          onPressed: cloud.working
              ? null
              : () async {
                  final confirmed = await _confirm(
                    '导入本机 V1.0 数据？',
                    '本机模式的数据将复制到当前账号并参与同步。原来的本机数据会保留。',
                    '导入到当前账号',
                  );
                  if (confirmed && mounted) await cloud.importGuest();
                },
          icon: const Icon(Icons.drive_folder_upload_outlined),
          label: const Text('导入本机 V1.0 数据'),
        ),
      if (beforePull != null && beforePull.existsSync())
        TextButton.icon(
          onPressed: cloud.working
              ? null
              : () => _downloadSaved(beforePull, 'before-cloud-sync.json'),
          icon: const Icon(Icons.download),
          label: const Text('导出上次云端覆盖前的本机备份'),
        ),
      if (otherBackup != null && otherBackup.existsSync())
        TextButton.icon(
          onPressed: cloud.working
              ? null
              : () => _downloadSaved(otherBackup, 'before-cloud-conflict.json'),
          icon: const Icon(Icons.download),
          label: const Text('导出上次保留的云端冲突备份'),
        ),
    ];
  }

  Widget _conflictCard(CloudSyncController cloud, CloudConflict conflict) {
    final whole = conflict.merge.invalidReferences;
    final other = conflict.guest ? 'V1.0 旧数据' : '云端';
    final rows = conflict.merge.conflicts;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              whole ? '关联记录无法合并' : '${rows.length} 条记录需要选择',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(whole ? '请选择保留哪一整份数据。' : '选择冲突记录的版本，其余修改会自动合并。'),
            for (final row in rows.take(8))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_tableNames[row.table] ?? row.table),
                subtitle: Text(
                  '本机：${row.label(row.local)}\n$other：${row.label(row.other)}',
                ),
              ),
            if (rows.length > 8) Text('另有 ${rows.length - 8} 条冲突记录'),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: cloud.working
                      ? null
                      : () => _resolve(cloud, conflict, SyncChoice.local),
                  child: const Text('保留本机版本'),
                ),
                OutlinedButton(
                  onPressed: cloud.working
                      ? null
                      : () => _resolve(cloud, conflict, SyncChoice.other),
                  child: Text('保留$other版本'),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () =>
                      _download(conflict.local.backup, 'sync-local.json'),
                  child: const Text('导出本机版'),
                ),
                TextButton(
                  onPressed: () =>
                      _download(conflict.other.backup, 'sync-other.json'),
                  child: Text('导出$other版'),
                ),
                if (conflict.guest)
                  TextButton(
                    onPressed: cloud.working ? null : cloud.cancelGuestImport,
                    child: const Text('取消导入'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static const _tableNames = {
    'tasks': '任务',
    'semesters': '学期',
    'courses': '课程与绩点',
    'assignments': '作业',
    'exams': '考试',
    'events': '事件',
    'categories': '账目分类',
    'records': '账目与票据',
    'budgets': '预算',
  };
}
