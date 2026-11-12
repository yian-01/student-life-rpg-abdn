import 'package:flutter/material.dart';

import '../../../app/module_body.dart';
import '../../../shared/presentation/record_editor_dialog.dart';
import '../../../shared/presentation/undo_removal.dart';
import '../../academic/presentation/assignment_exam_page.dart';
import '../controllers/finance_controller.dart';
import '../models/finance_category.dart';
import '../models/finance_record.dart';
import '../models/finance_type.dart';
import '../models/money.dart';
import '../services/finance_calculator.dart';
import 'finance_record_editor.dart';

class FinanceFilterPage extends StatefulWidget {
  const FinanceFilterPage({super.key, required this.controller});
  final FinanceController controller;

  @override
  State<FinanceFilterPage> createState() => _FinanceFilterPageState();
}

typedef _Ledger = ({
  List<FinanceRecord> records,
  List<FinanceCategory> categories,
});

class _FinanceFilterPageState extends State<FinanceFilterPage> {
  late Future<_Ledger> _data = _load();
  FinanceType? _type;
  String? _category;
  DateTimeRange? _range;
  bool _pending = false;
  bool _acting = false;

  Future<_Ledger> _load() async => (
    records: await widget.controller.listRecords(),
    categories: await widget.controller.listCategories(),
  );

  void _refresh() => setState(() => _data = _load());

  Future<void> _chooseDate() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
      initialDateRange: _range,
    );
    if (mounted && range != null) setState(() => _range = range);
  }

  Future<void> _edit(FinanceRecord row) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await widget.controller.refresh();
      if (!mounted) return;
      if (widget.controller.error != null) {
        throw StateError('Unable to load finance');
      }
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            FinanceRecordEditor(controller: widget.controller, record: row),
      );
      if (mounted) _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('打开账目失败，请刷新。')));
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _delete(FinanceRecord row, String title) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      if (!await confirmRemoval(context, title, undoable: true) || !mounted) {
        return;
      }
      if (!await widget.controller.removeRecord(row.id)) {
        throw StateError('Delete failed');
      }
      if (!mounted) return;
      final controller = widget.controller;
      offerRemovalUndo(context, title, () async {
        await controller.restoreRecord(row);
        if (mounted) _refresh();
      });
      _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('删除失败，请重试。')));
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('筛选账目'),
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<_Ledger>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: _refresh,
              child: const Text('读取账本失败，点击重试'),
            ),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final byId = {
          for (final category in data.categories) category.id: category,
        };
        final categoryId = byId.containsKey(_category) ? _category : null;
        final range = _range;
        final start = range?.start;
        final end = range == null
            ? null
            : DateTime(range.end.year, range.end.month, range.end.day + 1);
        final rows =
            data.records
                .where(
                  (row) =>
                      (_type == null || row.type == _type) &&
                      (categoryId == null || row.categoryId == categoryId) &&
                      (!_pending ||
                          row.reimbursement == ReimbursementStatus.pending) &&
                      (start == null || !row.occurredAt.isBefore(start)) &&
                      (end == null || row.occurredAt.isBefore(end)),
                )
                .toList()
              ..sort((a, b) {
                final order = b.occurredAt.compareTo(a.occurredAt);
                return order == 0 ? a.id.compareTo(b.id) : order;
              });
        final totals = const FinanceCalculator().calculate(
          rows,
          limitTotals: false,
        );
        final pending = const FinanceCalculator().calculate(
          rows
              .where((row) => row.reimbursement == ReimbursementStatus.pending)
              .toList(),
          limitTotals: false,
        );
        return ModuleBody(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (snapshot.connectionState != ConnectionState.done)
                const LinearProgressIndicator(),
              DropdownButton<FinanceType?>(
                isExpanded: true,
                value: _type,
                items: [
                  const DropdownMenuItem(value: null, child: Text('全部收支')),
                  const DropdownMenuItem(
                    value: FinanceType.income,
                    child: Text('收入'),
                  ),
                  const DropdownMenuItem(
                    value: FinanceType.expense,
                    child: Text('支出'),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _type = value;
                  if (value != null && byId[_category]?.type != value) {
                    _category = null;
                  }
                }),
              ),
              DropdownButton<String?>(
                isExpanded: true,
                value: categoryId,
                items: [
                  const DropdownMenuItem(value: null, child: Text('全部分类')),
                  for (final category in data.categories)
                    if (_type == null || category.type == _type)
                      DropdownMenuItem(
                        value: category.id,
                        child: Text(
                          category.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                ],
                onChanged: (value) => setState(() => _category = value),
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _chooseDate,
                    child: Text(
                      range == null
                          ? '全部日期'
                          : '${_day(range.start)} — ${_day(range.end)}（含首尾）',
                    ),
                  ),
                  FilterChip(
                    label: const Text('仅待报销'),
                    selected: _pending,
                    onSelected: (value) => setState(() => _pending = value),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _type = null;
                      _category = null;
                      _range = null;
                      _pending = false;
                    }),
                    child: const Text('清除筛选'),
                  ),
                ],
              ),
              const Divider(),
              Text('筛选结果 · ${rows.length} 笔'),
              Text(
                '收入 ¥${_money(totals.incomeMinor)} · 支出 ¥${_money(totals.expenseMinor)} · 结余 ¥${_money(totals.balanceMinor)}',
              ),
              Text('其中待报销支出 ¥${_money(pending.expenseMinor)}'),
              if (rows.isEmpty) const Text('暂无符合条件的账目'),
              for (final row in rows)
                Card(
                  child: ListTile(
                    title: Text(
                      '${byId[row.categoryId]?.name ?? row.categoryId} · ¥${_money(row.amountMinor)}',
                    ),
                    subtitle: Text(
                      '${formatLocalDateTime(row.occurredAt)}'
                      '${row.type == FinanceType.expense ? ' · ${row.reimbursement.label}' : ''}'
                      '${row.note == null ? '' : '\n${row.note}'}',
                    ),
                    onTap: _acting ? null : () => _edit(row),
                    trailing: IconButton(
                      tooltip: '删除账目',
                      onPressed: _acting
                          ? null
                          : () => _delete(
                              row,
                              byId[row.categoryId]?.name ?? '账目',
                            ),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

String _day(DateTime date) => formatLocalDateTime(date).split(' ').first;

String _money(int minor) => formatAmountMinor(minor);
