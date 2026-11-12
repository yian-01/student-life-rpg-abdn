import 'dart:convert';
import 'dart:typed_data';

import '../models/finance_record.dart';
import '../models/finance_type.dart';
import '../models/money.dart';

/// UTF-8 with BOM so desktop spreadsheets can detect Chinese column headers.
Uint8List exportFinanceCsv(
  Iterable<FinanceRecord> rows,
  Map<String, String> names,
) {
  final output = StringBuffer(
    '\ufeff"日期时间","收支","分类","金额（元）","备注","报销状态","含票据"\r\n',
  );
  for (final row in rows) {
    final cells = [
      row.occurredAt.toIso8601String(),
      row.type == FinanceType.income ? '收入' : '支出',
      _spreadsheetText(names[row.categoryId] ?? row.categoryId),
      formatAmountMinor(row.amountMinor),
      _spreadsheetText(row.note ?? ''),
      row.type == FinanceType.expense ? row.reimbursement.label : '',
      row.receipt == null ? '否' : '是',
    ];
    output
      ..write(cells.map((cell) => '"${cell.replaceAll('"', '""')}"').join(','))
      ..write('\r\n');
  }
  return Uint8List.fromList(utf8.encode(output.toString()));
}

String _spreadsheetText(String input) {
  final value = input.replaceAll(
    RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'),
    '',
  );
  final first = value.trimLeft();
  if (RegExp(r'^[=+\-@＝＋－＠]').hasMatch(first) ||
      RegExp(r'^[\t\r\n]').hasMatch(value)) {
    return "'$value";
  }
  return value;
}
