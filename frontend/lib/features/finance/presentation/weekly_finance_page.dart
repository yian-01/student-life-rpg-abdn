import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/finance_controller.dart';
import '../models/money.dart';
import '../models/finance_type.dart';
import '../services/weekly_finance.dart';
import 'finance_filter_page.dart';

class WeeklyFinancePage extends StatefulWidget {
  const WeeklyFinancePage({super.key, required this.controller});

  final FinanceController controller;

  @override
  State<WeeklyFinancePage> createState() => _WeeklyFinancePageState();
}

typedef _WeekReport = ({FinanceWeek week, Map<String, String> names});

class _WeeklyFinancePageState extends State<WeeklyFinancePage> {
  late DateTime _start = financeWeekStart(widget.controller.now);
  late int _selected = widget.controller.now.weekday - 1;
  late Future<_WeekReport> _future = _read(_start);
  bool _showIncome = true;

  Future<_WeekReport> _read(DateTime start) async => (
    week: weeklyFinance(await widget.controller.listRecords(), start),
    names: {
      for (final category in await widget.controller.listCategories())
        category.id: category.name,
    },
  );

  void _load(DateTime start, {bool resetSelection = false}) => setState(() {
    _start = financeWeekStart(start);
    if (resetSelection) {
      _selected =
          DateUtils.isSameDay(_start, financeWeekStart(widget.controller.now))
          ? widget.controller.now.weekday - 1
          : 0;
    }
    _future = _read(_start);
  });

  Future<void> _openDetails(
    DateTime start,
    DateTime end, {
    String? category,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FinanceFilterPage(
          controller: widget.controller,
          initialRange: DateTimeRange(start: start, end: end),
          initialType: category == null ? null : FinanceType.expense,
          initialCategoryId: category,
        ),
      ),
    );
    if (mounted) _load(_start);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('每周收支')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                IconButton(
                  tooltip: '上一周收支',
                  onPressed: () =>
                      _load(financeDayOffset(_start, -7), resetSelection: true),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  '${_date(_start)} — ${_date(financeDayOffset(_start, 6))}',
                ),
                IconButton(
                  tooltip: '下一周收支',
                  onPressed: () =>
                      _load(financeDayOffset(_start, 7), resetSelection: true),
                  icon: const Icon(Icons.chevron_right),
                ),
                TextButton(
                  onPressed: () =>
                      _load(widget.controller.now, resetSelection: true),
                  child: const Text('本周'),
                ),
              ],
            ),
            FutureBuilder<_WeekReport>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator();
                }
                final report = snapshot.data;
                if (report == null) {
                  return TextButton(
                    onPressed: () => _load(_start),
                    child: const Text('收支读取失败，点击重试'),
                  );
                }
                return _report(context, report);
              },
            ),
          ],
        ),
      ),
    ),
  );

  Widget _report(BuildContext context, _WeekReport report) {
    final week = report.week;
    final day = week.days[_selected];
    final difference = week.expense - week.previousExpense;
    final compare = difference == 0
        ? '与上周持平'
        : '${difference > 0 ? '比上周多' : '比上周少'} ${_yuan(difference.abs())}';
    final theme = Theme.of(context);
    final expenses = theme.colorScheme.primary;
    final income = theme.colorScheme.tertiary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _metric(context, '支出', _yuan(week.expense)),
            _metric(context, '收入', _yuan(week.income)),
            _metric(context, '净额', _yuan(week.income - week.expense)),
            _metric(context, '日均支出（按 7 天）', _yuan((week.expense / 7).round())),
          ],
        ),
        const SizedBox(height: 6),
        Text('上周支出 ${_yuan(week.previousExpense)} · $compare'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('每日趋势', style: theme.textTheme.titleLarge),
            Text('● 支出', style: TextStyle(color: expenses)),
            FilterChip(
              selected: _showIncome,
              label: Text('收入', style: TextStyle(color: income)),
              onSelected: (value) => setState(() => _showIncome = value),
            ),
          ],
        ),
        _WeekChart(
          days: week.days,
          selected: _selected,
          showIncome: _showIncome,
          expenses: expenses,
          income: income,
          onSelect: (value) => setState(() => _selected = value),
        ),
        if (week.days.every((day) => day.count == 0)) const Text('本周暂无账目'),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${_date(day.date)} · ${day.count} 笔'),
          subtitle: Text('支出 ${_yuan(day.expense)} · 收入 ${_yuan(day.income)}'),
          trailing: TextButton(
            onPressed: () => _openDetails(day.date, day.date),
            child: const Text('看明细'),
          ),
        ),
        const Divider(),
        Text('支出分类排行', style: theme.textTheme.titleLarge),
        if (week.categories.isEmpty) const Text('本周暂无支出'),
        for (final category in week.categories)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(report.names[category.id] ?? category.id),
            trailing: Text(_yuan(category.amount)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: LinearProgressIndicator(
                value: category.amount / week.expense,
                semanticsLabel:
                    '占本周支出 ${(category.amount / week.expense * 100).toStringAsFixed(1)}%',
              ),
            ),
            onTap: () => _openDetails(
              _start,
              financeDayOffset(_start, 6),
              category: category.id,
            ),
          ),
      ],
    );
  }

  Widget _metric(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
      ],
    ),
  );
}

String _date(DateTime date) => '${date.month} 月 ${date.day} 日';
String _yuan(int minor) => '¥${formatAmountMinor(minor)}';

class _WeekChart extends StatelessWidget {
  const _WeekChart({
    required this.days,
    required this.selected,
    required this.showIncome,
    required this.expenses,
    required this.income,
    required this.onSelect,
  });

  final List<FinanceDay> days;
  final int selected;
  final bool showIncome;
  final Color expenses;
  final Color income;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maximum = days.fold(
      1,
      (amount, day) => math.max(
        amount,
        showIncome ? math.max(day.income, day.expense) : day.expense,
      ),
    );
    return Column(
      children: [
        SizedBox(
          height: 152,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 58,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _yuan(maximum),
                      style: theme.textTheme.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text('¥0', style: theme.textTheme.labelSmall),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (event) => onSelect(
                      (event.localPosition.dx * 7 / constraints.maxWidth)
                          .floor()
                          .clamp(0, 6),
                    ),
                    child: CustomPaint(
                      key: const Key('weekly-finance-line-chart'),
                      painter: _WeekLines(
                        days: days,
                        maximum: maximum,
                        selected: selected,
                        showIncome: showIncome,
                        expenses: expenses,
                        income: income,
                        grid: theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 58),
          child: Row(
            children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: Semantics(
                    selected: selected == i,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: () => onSelect(i),
                      child: Text('一二三四五六日'[i]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeekLines extends CustomPainter {
  const _WeekLines({
    required this.days,
    required this.maximum,
    required this.selected,
    required this.showIncome,
    required this.expenses,
    required this.income,
    required this.grid,
  });

  final List<FinanceDay> days;
  final int maximum;
  final int selected;
  final bool showIncome;
  final Color expenses;
  final Color income;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final bottom = size.height - 6;
    const top = 6.0;
    final guide = Paint()..color = grid;
    double x(int i) => (i + 0.5) * size.width / 7;
    for (var i = 0; i < 5; i++) {
      final y = top + (bottom - top) * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), guide);
    }
    canvas.drawLine(
      Offset(x(selected), top),
      Offset(x(selected), bottom),
      guide..strokeWidth = 2,
    );

    void line(Color color, int Function(FinanceDay) value) {
      final path = Path();
      final points = [
        for (final (i, day) in days.indexed)
          Offset(x(i), bottom - (bottom - top) * value(day) / maximum),
      ];
      path.moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, paint);
      paint.style = PaintingStyle.fill;
      for (final (i, point) in points.indexed) {
        canvas.drawCircle(point, i == selected ? 5 : 3, paint);
      }
    }

    if (showIncome) line(income, (day) => day.income);
    line(expenses, (day) => day.expense);
  }

  @override
  bool shouldRepaint(_WeekLines old) =>
      old.days != days ||
      old.selected != selected ||
      old.showIncome != showIncome ||
      old.maximum != maximum ||
      old.expenses != expenses ||
      old.income != income ||
      old.grid != grid;
}
