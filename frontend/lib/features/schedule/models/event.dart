import '../../../shared/models/time_range.dart';
import 'local_datetime_json.dart';

const Object _unset = Object();

const Set<String> _eventJsonKeys = <String>{
  'id',
  'title',
  'range',
  'description',
};

/// H 的事件模型：不可变，遵守共享 [TimeRange] 的本地半开区间规则。
///
/// Event 不包含任务完成状态。
class Event {
  Event({
    required this.id,
    required this.title,
    required this.range,
    this.description,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (title.trim().isEmpty) {
      throw ArgumentError.value(title, 'title', 'must not be empty');
    }
  }

  final String id;
  final String title;
  final TimeRange range;
  final String? description;

  /// 返回新对象；不提供修改 `id` 的能力，`description` 可用 `null` 清空。
  Event copyWith({
    String? title,
    TimeRange? range,
    Object? description = _unset,
  }) {
    final nextDescription = identical(description, _unset)
        ? this.description
        : description;
    if (nextDescription != null && nextDescription is! String) {
      throw ArgumentError.value(
        nextDescription,
        'description',
        'must be String?',
      );
    }

    return Event(
      id: id,
      title: title ?? this.title,
      range: range ?? this.range,
      description: nextDescription as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'range': range.toJson(),
      'description': description,
    };
  }

  /// 契约：`range` 必填；可空字段缺失按 null 处理；字段错误抛 [FormatException]。
  factory Event.fromJson(Map<String, dynamic> json) {
    rejectUnknownKeys(json, _eventJsonKeys, 'Event');
    final id = json['id'];
    final title = json['title'];
    final description = json['description'];
    if (id is! String || title is! String) {
      throw const FormatException('Event requires String id and String title');
    }
    if (description != null && description is! String) {
      throw const FormatException('Event.description must be a string or null');
    }

    try {
      return Event(
        id: id,
        title: title,
        range: decodeTimeRange(json['range'], 'Event.range'),
        description: description as String?,
      );
    } on ArgumentError catch (error) {
      throw FormatException(
        'Event contains an invalid value: ${error.message}',
      );
    }
  }

  @override
  bool operator ==(Object other) {
    return other is Event &&
        other.id == id &&
        other.title == title &&
        other.range.start == range.start &&
        other.range.end == range.end &&
        other.description == description;
  }

  @override
  int get hashCode =>
      Object.hash(id, title, range.start, range.end, description);

  @override
  String toString() => 'Event($id)';
}
