import 'package:flutter/material.dart';
import '../../../shared/presentation/civil_datetime_field.dart';
import '../../../shared/presentation/record_editor_dialog.dart';
import '../controllers/finance_controller.dart';
import '../models/finance_record.dart';
import '../models/finance_type.dart';
import 'receipt_fields.dart';

class FinanceRecordEditor extends StatefulWidget {
  const FinanceRecordEditor({
    super.key,
    required this.controller,
    required this.record,
  });
  final FinanceController controller;
  final FinanceRecord record;
  @override
  State<FinanceRecordEditor> createState() => _FinanceRecordEditorState();
}

class _FinanceRecordEditorState extends State<FinanceRecordEditor> {
  late final _amount = TextEditingController(
    text: (widget.record.amountMinor / 100).toStringAsFixed(2),
  );
  late final _note = TextEditingController(text: widget.record.note ?? '');
  late String _category = widget.record.categoryId;
  late DateTime _date = widget.record.occurredAt;
  late ReimbursementStatus _status = widget.record.reimbursement;
  late String? _receipt = widget.record.receipt;
  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RecordEditorDialog(
    title: '编辑收支',
    onSave: () async {
      final saved = await widget.controller.updateRecord(
        widget.record.id,
        categoryId: _category,
        amountText: _amount.text,
        occurredAt: _date,
        note: _note.text,
        reimbursement: _status,
        receipt: _receipt,
        replaceReceipt: true,
      );
      if (!saved) throw const FormatException('保存失败，请检查金额、分类和存储后重试。');
    },
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _category,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '分类（决定收支类型）'),
          items: widget.controller.availableCategories
              .map(
                (c) => DropdownMenuItem(
                  value: c.id,
                  child: Text(c.name, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => _category = v);
          },
        ),
        TextField(
          key: const Key('finance-edit-amount'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '金额（元）'),
        ),
        TextField(
          controller: _note,
          decoration: const InputDecoration(labelText: '备注'),
        ),
        if (widget.controller.availableCategories.any(
          (row) => row.id == _category && row.type == FinanceType.expense,
        ))
          ReceiptFields(
            status: _status,
            receipt: _receipt,
            onChanged: (status, image) => setState(() {
              _status = status;
              _receipt = image;
            }),
          ),
        const SizedBox(height: 12),
        CivilDateTimeField(
          label: '发生时间',
          value: _date,
          enabled: true,
          onChanged: (v) => setState(() => _date = v),
        ),
      ],
    ),
  );
}
