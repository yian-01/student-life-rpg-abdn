import '../../../app/module_body.dart';
import 'package:flutter/material.dart';

import '../controllers/finance_controller.dart';
import '../finance_memory_scope.dart';
import '../models/finance_category.dart';
import '../models/finance_record.dart';
import '../models/finance_type.dart';
import '../models/money.dart';
import '../models/monthly_finance_summary.dart';

class FinancePage extends StatefulWidget {
  const FinancePage({super.key, this.controller});

  final FinanceController? controller;

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  late final FinanceController _controller;
  late final bool _ownsController;
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  FinanceType _selectedType = FinanceType.expense;
  String? _selectedCategoryId;

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
    _controller.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.load();
    });
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Finance')),
      body: ModuleBody(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    '演示数据：分类为合成示例。财务记录保存在内存中，完全退出应用后不会保留。本轮仅 Task 安排 JSON 持久化。预算由组合根注入（演示预算 1000.00 元），无预算 CRUD。',
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
                  const SizedBox(height: 16),
                  _AddRecordForm(
                    categories: _controller.categoriesFor(_selectedType),
                    selectedType: _selectedType,
                    selectedCategoryId: _selectedCategoryId,
                    amountController: _amountController,
                    noteController: _noteController,
                    onTypeChanged: (type) {
                      setState(() {
                        _selectedType = type;
                        final matching = _controller.categoriesFor(type);
                        _selectedCategoryId = matching.isEmpty
                            ? null
                            : matching.first.id;
                      });
                    },
                    onCategoryChanged: (id) {
                      setState(() => _selectedCategoryId = id);
                    },
                    onSubmit: _selectedCategoryId == null
                        ? null
                        : () async {
                            await _controller.addRecord(
                              categoryId: _selectedCategoryId!,
                              amountText: _amountController.text,
                              note: _noteController.text,
                            );
                            if (!mounted) return;
                            if (_controller.error == null) {
                              _amountController.clear();
                              _noteController.clear();
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
                    ..._controller.monthRecords.map(_RecordTile.new),
                  SizedBox(height: constraints.maxHeight < 360 ? 8 : 24),
                ],
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
            Text('余额 ${formatAmountMinor(data.balanceMinor)} 元'),
            Text(
              remaining == null
                  ? '预算剩余 未设置'
                  : '预算剩余 ${formatAmountMinor(remaining)} 元',
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
    required this.onTypeChanged,
    required this.onCategoryChanged,
    required this.onSubmit,
  });

  final List<FinanceCategory> categories;
  final FinanceType selectedType;
  final String? selectedCategoryId;
  final TextEditingController amountController;
  final TextEditingController noteController;
  final ValueChanged<FinanceType> onTypeChanged;
  final ValueChanged<String?> onCategoryChanged;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
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
        TextField(
          controller: amountController,
          decoration: const InputDecoration(
            labelText: '金额（元）',
            hintText: '例如 3.50',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
  const _RecordTile(this.record);

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
        subtitle: Text(
          [
            record.categoryId,
            record.occurredAt.toIso8601String(),
            if (note != null && note.isNotEmpty) note,
          ].join(' · '),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
