import '../../../../shared/models/time_range.dart';
import 'academic_json.dart';

/// 考试。
///
/// 契约第 5 节字段：`String id、courseId、title；TimeRange range；String? location`。
///
/// 本阶段只完成模型、JSON 和校验，不扩展完整管理页面。
/// `range` 复用公共 [TimeRange]，其构造器已保证本地时间且 `start < end`。
class Exam {
  Exam({
    required this.id,
    required this.courseId,
    required this.title,
    required this.range,
    this.location,
  }) {
    validateNotBlank(id, 'id');
    validateNotBlank(courseId, 'courseId');
    validateNotBlank(title, 'title');
  }

  static const Set<String> jsonKeys = {
    'id',
    'courseId',
    'title',
    'range',
    'location',
  };

  final String id;
  final String courseId;
  final String title;
  final TimeRange range;
  final String? location;

  Map<String, dynamic> toJson() => {
    'id': id,
    'courseId': courseId,
    'title': title,
    'range': range.toJson(),
    // 可空字段 toJson 必须写入 null。
    'location': location,
  };

  factory Exam.fromJson(Map<String, dynamic> json) {
    rejectUnknownKeys(json, jsonKeys, context: 'Exam');
    final id = readRequiredString(json, 'id');
    final courseId = readRequiredString(json, 'courseId');
    final title = readRequiredString(json, 'title');
    final location = readNullableString(json, 'location');
    final range = TimeRange.fromJson(readRequiredObject(json, 'range'));

    return decodeWithArgumentErrors(
      () => Exam(
        id: id,
        courseId: courseId,
        title: title,
        range: range,
        location: location,
      ),
    );
  }
}
