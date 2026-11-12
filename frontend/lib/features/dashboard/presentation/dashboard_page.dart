import 'package:flutter/material.dart';

import '../../../app/app_data.dart';
import '../../../app/app_routes.dart';
import '../../academic/models/assignment.dart';
import '../../academic/models/exam.dart';
import '../../finance/models/budget.dart';
import '../../finance/models/monthly_finance_summary.dart';
import '../../gpa/models/gpa_result.dart';
import '../models/section_state.dart';
import '../models/task_metrics.dart';
import 'dashboard_layout.dart';
import 'dashboard_section_view.dart';

/// 当天需要展示的学业事项：当天截止的作业与当天进行的考试。
typedef TodayAgenda = ({List<Assignment> assignments, List<Exam> exams});

/// 财务分区数据：月度汇总、当月分类预算与分类名称。
///
/// 预算是分类粒度的，这里不提供“全局预算剩余”，避免把少数分类的预算
/// 当成全局预算（验收口径 DB07）。
typedef FinanceOverview = ({
  MonthlyFinanceSummary summary,
  List<Budget> budgets,
  Map<String, String> categoryNames,
});

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  SectionState<TaskMetrics> _tasks = const SectionState.loading();
  SectionState<TodayAgenda> _agenda = const SectionState.loading();
  SectionState<GpaResult> _gpa = const SectionState.loading();
  SectionState<FinanceOverview> _finance = const SectionState.loading();
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
      _agenda = const SectionState.loading();
      _gpa = const SectionState.loading();
      _finance = const SectionState.loading();
    });
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final month = DateTime(now.year, now.month);
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
        () async {
          final campus = await AppData.campus();
          final assignments = await campus.assignments.list();
          final exams = await campus.exams.list();
          return (
            // 作业按截止日期归入当天，考试按时间段是否覆盖当天归入。
            assignments:
                assignments
                    .where(
                      (item) =>
                          item.status != AssignmentStatus.submitted &&
                          !item.dueAt.isBefore(today) &&
                          item.dueAt.isBefore(tomorrow),
                    )
                    .toList()
                  ..sort((a, b) => a.dueAt.compareTo(b.dueAt)),
            exams:
                exams
                    .where(
                      (item) =>
                          item.range.start.isBefore(tomorrow) &&
                          item.range.end.isAfter(today),
                    )
                    .toList()
                  ..sort((a, b) => a.range.start.compareTo(b.range.start)),
          );
        },
        (state) => _agenda = state,
        request,
      ),
      _read(
        () async => (await AppData.campus()).gpa.loadGpa(),
        (state) => _gpa = state,
        request,
      ),
      _read(
        () async {
          final campus = await AppData.campus();
          final summary = await campus.financeService.loadMonth(month);
          final budgets = (await campus.budgets.list())
              .where((budget) => budget.month == month)
              .toList();
          final categories = await campus.categories.list();
          return (
            summary: summary,
            budgets: budgets
              ..sort((a, b) => a.categoryId.compareTo(b.categoryId)),
            categoryNames: {
              for (final category in categories) category.id: category.name,
            },
          );
        },
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

  Widget _budgetLine({
    required Budget budget,
    required int spentMinor,
    required String categoryName,
  }) {
    final remaining = budget.amountMinor - spentMinor;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '$categoryName  预算 ${_money(budget.amountMinor)} · '
        '已用 ${_money(spentMinor)} · '
        '${remaining < 0 ? '超支 ${_money(-remaining)}' : '剩余 ${_money(remaining)}'}',
      ),
    );
  }

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
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.today_outlined),
                    label: const Text('今日规划'),
                    onPressed: () => _open(AppRoutes.today),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.timer_outlined),
                    label: const Text('专注计时'),
                    onPressed: () => _open(AppRoutes.focus),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.checklist),
                    label: const Text('待办'),
                    onPressed: () => _open('/todo'),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.search),
                    label: const Text('本地搜索'),
                    onPressed: () => _open('/search'),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.folder_copy_outlined),
                    label: const Text('备份与恢复'),
                    onPressed: () => _open('/backup'),
                  ),
                ],
              ),
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
          DashboardSectionView<TodayAgenda>(
            title: '作业与考试',
            description: '作业按截止日期归入当天，考试按当天是否在考试时间段内归入；两者分开显示，不计入任务指标。',
            state: _agenda,
            onRetry: _load,
            contentBuilder: (context, data) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.assignments.isEmpty && data.exams.isEmpty
                      ? '今日暂无作业截止或考试'
                      : '今日截止作业 ${data.assignments.length} 项 · '
                            '今日考试 ${data.exams.length} 场',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                for (final assignment in data.assignments)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('作业截止  ${assignment.title}'),
                  ),
                for (final exam in data.exams)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('考试  ${exam.title}'),
                  ),
                _link(AppRoutes.academic),
              ],
            ),
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
                      : 'GPA ${data.value!.toStringAsFixed(2)} / 5.0',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '已评分 ${data.gradedCourseCount} 门 · 待评分 ${data.missingCount} 门',
                ),
                const Text('全部学期 · 自定义 5.0 规则，非学校官方换算'),
                _link(AppRoutes.gpa),
              ],
            ),
          ),
          DashboardSectionView<FinanceOverview>(
            title: '本月收支',
            description: '预算只抵扣对应分类的当月支出；未设置与设置为 0 是两种不同状态。',
            state: _finance,
            onRetry: _load,
            contentBuilder: (context, data) {
              final summary = data.summary;
              final spentByCategory = {
                for (final expense in summary.expenseByCategory)
                  expense.categoryId: expense.amountMinor,
              };
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${summary.month.year} / ${summary.month.month}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text('收入  ${_money(summary.incomeMinor)}'),
                  Text('支出  ${_money(summary.expenseMinor)}'),
                  Text('结余  ${_money(summary.balanceMinor)}'),
                  if (summary.incomeMinor == 0 && summary.expenseMinor == 0)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('本月暂无收支记录（收支为 0）'),
                    ),
                  const SizedBox(height: 8),
                  if (data.budgets.isEmpty)
                    const Text('本月未设置分类预算')
                  else
                    for (final budget in data.budgets)
                      _budgetLine(
                        budget: budget,
                        spentMinor: spentByCategory[budget.categoryId] ?? 0,
                        categoryName:
                            data.categoryNames[budget.categoryId] ?? '未分类',
                      ),
                  _link(AppRoutes.finance),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}
