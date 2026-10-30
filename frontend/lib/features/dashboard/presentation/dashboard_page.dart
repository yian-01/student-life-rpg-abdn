import 'package:flutter/material.dart';

import '../../../app/app_data.dart';
import '../../../app/app_routes.dart';
import '../../finance/finance_memory_scope.dart';
import '../../finance/models/monthly_finance_summary.dart';
import '../../gpa/models/gpa_result.dart';
import '../models/section_state.dart';
import '../models/task_metrics.dart';
import 'dashboard_layout.dart';
import 'dashboard_section_view.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  SectionState<TaskMetrics> _tasks = const SectionState.loading();
  SectionState<GpaResult> _gpa = const SectionState.loading();
  SectionState<MonthlyFinanceSummary> _finance = const SectionState.loading();
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _tasks = const SectionState.loading();
      _gpa = const SectionState.loading();
      _finance = const SectionState.loading();
    });
    final now = DateTime.now();
    // Independent sections: a disk failure must not hide academic/finance data.
    await Future.wait([
      _read(
        () async {
          final tasks = await (await AppData.tasks()).list();
          return computeTaskMetrics(
            tasks: tasks.map(
              (task) => (
                id: task.id,
                isCompleted: task.isCompleted,
                scheduledRange: task.scheduledRange,
                dueAt: task.dueAt,
              ),
            ),
            today: now,
          );
        },
        (state) => _tasks = state,
        request,
      ),
      _read(
        () => AppRoutes.gpaComposition.loadGpa(),
        (state) => _gpa = state,
        request,
      ),
      _read(
        () => FinanceMemoryScope.shared.service.loadMonth(
          DateTime(now.year, now.month),
        ),
        (state) => _finance = state,
        request,
      ),
    ]);
  }

  Future<void> _read<T>(
    Future<T> Function() load,
    void Function(SectionState<T>) update,
    int request,
  ) async {
    SectionState<T> result;
    try {
      result = SectionState.ready(await load());
    } catch (error) {
      result = SectionState.failure(error);
    }
    if (mounted && request == _request) setState(() => update(result));
  }

  Future<void> _open(String route) async {
    await Navigator.of(context).pushNamed(route);
    if (mounted) await _load();
  }

  Widget _link(String route) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextButton.icon(
      onPressed: () => _open(route),
      icon: const Icon(Icons.arrow_forward),
      label: const Text('进入模块'),
    ),
  );

  String _money(int minor) => '¥${(minor / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Dashboard'),
      actions: [
        IconButton(
          tooltip: '刷新总览',
          onPressed: _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: DashboardSectionLayout(
        sections: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('生活总览', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                const Text('任务保存在本机；学业和财务为内存演示，重启后重置。'),
              ],
            ),
          ),
          DashboardSectionView<TaskMetrics>(
            title: '任务进度',
            state: _tasks,
            onRetry: _load,
            contentBuilder: (context, data) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.totalCount == 0
                      ? '暂无任务'
                      : '已完成 ${data.completedCount} / ${data.totalCount}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                if (data.completionRate != null)
                  LinearProgressIndicator(value: data.completionRate),
                const SizedBox(height: 8),
                Text('今日待办 ${data.todayPendingCount} 项'),
                _link(AppRoutes.schedule),
              ],
            ),
          ),
          DashboardSectionView<GpaResult>(
            title: '学业 · 内存演示',
            state: _gpa,
            onRetry: _load,
            contentBuilder: (context, data) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.value == null
                      ? '暂无已评分课程'
                      : 'GPA ${data.value!.toStringAsFixed(2)} / ${AppRoutes.gpaComposition.scoreScaleMax}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '已评分 ${data.gradedCourseCount} 门 · 待评分 ${data.missingCount} 门',
                ),
                const Text('全部学期 · 合成课程，非学校官方绩点规则'),
                _link(AppRoutes.gpa),
              ],
            ),
          ),
          DashboardSectionView<MonthlyFinanceSummary>(
            title: '本月收支 · 内存演示',
            state: _finance,
            onRetry: _load,
            contentBuilder: (context, data) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${data.month.year} / ${data.month.month}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text('收入  ${_money(data.incomeMinor)}'),
                Text('支出  ${_money(data.expenseMinor)}'),
                Text('结余  ${_money(data.balanceMinor)}'),
                if (data.remainingBudgetMinor != null)
                  Text('演示预算剩余  ${_money(data.remainingBudgetMinor!)}'),
                _link(AppRoutes.finance),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
