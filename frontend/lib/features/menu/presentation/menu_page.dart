import 'package:flutter/material.dart';

import '../../../app/app_routes.dart';
import '../../../app/app_theme.dart';

class MenuPage extends StatelessWidget {
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    const destinations = [
      (
        title: 'Schedule',
        subtitle: '日程与任务',
        detail: '安排今天，记录每一次完成',
        icon: Icons.event_note_outlined,
        route: AppRoutes.schedule,
      ),
      (
        title: 'GPA',
        subtitle: '课程与绩点',
        detail: '查看课程成绩与加权绩点',
        icon: Icons.school_outlined,
        route: AppRoutes.gpa,
      ),
      (
        title: 'Finance',
        subtitle: '收支账本',
        detail: '记录生活开销，查看月度汇总',
        icon: Icons.account_balance_wallet_outlined,
        route: AppRoutes.finance,
      ),
      (
        title: 'Dashboard',
        subtitle: '生活总览',
        detail: '一起查看任务、学业和收支',
        icon: Icons.space_dashboard_outlined,
        route: AppRoutes.dashboard,
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Menu')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'STUDENT LIFE',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppTheme.gold,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '今天，从这里开始',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('选择一本手册，继续你的校园生活。'),
                  const SizedBox(height: 28),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 600 ? 2 : 1;
                      final width =
                          (constraints.maxWidth - (columns - 1) * 16) / columns;
                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          for (final item in destinations)
                            SizedBox(
                              width: width,
                              child: Card(
                                margin: EdgeInsets.zero,
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () => Navigator.of(
                                    context,
                                  ).pushNamed(item.route),
                                  child: Padding(
                                    padding: const EdgeInsets.all(22),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          item.icon,
                                          color: AppTheme.gold,
                                          size: 30,
                                        ),
                                        const SizedBox(height: 20),
                                        Text(
                                          item.title,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleLarge,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          item.subtitle,
                                          style: const TextStyle(
                                            color: AppTheme.gold,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(item.detail),
                                        const SizedBox(height: 16),
                                        const Align(
                                          alignment: Alignment.centerRight,
                                          child: Icon(
                                            Icons.arrow_forward,
                                            size: 20,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
