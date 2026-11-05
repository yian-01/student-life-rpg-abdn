import 'package:flutter/material.dart';

import '../../../shared/presentation/record_editor_dialog.dart';
import '../controllers/finance_controller.dart';
import '../models/finance_category.dart';
import '../models/finance_type.dart';

String _errorMessage(Object? error, String fallback) {
  if (error is StateError) return error.message;
  if (error is ArgumentError) return error.message?.toString() ?? fallback;
  return fallback;
}

Future<void> showCategoryManager(
  BuildContext context, {
  required FinanceController controller,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => CategoryManagerDialog(controller: controller),
  );
}

class CategoryManagerDialog extends StatefulWidget {
  const CategoryManagerDialog({super.key, required this.controller});

  final FinanceController controller;

  @override
  State<CategoryManagerDialog> createState() => _CategoryManagerDialogState();
}

class _CategoryManagerDialogState extends State<CategoryManagerDialog> {
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.load();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _nameController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  FinanceType _newType = FinanceType.expense;

  Future<void> _add() async {
    final name = _nameController.text;
    final type = _newType;
    final dialogContext = context;
    await showDialog<bool>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (_) => _CategoryFormDialog(
        title: '新增分类',
        initialName: name,
        initialType: type,
        typeEnabled: true,
        onSave: (newName, newType) async {
          final saved = await widget.controller.addCategory(
            name: newName,
            type: newType,
          );
          if (!saved) {
            throw FormatException(
              _errorMessage(widget.controller.error, '保存失败，请检查分类名称与引用后重试。'),
            );
          }
        },
      ),
    );
    _nameController.clear();
  }

  Future<void> _edit(FinanceCategory category) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CategoryFormDialog(
        title: '编辑分类',
        initialName: category.name,
        initialType: category.type,
        typeEnabled: true,
        onSave: (newName, newType) async {
          final saved = await widget.controller.editCategory(
            category.id,
            name: newName,
            type: newType,
          );
          if (!saved) {
            throw FormatException(
              _errorMessage(widget.controller.error, '保存失败。'),
            );
          }
        },
      ),
    );
  }

  Future<void> _delete(FinanceCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除分类？'),
        content: Text('删除“${category.name}”后无法撤销。被记录或预算引用时不能删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final saved = await widget.controller.deleteCategory(category.id);
    if (!saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _errorMessage(widget.controller.error, '删除失败，请检查引用后重试。'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.controller.availableCategories;
    return AlertDialog(
      title: const Text('分类管理'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: '新分类名称'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<FinanceType>(
                    value: _newType,
                    items: FinanceType.values
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(
                              type == FinanceType.expense ? '支出' : '收入',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _newType = value);
                    },
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final name = _nameController.text;
                      if (name.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('分类名称不能为空。')),
                        );
                        return;
                      }
                      _add();
                    },
                    child: const Text('添加'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (categories.isEmpty)
                const Text('暂无分类')
              else
                ...categories.map(
                  (category) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(category.name, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      category.type == FinanceType.expense ? '支出' : '收入',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '编辑',
                          onPressed: () => _edit(category),
                          icon: const Icon(Icons.edit, size: 18),
                        ),
                        IconButton(
                          tooltip: '删除',
                          onPressed: () => _delete(category),
                          icon: const Icon(Icons.delete, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _CategoryFormDialog extends StatefulWidget {
  const _CategoryFormDialog({
    required this.title,
    required this.initialName,
    required this.initialType,
    required this.typeEnabled,
    required this.onSave,
  });

  final String title;
  final String initialName;
  final FinanceType initialType;
  final bool typeEnabled;
  final Future<void> Function(String name, FinanceType type) onSave;

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  late final TextEditingController _name;
  late FinanceType _type;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _type = widget.initialType;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RecordEditorDialog(
    title: widget.title,
    onSave: () => widget.onSave(_name.text, _type),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('category-name'),
          controller: _name,
          decoration: const InputDecoration(labelText: '名称'),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<FinanceType>(
          initialValue: _type,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '类型'),
          items: FinanceType.values
              .map(
                (type) => DropdownMenuItem(
                  value: type,
                  child: Text(type == FinanceType.expense ? '支出' : '收入'),
                ),
              )
              .toList(),
          onChanged: widget.typeEnabled
              ? (value) {
                  if (value != null) setState(() => _type = value);
                }
              : null,
        ),
      ],
    ),
  );
}
