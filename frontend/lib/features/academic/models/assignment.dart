import 'academic_json.dart';
import 'local_date.dart';

enum AssignmentStatus {
  notStarted('未开始'),
  inProgress('进行中'),
  submitted('已提交');

  const AssignmentStatus(this.label);
  final String label;
}

AssignmentStatus _readStatus(Object? value) {
  if (value == null) return AssignmentStatus.notStarted;
  for (final status in AssignmentStatus.values) {
    if (status.name == value) return status;
  }
  throw const FormatException('Unknown assignment status');
}

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
    this.status = AssignmentStatus.notStarted,
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
    'status',
  };

  final String id;
  final String courseId;
  final String title;
  final DateTime dueAt;
  final String? description;
  final AssignmentStatus status;

  Map<String, dynamic> toJson() => {
    'id': id,
    'courseId': courseId,
    'title': title,
    'dueAt': dueAt.toIso8601String(),
    // 可空字段 toJson 必须写入 null。
    'description': description,
    if (status != AssignmentStatus.notStarted) 'status': status.name,
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
        status: _readStatus(json['status']),
      ),
    );
  }
}
