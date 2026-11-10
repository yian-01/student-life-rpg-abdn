import 'package:flutter/material.dart';

import '../../../app/app_data.dart';
import '../../../app/app_routes.dart';
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
        () async => (await AppData.campus()).gpa.loadGpa(),
        (state) => _gpa = state,
        request,
      ),
      _read(
        () async => (await AppData.campus()).financeService.loadMonth(
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
      title: const Text('生活总览'),
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
        header: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('生活总览', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              const Text('任务、学业与账本保存在本机。'),
            ],
          ),
        ),
        sections: [
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
                const SizedBox(height: 4),
                Text(
                  '仅统计未完成、且当天有安排或当天截止的任务；同时满足两项时按任务去重。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                _link(AppRoutes.schedule),
              ],
            ),
          ),
          const DashboardSectionView<void>(
            title: '作业与考试',
            description: '作业截止和当天考试由学业模块提供；该接口尚未接入，因此这里不显示数据，也不计入任务指标。',
            state: SectionState<void>.notIntegrated(),
          ),
          DashboardSectionView<GpaResult>(
            title: '学业',
            state: _gpa,
            onRetry: _load,
            contentBuilder: (context, data) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.value == null
                      ? '暂无已评分课程'
                      : 'GPA ${data.value!.toStringAsFixed(2)} / 4.0',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '已评分 ${data.gradedCourseCount} 门 · 待评分 ${data.missingCount} 门',
                ),
                const Text('全部学期 · 自定义 4.0 规则，非学校官方换算'),
                _link(AppRoutes.gpa),
              ],
            ),
          ),
          DashboardSectionView<MonthlyFinanceSummary>(
            title: '本月收支',
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
                // 未设置预算与预算为 0 分开显示，避免把 null 显示成 0。
                Text(
                  data.remainingBudgetMinor == null
                      ? '预算剩余  未设置'
                      : '预算剩余  ${_money(data.remainingBudgetMinor!)}',
                ),
                if (data.incomeMinor == 0 && data.expenseMinor == 0)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('本月暂无收支记录（收支为 0）'),
                  ),
                _link(AppRoutes.finance),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
