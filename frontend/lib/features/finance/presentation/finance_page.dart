import '../../../app/module_body.dart';
import 'package:flutter/material.dart';
import '../../../shared/presentation/undo_removal.dart';
import 'finance_filter_page.dart';
import 'weekly_finance_page.dart';
import 'receipt_fields.dart';

import '../controllers/finance_controller.dart';
import '../controllers/budget_controller.dart';
import '../../../shared/presentation/civil_datetime_field.dart';
import '../../../shared/presentation/record_editor_dialog.dart';
import 'finance_record_editor.dart';
import 'category_manager.dart';
import 'budget_editor.dart';
import '../finance_memory_scope.dart';
import '../models/finance_category.dart';
import '../models/finance_record.dart';
import '../models/finance_type.dart';
import '../models/money.dart';
import '../models/monthly_finance_summary.dart';

class FinancePage extends StatefulWidget {
  const FinancePage({
    super.key,
    this.controller,
    this.budgetController,
    this.isPersistent = false,
    this.onRecover,
    this.initialMonth,
  });

  final FinanceController? controller;
  final BudgetController? budgetController;
  final bool isPersistent;
  final DateTime? initialMonth;
  final Future<void> Function()? onRecover;

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  late final FinanceController _controller;
  late final bool _ownsController;
  late final BudgetController? _budgetController;
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  FinanceType _selectedType = FinanceType.expense;
  String? _selectedCategoryId;
  late DateTime _recordDate;
  bool _budgetWasSaving = false;
  ReimbursementStatus _reimbursement = ReimbursementStatus.none;
  String? _receipt;
  int _recordFormRevision = 0;

  @override
  void initState() {
    super.initState();
    final injected = widget.controller;
    if (injected != null) {
      _controller = injected;
      _ownsController = false;
    } else {
      _controller = FinanceMemoryScope.shared.controller;
      _ownsController = false;
    }
    _recordDate = _controller.now;
    _budgetController =
        widget.budgetController ??
        (injected == null ? FinanceMemoryScope.shared.budgetController : null);
    _controller.addListener(_onChanged);
    _budgetController?.addListener(_onBudgetChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.load(month: widget.initialMonth);
    });
  }

  void _onBudgetChanged() {
    if (!mounted) return;
    final saving = _budgetController?.isSaving ?? false;
    // 预算保存完成后重新读取月汇总，使总额剩余与分类状态一致。
    if (_budgetWasSaving && !saving) {
      _controller.refresh();
    }
    _budgetWasSaving = saving;
    setState(() {});
  }

  @override
  void dispose() {
    _budgetController?.removeListener(_onBudgetChanged);
    _controller.removeListener(_onChanged);
    _amountController.dispose();
    _noteController.dispose();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      final matching = _controller.categoriesFor(_selectedType);
      if (_selectedCategoryId == null ||
          matching.every((category) => category.id != _selectedCategoryId)) {
        _selectedCategoryId = matching.isEmpty ? null : matching.first.id;
      }
    });
  }

  Future<void> _addCategory() async {
    final category = await showNewFinanceCategory(
      context,
      controller: _controller,
      type: _selectedType,
    );
    if (!mounted || category == null) return;
    if (_controller
        .categoriesFor(category.type)
        .any((row) => row.id == category.id)) {
      setState(() => _selectedCategoryId = category.id);
    }
  }

  void _changeMonth(int delta) {
    final target = DateTime(
      _controller.month.year,
      _controller.month.month + delta,
    );
    setState(() => _recordDate = _dateInMonth(_recordDate, target));
    _controller.load(month: target);
  }

  static DateTime _dateInMonth(DateTime date, DateTime month) {
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final day = date.day > lastDay ? lastDay : date.day;
    return DateTime(month.year, month.month, day, date.hour, date.minute);
  }

  Map<String, int> _spentByCategory() => {
    for (final expense in _controller.summary?.expenseByCategory ?? const [])
      expense.categoryId: expense.amountMinor,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('生活账本'),
        actions: [
          IconButton(
            tooltip: '筛选账目',
            icon: const Icon(Icons.filter_list),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => FinanceFilterPage(controller: _controller),
              ),
            ),
          ),
          IconButton(
            tooltip: '分类管理',
            onPressed: () =>
                showCategoryManager(context, controller: _controller),
            icon: const Icon(Icons.category),
          ),
          if (widget.onRecover != null)
            IconButton(
              tooltip: '重新读取 / 从备份恢复',
              onPressed: widget.onRecover,
              icon: const Icon(Icons.restore),
            ),
        ],
      ),
      body: ModuleBody(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ModuleNotice(
                      widget.isPersistent
                          ? '收支记录与分类预算保存在本机。'
                          : '演示数据：账本记录仅存内存，关闭应用后重置。分类为示例，演示预算为 1000 元。',
                    ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: '上个月',
                          onPressed: _controller.isLoading
                              ? null
                              : () => _changeMonth(-1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: Text(
                            '${_controller.month.year}-${_controller.month.month.toString().padLeft(2, '0')}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        IconButton(
                          tooltip: '下个月',
                          onPressed: _controller.isLoading
                              ? null
                              : () => _changeMonth(1),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_controller.isLoading) const Text('加载中'),
                    if (_controller.error != null) ...[
                      Text(
                        '错误：${_controller.error}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _controller.retry,
                          child: const Text('重试'),
                        ),
                      ),
                    ],
                    _SummaryCard(summary: _controller.summary),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.show_chart),
                        label: const Text('每周收支趋势'),
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) =>
                                WeeklyFinancePage(controller: _controller),
                          ),
                        ),
                      ),
                    ),
                    if (_budgetController != null) ...[
                      const SizedBox(height: 12),
                      BudgetSection(
                        controller: _budgetController,
                        month: _controller.month,
                        spentByCategory: _spentByCategory(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (_selectedType == FinanceType.expense)
                      ExpansionTile(
                        key: ValueKey(_recordFormRevision),
                        title: const Text('新支出的报销与票据'),
                        children: [
                          ReceiptFields(
                            status: _reimbursement,
                            receipt: _receipt,
                            onChanged: (status, receipt) => setState(() {
                              _reimbursement = status;
                              _receipt = receipt;
                            }),
                          ),
                        ],
                      ),
                    _AddRecordForm(
                      categories: _controller.categoriesFor(_selectedType),
                      selectedType: _selectedType,
                      selectedCategoryId: _selectedCategoryId,
                      amountController: _amountController,
                      noteController: _noteController,
                      date: _recordDate,
                      viewedMonth: _controller.month,
                      onDateChanged: (value) =>
                          setState(() => _recordDate = value),
                      onTypeChanged: (type) {
                        setState(() {
                          _selectedType = type;
                          final matching = _controller.categoriesFor(type);
                          _selectedCategoryId = matching.isEmpty
                              ? null
                              : matching.first.id;
                        });
                      },
                      onAddCategory:
                          _controller.isSaving || _controller.isLoading
                          ? null
                          : _addCategory,
                      onCategoryChanged: (id) {
                        setState(() => _selectedCategoryId = id);
                      },
                      onSubmit:
                          _selectedCategoryId == null ||
                              _controller.isSaving ||
                              _controller.isLoading
                          ? null
                          : () async {
                              final saved = await _controller.addRecord(
                                categoryId: _selectedCategoryId!,
                                amountText: _amountController.text,
                                occurredAt: _recordDate,
                                note: _noteController.text,
                                reimbursement:
                                    _selectedType == FinanceType.expense
                                    ? _reimbursement
                                    : ReimbursementStatus.none,
                                receipt: _selectedType == FinanceType.expense
                                    ? _receipt
                                    : null,
                              );
                              if (!mounted) return;
                              if (saved) {
                                _amountController.clear();
                                _noteController.clear();
                                setState(() {
                                  _reimbursement = ReimbursementStatus.none;
                                  _receipt = null;
                                  _recordFormRevision++;
                                });
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _controller.refresh,
                        child: const Text('刷新'),
                      ),
                    ),
                    const Text('本月记录'),
                    const SizedBox(height: 8),
                    if (_controller.monthRecords.isEmpty)
                      const Text('暂无记录')
                    else
                      ..._controller.monthRecords.map(
                        (record) => _RecordTile(
                          record,
                          categoryName:
                              _controller.availableCategories
                                  .where((c) => c.id == record.categoryId)
                                  .map((c) => c.name)
                                  .firstOrNull ??
                              record.categoryId,
                          onAction: _controller.isSaving
                              ? null
                              : (action) async {
                                  if (action == 'edit') {
                                    await showDialog<bool>(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (_) => FinanceRecordEditor(
                                        controller: _controller,
                                        record: record,
                                      ),
                                    );
                                  } else if (await confirmRemoval(
                                        context,
                                        '这笔收支记录',
                                        undoable: true,
                                      ) &&
                                      mounted) {
                                    final controller = _controller;
                                    final removed = await controller
                                        .removeRecord(record.id);
                                    if (removed && context.mounted) {
                                      offerRemovalUndo(
                                        context,
                                        '收支记录',
                                        () => controller.restoreRecord(record),
                                      );
                                    }
                                  }
                                },
                        ),
                      ),
                    SizedBox(height: constraints.maxHeight < 360 ? 8 : 24),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final MonthlyFinanceSummary? summary;

  @override
  Widget build(BuildContext context) {
    final data = summary;
    if (data == null) {
      return const Card(
        child: Padding(padding: EdgeInsets.all(16), child: Text('汇总未加载')),
      );
    }
    final remaining = data.remainingBudgetMinor;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '月份 ${data.month.year}-${data.month.month.toString().padLeft(2, '0')}',
            ),
            Text('收入 ${formatAmountMinor(data.incomeMinor)} 元'),
            Text('支出 ${formatAmountMinor(data.expenseMinor)} 元'),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '余额 ${formatAmountMinor(data.balanceMinor)} 元',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            Text(
              data.budgetMinor == null
                  ? '月预算 未设置'
                  : '月预算 ${formatAmountMinor(data.budgetMinor!)} 元',
            ),
            Text(
              remaining == null
                  ? '预算剩余 未设置'
                  : remaining < 0
                  ? '预算剩余 ${formatAmountMinor(remaining)} 元（超支）'
                  : '预算剩余 ${formatAmountMinor(remaining)} 元',
              style: remaining != null && remaining < 0
                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddRecordForm extends StatelessWidget {
  const _AddRecordForm({
    required this.categories,
    required this.selectedType,
    required this.selectedCategoryId,
    required this.amountController,
    required this.noteController,
    required this.date,
    required this.viewedMonth,
    required this.onDateChanged,
    required this.onTypeChanged,
    required this.onCategoryChanged,
    required this.onAddCategory,
    required this.onSubmit,
  });

  final List<FinanceCategory> categories;
  final FinanceType selectedType;
  final String? selectedCategoryId;
  final TextEditingController amountController;
  final TextEditingController noteController;
  final DateTime date;
  final DateTime viewedMonth;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<FinanceType> onTypeChanged;
  final ValueChanged<String?> onCategoryChanged;
  final VoidCallback? onAddCategory;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final crossesMonth =
        date.year != viewedMonth.year || date.month != viewedMonth.month;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('支出'),
              selected: selectedType == FinanceType.expense,
              onSelected: (_) => onTypeChanged(FinanceType.expense),
            ),
            ChoiceChip(
              label: const Text('收入'),
              selected: selectedType == FinanceType.income,
              onSelected: (_) => onTypeChanged(FinanceType.income),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          // ignore: deprecated_member_use
          value: selectedCategoryId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '分类'),
          items: categories
              .map(
                (category) => DropdownMenuItem(
                  value: category.id,
                  child: Text(category.name, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: onCategoryChanged,
        ),
        TextButton.icon(
          key: const Key('finance-add-category-inline'),
          onPressed: onAddCategory,
          icon: const Icon(Icons.add),
          label: Text(
            '新建${selectedType == FinanceType.expense ? '支出' : '收入'}分类',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: amountController,
          decoration: const InputDecoration(
            labelText: '金额（元）',
            hintText: '例如 3.50',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        CivilDateTimeField(
          label: '日期',
          value: date,
          enabled: onSubmit != null,
          showTime: false,
          onChanged: onDateChanged,
        ),
        if (crossesMonth)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '保存后将切换到 ${date.year}-${date.month.toString().padLeft(2, '0')}',
              key: const Key('finance-date-month-hint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        TextField(
          controller: noteController,
          decoration: const InputDecoration(labelText: '备注（可选）'),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: onSubmit, child: const Text('添加记录')),
      ],
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile(this.record, {required this.categoryName, this.onAction});
  final String categoryName;
  final ValueChanged<String>? onAction;

  final FinanceRecord record;

  @override
  Widget build(BuildContext context) {
    final kind = record.type == FinanceType.income ? '收入' : '支出';
    final note = record.note;
    return Card(
      child: ListTile(
        title: Text(
          '$kind ${formatAmountMinor(record.amountMinor)} 元',
          overflow: TextOverflow.ellipsis,
        ),
        trailing: onAction == null
            ? null
            : PopupMenuButton<String>(
                key: Key('finance-actions-${record.id}'),
                onSelected: onAction,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
        subtitle: Text(
          [
            categoryName,
            record.occurredAt.toIso8601String(),
            if (record.type == FinanceType.expense &&
                record.reimbursement != ReimbursementStatus.none)
              record.reimbursement.label,
            if (record.receipt != null) '含票据',
            if (note != null && note.isNotEmpty) note,
          ].join(' · '),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
