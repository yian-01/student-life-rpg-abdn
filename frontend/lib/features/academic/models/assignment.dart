import 'academic_json.dart';
import 'local_date.dart';

/// 作业。
///
/// 契约第 5 节字段：`String id、courseId、title；DateTime dueAt；String? description`。
///
/// 本阶段只完成模型、JSON 和校验，不扩展完整管理页面。
/// `dueAt` 是完整时间字段，JSON 使用本地 ISO 格式且保留微秒精度。
class Assignment {
  Assignment({
    required this.id,
    required this.courseId,
    required this.title,
    required this.dueAt,
    this.description,
  }) {
    validateNotBlank(id, 'id');
    validateNotBlank(courseId, 'courseId');
    validateNotBlank(title, 'title');
    if (dueAt.isUtc) {
      throw ArgumentError.value(dueAt, 'dueAt', 'Must be a local DateTime.');
    }
  }

  static const Set<String> jsonKeys = {
    'id',
    'courseId',
    'title',
    'dueAt',
    'description',
  };

  final String id;
  final String courseId;
  final String title;
  final DateTime dueAt;
  final String? description;

  Map<String, dynamic> toJson() => {
    'id': id,
    'courseId': courseId,
    'title': title,
    'dueAt': dueAt.toIso8601String(),
    // 可空字段 toJson 必须写入 null。
    'description': description,
  };

  factory Assignment.fromJson(Map<String, dynamic> json) {
    rejectUnknownKeys(json, jsonKeys, context: 'Assignment');
    final id = readRequiredString(json, 'id');
    final courseId = readRequiredString(json, 'courseId');
    final title = readRequiredString(json, 'title');
    final description = readNullableString(json, 'description');

    if (!json.containsKey('dueAt')) {
      throw const FormatException('Missing required field "dueAt".');
    }
    final dueAt = parseLocalDateTime(json['dueAt'], field: 'dueAt');

    return decodeWithArgumentErrors(
      () => Assignment(
        id: id,
        courseId: courseId,
        title: title,
        dueAt: dueAt,
        description: description,
      ),
    );
  }
}
