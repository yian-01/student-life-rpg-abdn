import 'package:flutter/material.dart';

abstract final class GardenRoutes {
  static const study = '/garden/study';
  static const days = '/garden/days';
  static const finance = '/garden/finance';
  static const more = '/garden/more';
  static const assignments = '/assignments';
  static const exams = '/exams';
  static const week = '/week';
  static const statistics = '/finance/statistics';
  static const categories = '/finance/categories';
  static const budgets = '/finance/budgets';
  static const receipts = '/finance/receipts';
  static const hubs = ['/', study, days, finance, more];
  static const names = ['首页', '学业', '日程', '财务', '更多'];
  static const plants = ['cherry', 'maple', 'bush', 'ginkgo', 'bamboo'];
  static const english = ['HOME', 'STUDY', 'DAYS', 'LIVING', 'LITTLE THINGS'];
  static const intros = [
    '今天，也慢慢来。',
    '把好奇心，慢慢养大。',
    '让日子，有自己的节奏。',
    '留一点余裕，给生活。',
    '把生活，过成喜欢的样子。',
  ];
  static const tools = <List<(String, String)>>[
    [],
    [('课程', '/academic'), ('GPA', '/gpa'), ('作业', assignments), ('考试', exams)],
    [('周课表', week), ('待办', '/todo'), ('事件', '/events'), ('日程手账', '/schedule')],
    [
      ('账目', '/finance'),
      ('统计', statistics),
      ('分类', categories),
      ('预算', budgets),
      ('票据', receipts),
    ],
    [
      ('专注计时', '/focus'),
      ('备份与恢复', '/backup'),
      ('我的空间', '/bedroom'),
      ('今日规划', '/today'),
      ('数据概览', '/dashboard'),
      ('校园大厅', '/menu'),
      ('个人空间与好友', '/people'),
    ],
  ];
  static int section(String route) {
    final hub = hubs.indexOf(route);
    if (hub >= 0) return hub;
    for (var i = 1; i < tools.length; i++) {
      if (tools[i].any((tool) => tool.$2 == route)) return i;
    }
    return 4;
  }
}

/// Named pages determine the section; anonymous detail routes keep its context.
class GardenRouteObserver extends NavigatorObserver {
  GardenRouteObserver(this.route, this.popup);
  final ValueNotifier<String> route;
  final ValueNotifier<bool> popup;
  Route<dynamic>? _top;
  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    _top = topRoute;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator?.mounted != true || _top != topRoute) return;
      popup.value = topRoute is PopupRoute;
      if (topRoute is! PopupRoute && topRoute.settings.name != null) {
        route.value = topRoute.settings.name!;
      }
    });
  }
}

class GardenLandingPage extends StatelessWidget {
  const GardenLandingPage({super.key, this.section = 0});
  final int section;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, box) {
        final theme = Theme.of(context);
        if (section == 0) {
          final date = DateTime.now();
          const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
          return Align(
            alignment: const Alignment(0, -.61),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '今天，也慢慢来。',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  '${date.month} 月 ${date.day} 日 · 星期${weekdays[date.weekday - 1]}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          );
        }
        final entries = GardenRoutes.tools[section];
        return Stack(
          children: [
            Positioned(
              left: box.maxWidth * .21,
              top: box.maxHeight * .24,
              width: box.maxWidth * .34,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '0${section + 1} / ${GardenRoutes.english[section]}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    GardenRoutes.names[section],
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    GardenRoutes.intros[section],
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                  ),
                  const SizedBox(height: 42),
                  Wrap(
                    spacing: 18,
                    runSpacing: 18,
                    children: [
                      for (var i = 0; i < entries.length; i++)
                        SizedBox(
                          width: (box.maxWidth * .34 - 18) / 2,
                          child: TextButton(
                            key: ValueKey('garden-tool-${entries[i].$2}'),
                            style: TextButton.styleFrom(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              foregroundColor: theme.colorScheme.onSurface,
                            ),
                            onPressed: () =>
                                Navigator.of(context).pushNamed(entries[i].$2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '0${i + 1}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: .55),
                                  ),
                                ),
                                const SizedBox(width: 11),
                                Flexible(
                                  child: Text(
                                    entries[i].$1,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      letterSpacing: 2,
                                      fontWeight: FontWeight.w300,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}
