import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/finance/models/monthly_finance_summary.dart';
import '../features/gpa/models/gpa_result.dart';
import '../features/schedule/models/task.dart';
import '../shared/models/schedule_item.dart';
import 'app_data.dart';
import 'app_routes.dart';
import 'app_theme.dart';
import 'atmosphere.dart';
import 'cloud/cloud_page.dart';
import 'cloud/cloud_scope.dart';
import 'command_palette.dart';

/// A real-data landing page. Each section can fail and retry independently.
class PlatformHomePage extends StatefulWidget {
  const PlatformHomePage({super.key});

  @override
  State<PlatformHomePage> createState() => _PlatformHomePageState();
}

class _PlatformHomePageState extends State<PlatformHomePage>
    with WidgetsBindingObserver {
  late DateTime _today;
  late Future<List<ScheduleItem>> _courses;
  late Future<List<Task>> _tasks;
  late Future<MonthlyFinanceSummary> _finance;
  late Future<GpaResult> _gpa;
  int? _cloudDataRevision;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _read();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final revision = CloudScope.maybeOf(context)?.dataRevision;
    if (_cloudDataRevision != null && revision != _cloudDataRevision) {
      _read();
    }
    _cloudDataRevision = revision;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(_read);
  }

  void _read() {
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _courses = AppData.campus().then((data) async {
      final rows = await data.courseOccurrences(_today);
      return rows..sort((a, b) => a.range.start.compareTo(b.range.start));
    });
    _tasks = AppData.tasks().then((repository) async {
      final rows = (await repository.list())
          .where((task) => !task.isCompleted)
          .toList();
      rows.sort((a, b) {
        final priority = b.priority.index.compareTo(a.priority.index);
        if (priority != 0) return priority;
        return (a.dueAt ?? DateTime(9999)).compareTo(b.dueAt ?? DateTime(9999));
      });
      return rows;
    });
    _finance = AppData.campus().then(
      (data) => data.financeService.loadMonth(DateTime(now.year, now.month)),
    );
    _gpa = AppData.campus().then((data) => data.gpa.loadGpa());
    // Observe errors before lazy, offscreen sections attach their builders.
    _courses.ignore();
    _tasks.ignore();
    _finance.ignore();
    _gpa.ignore();
  }

  Future<void> _refresh() async {
    setState(_read);
    // All errors are rendered by their own section, without hiding other data.
    await Future.wait<Object?>([
      _courses.then<Object?>((v) => v, onError: (_) => null),
      _tasks.then<Object?>((v) => v, onError: (_) => null),
      _finance.then<Object?>((v) => v, onError: (_) => null),
      _gpa.then<Object?>((v) => v, onError: (_) => null),
    ]);
  }

  Future<void> _open(String route) async {
    await Navigator.of(context).pushNamed(route);
    if (mounted) setState(_read);
  }

  Future<void> _commands() async {
    final route = await showCampusCommands(context);
    if (route != null && mounted) {
      await _open(route);
    }
  }

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cloud = CloudScope.maybeOf(context);
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final hour = DateTime.now().hour;
    final greeting = hour < 11
        ? '早上好'
        : hour < 18
        ? '下午好'
        : '晚上好';
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _commands,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _commands,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppTheme.accent, AppTheme.cyan],
                          ),
                          boxShadow: const [
                            BoxShadow(color: Color(0x22CAEF78), blurRadius: 24),
                          ],
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.sailing_rounded,
                          color: AppTheme.background,
                          size: 25,
                        ),
                      ),
                      const SizedBox(width: 11),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '课屿',
                              style: TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                              ),
                            ),
                            Text(
                              '让校园生活，有条不紊',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF70838A),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: '搜索功能 · Ctrl/⌘ K',
                        onPressed: _commands,
                        icon: const Icon(Icons.search_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '$greeting，今天也从容一点。',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_today.month}月${_today.day}日 · 星期${weekdays[_today.weekday - 1]}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  _hero(),
                  const SizedBox(height: 22),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final count = constraints.maxWidth < 320 ? 2 : 4;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final action in [
                            (
                              Icons.calendar_month_outlined,
                              '课程管理',
                              AppRoutes.academic,
                              AppTheme.cyan,
                            ),
                            (
                              Icons.checklist_rounded,
                              '待办清单',
                              AppRoutes.todo,
                              AppTheme.accent,
                            ),
                            (
                              Icons.timer_outlined,
                              '专注时刻',
                              AppRoutes.focus,
                              const Color(0xFFF0C58A),
                            ),
                            (
                              Icons.auto_graph_rounded,
                              '学业档案',
                              AppRoutes.gpa,
                              const Color(0xFFC8B4F7),
                            ),
                          ])
                            SizedBox(
                              width:
                                  (constraints.maxWidth - (count - 1) * 12) /
                                  count,
                              child: GlassSurface(
                                radius: 18,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                  horizontal: 4,
                                ),
                                onTap: () => _open(action.$3),
                                child: Column(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: action.$4.withValues(
                                        alpha: .1,
                                      ),
                                      foregroundColor: action.$4,
                                      child: Icon(action.$1, size: 22),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      action.$2,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 26),
                  _heading('生活一览', '详细统计', AppRoutes.dashboard),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cards = [
                        _metric<MonthlyFinanceSummary>(
                          future: _finance,
                          icon: Icons.account_balance_wallet_outlined,
                          title: '${_today.month}月支出',
                          route: AppRoutes.finance,
                          content: (data) => [
                            Text(
                              '¥ ${(data.expenseMinor / 100).toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '收入 ¥ ${(data.incomeMinor / 100).toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        _metric<GpaResult>(
                          future: _gpa,
                          icon: Icons.school_outlined,
                          title: '累计 GPA',
                          route: AppRoutes.gpa,
                          content: (data) => [
                            Text(
                              data.value?.toStringAsFixed(2) ?? '—',
                              style: const TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              data.value == null
                                  ? '添加课程，开启学业记录'
                                  : '5.0 制 · 已评分 ${data.gradedCourseCount} 门',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ];
                      if (constraints.maxWidth < 300) {
                        return Column(
                          children: [
                            cards[0],
                            const SizedBox(height: 12),
                            cards[1],
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: cards[0]),
                          const SizedBox(width: 12),
                          Expanded(child: cards[1]),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 25),
                  _heading('今日课程', '查看课表', AppRoutes.schedule),
                  const SizedBox(height: 12),
                  _surface(
                    child: _section<List<ScheduleItem>>(
                      _courses,
                      (rows) => rows.isEmpty
                          ? _empty(
                              Icons.wb_sunny_outlined,
                              '今天没有课程安排',
                              '留一点时间，做自己喜欢的事。',
                              '添加课程',
                              AppRoutes.academic,
                            )
                          : Column(
                              children: [
                                for (final row in rows) _courseRow(row),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 25),
                  _heading('待办事项', '查看全部', AppRoutes.todo),
                  const SizedBox(height: 12),
                  _surface(
                    child: _section<List<Task>>(
                      _tasks,
                      (rows) => rows.isEmpty
                          ? _empty(
                              Icons.task_alt_rounded,
                              '暂时没有未完成事项',
                              '把灵感和计划，收进你的清单。',
                              '新建待办',
                              AppRoutes.todo,
                            )
                          : Column(
                              children: [
                                for (final task in rows.take(3))
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      Icons.radio_button_unchecked,
                                      color: task.priority == TaskPriority.high
                                          ? const Color(0xFFC47B4B)
                                          : AppTheme.accent,
                                    ),
                                    title: Text(
                                      task.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      task.dueAt == null
                                          ? '未设置截止时间'
                                          : '${task.dueAt!.month}月${task.dueAt!.day}日 ${_time(task.dueAt!)} 截止',
                                    ),
                                    trailing: const Icon(
                                      Icons.chevron_right_rounded,
                                    ),
                                    onTap: () => _open(AppRoutes.todo),
                                  ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _surface(
                    color: const Color(0xD4152528),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.cottage_outlined, size: 29),
                      title: const Text(
                        '我的小小空间',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text('忙碌之外，回到你的校园卧室'),
                      trailing: const Icon(
                        Icons.arrow_forward_rounded,
                        size: 20,
                      ),
                      onTap: () => _open(AppRoutes.bedroom),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (cloud != null)
                    ListenableBuilder(
                      listenable: cloud,
                      builder: (context, _) => TextButton.icon(
                        onPressed: () => _open(CloudPage.route),
                        icon: Icon(
                          cloud.session == null
                              ? Icons.cloud_outlined
                              : Icons.manage_accounts_outlined,
                          size: 17,
                        ),
                        label: Text(
                          cloud.session == null
                              ? '登录账号，开启云端同步'
                              : '账号与云同步 · 查看状态',
                        ),
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

  Widget _hero() => SurfaceReveal(
    child: GlassSurface(
      padding: EdgeInsets.zero,
      radius: 26,
      blur: true,
      tint: const Color(0xD91A2728),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 650;
            return Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF233D31).withValues(alpha: .6),
                          const Color(0xFF17212B).withValues(alpha: .5),
                          const Color(0xFF101921),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: wide ? 18 : -55,
                  top: wide ? -26 : 22,
                  width: wide ? 370 : 230,
                  height: wide ? 320 : 230,
                  child: Opacity(
                    opacity: wide ? 1 : .62,
                    child: const OrbitalScene(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.blur_on_rounded,
                            color: AppTheme.accent,
                            size: 17,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'YOUR CAMPUS, IN ORBIT',
                              style: TextStyle(
                                fontSize: 9,
                                letterSpacing: 1.8,
                                color: AppTheme.cyan,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '把生活，',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          height: 1.28,
                          letterSpacing: -1,
                        ),
                      ),
                      const Text(
                        '调到你的节奏。',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          height: 1.28,
                          letterSpacing: -1,
                          color: AppTheme.accent,
                        ),
                      ),
                      const SizedBox(height: 9),
                      const Text(
                        '学习 · 计划 · 收支，一屿掌握。',
                        style: TextStyle(color: AppTheme.muted, fontSize: 12),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 14,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: () => _open(AppRoutes.today),
                            icon: const Icon(
                              Icons.north_east_rounded,
                              size: 17,
                            ),
                            label: const Text('查看今日计划'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(48, 44),
                            ),
                          ),
                          FutureBuilder<List<ScheduleItem>>(
                            future: _courses,
                            builder: (context, value) => Text(
                              value.hasError
                                  ? '课程读取失败'
                                  : value.hasData
                                  ? '今日课程 / ${value.data!.length} 门'
                                  : '正在读取课程',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.muted,
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
      ),
    ),
  );

  Widget _heading(String title, String action, String route) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      TextButton(onPressed: () => _open(route), child: Text(action)),
    ],
  );

  Widget _surface({required Widget child, Color? color}) => SurfaceReveal(
    order: 2,
    child: GlassSurface(tint: color, child: child),
  );

  Widget _section<T>(Future<T> future, Widget Function(T) render) =>
      FutureBuilder<T>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('暂时无法读取'),
                TextButton(
                  onPressed: () => setState(_read),
                  child: const Text('重新读取'),
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return render(snapshot.data as T);
        },
      );

  Widget _metric<T>({
    required Future<T> future,
    required IconData icon,
    required String title,
    required String route,
    required List<Widget> Function(T) content,
  }) => _surface(
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _open(route),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.accent, size: 23),
          const SizedBox(height: 11),
          Text(title, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 7),
          _section<T>(
            future,
            (data) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: content(data),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _empty(
    IconData icon,
    String title,
    String subtitle,
    String action,
    String route,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      children: [
        Icon(icon, size: 32, color: AppTheme.cyan),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 5),
        TextButton(onPressed: () => _open(route), child: Text(action)),
      ],
    ),
  );

  Widget _courseRow(ScheduleItem row) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 53,
          child: Column(
            children: [
              Text(
                _time(row.range.start),
                style: const TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                _time(row.range.end),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Container(
          width: 3,
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.accent,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                row.location?.isNotEmpty == true ? row.location! : '未设置上课地点',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
