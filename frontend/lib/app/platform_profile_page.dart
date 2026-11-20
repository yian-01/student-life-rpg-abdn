import 'package:flutter/material.dart';

import 'app_routes.dart';
import 'app_theme.dart';
import 'atmosphere.dart';
import 'cloud/cloud_page.dart';
import 'cloud/cloud_scope.dart';

class PlatformProfilePage extends StatelessWidget {
  const PlatformProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final cloud = CloudScope.maybeOf(context);
    final content = Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const Text(
            '属于你的校园生活',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text('记录成长，也给自己留一点空间。', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 24),
          SurfaceReveal(child: GlassSurface(
            blur: true, tint: const Color(0xB81B2C2B),
            padding: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: cloud == null
                  ? _link(
                      context,
                      Icons.cloud_outlined,
                      '账号与云同步',
                      '登录、注册及同步设置',
                      CloudPage.route,
                    )
                  : ListenableBuilder(
                      listenable: cloud,
                      builder: (context, _) => _link(
                        context,
                        Icons.cloud_outlined,
                        cloud.session?.email ?? '登录你的课屿账号',
                        cloud.session == null ? '登录后可开启跨设备数据同步' : '管理账号，查看同步状态',
                        CloudPage.route,
                      ),
                    ),
            ),
          )),
          const SizedBox(height: 14),
          Card(
            child: Column(
              children: [
                _link(
                  context,
                  Icons.school_outlined,
                  '学业档案',
                  '成绩、GPA 与学业预测',
                  AppRoutes.gpa,
                ),
                _link(
                  context,
                  Icons.auto_stories_outlined,
                  '学期与课程',
                  '管理课程、学期与导入课表',
                  AppRoutes.academic,
                ),
                _link(
                  context,
                  Icons.event_note_outlined,
                  '事件安排',
                  '校园活动与个人日程',
                  AppRoutes.events,
                ),
                _link(
                  context,
                  Icons.insights_outlined,
                  '生活统计',
                  '任务进度、学业和收支概览',
                  AppRoutes.dashboard,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Column(
              children: [
                _link(
                  context,
                  Icons.cottage_outlined,
                  '我的空间',
                  '回到熟悉的校园卧室',
                  AppRoutes.bedroom,
                ),
                _link(
                  context,
                  Icons.backup_outlined,
                  '备份与恢复',
                  '导出与恢复你的完整数据',
                  AppRoutes.backup,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            '课屿 KEYULIFE\n让校园生活，有条不紊',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.9,
              color: AppTheme.muted,
            ),
          ),
        ],
      ),
    );
    return content;
  }

  Widget _link(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    String route,
  ) => ListTile(
    leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () => Navigator.of(context).pushNamed(route),
  );
}
