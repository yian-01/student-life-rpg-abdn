import 'finance_type.dart';
import 'json_map.dart';

class FinanceCategory {
  FinanceCategory({required this.id, required this.name, required this.type}) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be blank.');
    }
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Must not be blank.');
    }
  }

  final String id;
  final String name;
  final FinanceType type;

  FinanceCategory copyWith({String? name, FinanceType? type}) {
    return FinanceCategory(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': financeTypeToJson(type),
  };

  factory FinanceCategory.fromJson(Map<String, dynamic> json) {
    requireExactJsonKeys(json, requiredKeys: const {'id', 'name', 'type'});
    try {
      return FinanceCategory(
        id: readRequiredString(json, 'id'),
        name: readRequiredString(json, 'name'),
        type: financeTypeFromJson(json['type']),
      );
    } on ArgumentError {
      throw const FormatException('Invalid FinanceCategory values.');
    }
  }
}
