import '../../../app/module_navigation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_routes.dart';

class MenuPage extends StatelessWidget {
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    const destinations = [
      (
        title: 'Schedule',
        label: '日程与任务',
        detail: '安排时间，完成今天的计划',
        icon: Icons.checklist_rounded,
        color: Color(0xFF5368DC),
        route: AppRoutes.schedule,
      ),
      (
        title: 'GPA',
        label: '课程与绩点',
        detail: '查看课程，记录学业进展',
        icon: Icons.school_outlined,
        color: Color(0xFF448975),
        route: AppRoutes.gpa,
      ),
      (
        title: 'Finance',
        label: '收支账本',
        detail: '记下一笔，了解生活开销',
        icon: Icons.account_balance_wallet_outlined,
        color: Color(0xFFBF8542),
        route: AppRoutes.finance,
      ),
      (
        title: 'Dashboard',
        label: '生活总览',
        detail: '汇总任务、学业与本月收支',
        icon: Icons.pie_chart_outline_rounded,
        color: Color(0xFF8B68B5),
        route: AppRoutes.dashboard,
      ),
    ];
    final now = DateTime.now();
    return Scaffold(
      bottomNavigationBar: const ModuleNavigation(selectedIndex: 0),
      appBar: AppBar(title: const Text('Menu')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Text(
                  '${now.month}月${now.day}日 · ${const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][now.weekday - 1]}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text('我的校园', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                const Text(
                  '学习与生活，一处安排',
                  style: TextStyle(color: Color(0xFF687184)),
                ),
                const SizedBox(height: 24),
                for (final item in destinations) ...[
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pushNamed(item.route),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                color: item.color.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                item.icon,
                                color: item.color,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.label,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  Text(
                                    item.title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    item.detail,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Icon(
                                Icons.chevron_right,
                                size: 20,
                                color: Color(0xFF9AA2B4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.door_back_door_outlined, size: 18),
                    label: const Text('返回卧室'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
