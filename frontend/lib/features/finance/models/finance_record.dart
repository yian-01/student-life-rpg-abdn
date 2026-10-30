import 'finance_type.dart';
import 'json_map.dart';
import 'local_date_time_json.dart';
import 'money.dart';

class FinanceRecord {
  FinanceRecord({
    required this.id,
    required this.categoryId,
    required this.type,
    required this.amountMinor,
    required this.occurredAt,
    this.note,
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
  }

  final String id;
  final String categoryId;
  final FinanceType type;
  final int amountMinor;
  final DateTime occurredAt;
  final String? note;

  FinanceRecord copyWith({
    String? categoryId,
    FinanceType? type,
    int? amountMinor,
    DateTime? occurredAt,
    Object? note = _unset,
  }) {
    return FinanceRecord(
      id: id,
      categoryId: categoryId ?? this.categoryId,
      type: type ?? this.type,
      amountMinor: amountMinor ?? this.amountMinor,
      occurredAt: occurredAt ?? this.occurredAt,
      note: identical(note, _unset) ? this.note : note as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'categoryId': categoryId,
    'type': financeTypeToJson(type),
    'amountMinor': amountMinor,
    'occurredAt': occurredAt.toIso8601String(),
    'note': note,
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
      optionalKeys: const {'note'},
    );
    try {
      return FinanceRecord(
        id: readRequiredString(json, 'id'),
        categoryId: readRequiredString(json, 'categoryId'),
        type: financeTypeFromJson(json['type']),
        amountMinor: readRequiredInt(json, 'amountMinor'),
        occurredAt: readLocalDateTime(json['occurredAt']),
        note: readOptionalString(json, 'note'),
      );
    } on ArgumentError {
      throw const FormatException('Invalid FinanceRecord values.');
    }
  }
}

const Object _unset = Object();
