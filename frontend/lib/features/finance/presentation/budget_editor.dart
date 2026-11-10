import 'package:flutter/material.dart';

import '../../../shared/presentation/record_editor_dialog.dart';
import '../controllers/budget_controller.dart';
import '../models/money.dart';

/// 打开“设置分类月度预算”对话框。
Future<void> showBudgetEditor(
  BuildContext context, {
  required BudgetController controller,
  String? categoryId,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BudgetEditorDialog(
      controller: controller,
      initialCategoryId: categoryId,
    ),
  );
}

/// 单个支出类别的月度预算表单。
///
/// 复用 [RecordEditorDialog] 的保存边界：失败时保留输入、防止重复提交。
/// 金额允许 0（有效预算）；空输入或非法格式由 [BudgetController.setBudget]
/// 解析并反馈错误。
class BudgetEditorDialog extends StatefulWidget {
  const BudgetEditorDialog({
    super.key,
    required this.controller,
    this.initialCategoryId,
  });

  final BudgetController controller;
  final String? initialCategoryId;

  @override
  State<BudgetEditorDialog> createState() => _BudgetEditorDialogState();
}

class _BudgetEditorDialogState extends State<BudgetEditorDialog> {
  String? _categoryId;
  late final TextEditingController _amount;

  @override
  void initState() {
    super.initState();
    final categories = widget.controller.expenseCategories;
    if (widget.initialCategoryId != null) {
      _categoryId = widget.initialCategoryId;
    } else {
      _categoryId = categories.isEmpty ? null : categories.first.id;
    }
    _amount = TextEditingController(text: _initialAmountText(_categoryId));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  String _initialAmountText(String? categoryId) {
    if (categoryId == null) return '';
    final existing = widget.controller.budgetFor(categoryId);
    return existing == null ? '' : formatAmountMinor(existing);
  }

  void _onCategoryChanged(String? id) {
    setState(() {
      _categoryId = id;
      _amount.text = _initialAmountText(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.controller.expenseCategories;
    return RecordEditorDialog(
      title: '设置分类月度预算',
      onSave: () async {
        final categoryId = _categoryId;
        if (categoryId == null) {
          throw const FormatException('请选择一个支出分类。');
        }
        final saved = await widget.controller.setBudget(
          categoryId: categoryId,
          amountText: _amount.text,
        );
        if (!saved) {
          throw const FormatException('保存失败，请检查金额、分类和存储后重试。');
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _categoryId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '支出分类'),
            items: categories
                .map(
                  (category) => DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: _onCategoryChanged,
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('budget-amount'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '月预算（元，0 为有效预算）',
              hintText: '例如 500 或 0',
            ),
          ),
        ],
      ),
    );
  }
}

/// 可嵌入页面的分类月度预算区块：列出支出类别的预算、已用、剩余/超支状态，
/// 并提供设置与清除入口。
///
/// [spentByCategory] 来自月度汇总的分类支出（`expenseByCategory`），因此页面和
/// 总览共用同一套金额算法，不在本组件内重复汇总。
class BudgetSection extends StatefulWidget {
  const BudgetSection({
    super.key,
    required this.controller,
    this.spentByCategory = const {},
    this.month,
  });

  final BudgetController controller;

  /// 类别 ID → 本月已用金额（分）。收入和其他类别的支出不在此抵消预算。
  final Map<String, int> spentByCategory;

  /// 与页面总览保持一致的本地月份；为空时沿用控制器当前月份。
  final DateTime? month;

  @override
  State<BudgetSection> createState() => _BudgetSectionState();
}

class _BudgetSectionState extends State<BudgetSection> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.load(month: widget.month);
    });
  }

  @override
  void didUpdateWidget(covariant BudgetSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.month != oldWidget.month) {
      widget.controller.load(month: widget.month);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  String _monthLabel() {
    final month = widget.controller.month;
    return '${month.year}-${month.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final categories = controller.expenseCategories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '分类月度预算 · ${_monthLabel()}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: controller.isLoading || categories.isEmpty
                  ? null
                  : () => showBudgetEditor(context, controller: controller),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('设置预算'),
            ),
          ],
        ),
        if (controller.isLoading) const Text('加载中'),
        if (controller.error != null) ...[
          Text(
            '错误：${controller.error}',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: controller.retry,
              child: const Text('重试'),
            ),
          ),
        ],
        if (categories.isEmpty)
          const Text('暂无支出分类')
        else
          ...categories.map((category) {
            final isSet = controller.isBudgetSet(category.id);
            final amount = controller.budgetFor(category.id);
            final spent = widget.spentByCategory[category.id] ?? 0;
            final remaining = isSet ? amount! - spent : null;
            final overspent = remaining != null && remaining < 0;
            final status = !isSet
                ? '未设置预算 · 已用 ${formatAmountMinor(spent)} 元'
                : overspent
                ? '已用 ${formatAmountMinor(spent)} 元 · 超支 ${formatAmountMinor(-remaining)} 元'
                : '已用 ${formatAmountMinor(spent)} 元 · 剩余 ${formatAmountMinor(remaining!)} 元';
            return ListTile(
              key: Key('budget-row-${category.id}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(category.name, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                status,
                key: Key('budget-status-${category.id}'),
                style: overspent
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(isSet ? '${formatAmountMinor(amount ?? 0)} 元' : '—'),
                  IconButton(
                    tooltip: '设置',
                    onPressed: controller.isSaving
                        ? null
                        : () => showBudgetEditor(
                            context,
                            controller: controller,
                            categoryId: category.id,
                          ),
                    icon: const Icon(Icons.edit, size: 18),
                  ),
                  IconButton(
                    tooltip: '清除',
                    onPressed: (!isSet || controller.isSaving)
                        ? null
                        : () => controller.removeBudget(category.id),
                    icon: const Icon(Icons.clear, size: 18),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
