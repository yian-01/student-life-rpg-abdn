import 'package:flutter/material.dart';

import 'app_routes.dart';
import 'cloud/cloud_page.dart';

/// Searchable real navigation commands; no synthetic records or actions.
Future<String?> showCampusCommands(BuildContext context) => showDialog<String>(
  context: context,
  builder: (_) => const _CampusCommands(),
);

class _CampusCommands extends StatefulWidget {
  const _CampusCommands();
  @override
  State<_CampusCommands> createState() => _CampusCommandsState();
}

class _CampusCommandsState extends State<_CampusCommands> {
  String _query = '';
  static const _commands = [
    (Icons.search_rounded, '搜索全部记录', '课程 待办 账目 搜索', AppRoutes.search),
    (Icons.calendar_month_outlined, '打开课表', '日程 安排 周课表', AppRoutes.schedule),
    (
      Icons.account_balance_wallet_outlined,
      '打开生活账本',
      '记账 收入 支出 预算',
      AppRoutes.finance,
    ),
    (Icons.checklist_rounded, '待办清单', '任务 清单', AppRoutes.todo),
    (Icons.school_outlined, '学业档案', 'GPA 成绩 绩点', AppRoutes.gpa),
    (Icons.timer_outlined, '开始专注', '专注 计时 番茄钟', AppRoutes.focus),
    (Icons.auto_stories_outlined, '学期与课程', '学期 导入 课程 管理', AppRoutes.academic),
    (Icons.cloud_outlined, '账号与云同步', '登录 退出 注册 同步', CloudPage.route),
    (Icons.backup_outlined, '备份与恢复', '导出 恢复 备份', AppRoutes.backup),
  ];

  @override
  Widget build(BuildContext context) {
    final matches = _commands
        .where(
          (command) => '${command.$2} ${command.$3}'.toLowerCase().contains(
            _query.trim().toLowerCase(),
          ),
        )
        .toList();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 570),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  labelText: '搜索功能',
                  hintText: '课表、记账、GPA…',
                ),
                onChanged: (value) => setState(() => _query = value),
                onSubmitted: (_) {
                  if (matches.isNotEmpty)
                    Navigator.of(context).pop(matches.first.$4);
                },
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: matches.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('没有匹配的功能，请换个关键词。'),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        for (final command in matches)
                          ListTile(
                            leading: Icon(command.$1),
                            title: Text(command.$2),
                            trailing: const Icon(
                              Icons.north_east_rounded,
                              size: 16,
                            ),
                            onTap: () => Navigator.of(context).pop(command.$4),
                          ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '输入筛选 · 回车打开',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
