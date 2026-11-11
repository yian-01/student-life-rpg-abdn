import 'dart:convert';
import 'finance_type.dart';
import 'json_map.dart';
import 'local_date_time_json.dart';
import 'money.dart';

enum ReimbursementStatus {
  none('无需报销'),
  pending('待报销'),
  reimbursed('已报销');

  const ReimbursementStatus(this.label);
  final String label;

  static ReimbursementStatus decode(Object? value) {
    if (value == null) return none;
    for (final status in values) {
      if (value == status.name) return status;
    }
    throw const FormatException('Invalid reimbursement status');
  }
}

const maxReceiptBytes = 1024 * 1024;

class FinanceRecord {
  FinanceRecord({
    required this.id,
    required this.categoryId,
    required this.type,
    required this.amountMinor,
    required this.occurredAt,
    this.note,
    this.reimbursement = ReimbursementStatus.none,
    this.receipt,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be blank.');
    }
    if (categoryId.trim().isEmpty) {
      throw ArgumentError.value(categoryId, 'categoryId', 'Must not be blank.');
    }
    if (amountMinor <= 0 || amountMinor > maxAmountMinor) {
      throw ArgumentError.value(
        amountMinor,
        'amountMinor',
        'Must be > 0 and <= $maxAmountMinor.',
      );
    }
    requireLocalDateTime(occurredAt, 'occurredAt');
    if (type == FinanceType.income &&
        (reimbursement != ReimbursementStatus.none || receipt != null)) {
      throw ArgumentError('Only expenses can contain reimbursement details.');
    }
    final image = receipt;
    if (image != null) {
      if (image.length > 4 * ((maxReceiptBytes + 2) ~/ 3)) {
        throw const FormatException('Receipt exceeds the size limit');
      }
      final bytes = base64Decode(image);
      final png =
          bytes.length >= 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4e &&
          bytes[3] == 0x47;
      final jpg =
          bytes.length >= 4 &&
          bytes[0] == 0xff &&
          bytes[1] == 0xd8 &&
          bytes[2] == 0xff;
      if (bytes.length > maxReceiptBytes || (!png && !jpg)) {
        throw const FormatException(
          'Receipt must be a JPEG or PNG within the size limit',
        );
      }
    }
  }

  final String id;
  final String categoryId;
  final FinanceType type;
  final int amountMinor;
  final DateTime occurredAt;
  final String? note;
  final ReimbursementStatus reimbursement;
  final String? receipt;

  FinanceRecord copyWith({
    String? categoryId,
    FinanceType? type,
    int? amountMinor,
    DateTime? occurredAt,
    Object? note = _unset,
    ReimbursementStatus? reimbursement,
    Object? receipt = _unset,
  }) {
    final nextType = type ?? this.type;
    return FinanceRecord(
      id: id,
      categoryId: categoryId ?? this.categoryId,
      type: type ?? this.type,
      amountMinor: amountMinor ?? this.amountMinor,
      occurredAt: occurredAt ?? this.occurredAt,
      note: identical(note, _unset) ? this.note : note as String?,
      reimbursement: nextType == FinanceType.income
          ? ReimbursementStatus.none
          : reimbursement ?? this.reimbursement,
      receipt: nextType == FinanceType.income
          ? null
          : identical(receipt, _unset)
          ? this.receipt
          : receipt as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'categoryId': categoryId,
    'type': financeTypeToJson(type),
    'amountMinor': amountMinor,
    'occurredAt': occurredAt.toIso8601String(),
    'note': note,
    if (reimbursement != ReimbursementStatus.none)
      'reimbursement': reimbursement.name,
    if (receipt != null) 'receipt': receipt,
  };

  factory FinanceRecord.fromJson(Map<String, dynamic> json) {
    requireExactJsonKeys(
      json,
      requiredKeys: const {
        'id',
        'categoryId',
        'type',
        'amountMinor',
        'occurredAt',
      },
      optionalKeys: const {'note', 'reimbursement', 'receipt'},
    );
    try {
      return FinanceRecord(
        id: readRequiredString(json, 'id'),
        categoryId: readRequiredString(json, 'categoryId'),
        type: financeTypeFromJson(json['type']),
        amountMinor: readRequiredInt(json, 'amountMinor'),
        occurredAt: readLocalDateTime(json['occurredAt']),
        note: readOptionalString(json, 'note'),
        reimbursement: ReimbursementStatus.decode(json['reimbursement']),
        receipt: readOptionalString(json, 'receipt'),
      );
    } on ArgumentError {
      throw const FormatException('Invalid FinanceRecord values.');
    }
  }
}

const Object _unset = Object();
