import 'time_range.dart';

enum ScheduleSourceType { course, event, task }

/// 日程展示项，由业务模型生成，不作为独立持久化实体。
class ScheduleItem {
  ScheduleItem({
    required this.id,
    required this.sourceId,
    required this.sourceType,
    required this.title,
    required this.range,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be blank.');
    }
    if (sourceId.trim().isEmpty) {
      throw ArgumentError.value(sourceId, 'sourceId', 'Must not be blank.');
    }
    if (title.trim().isEmpty) {
      throw ArgumentError.value(title, 'title', 'Must not be blank.');
    }
  }

  final String id;
  final String sourceId;
  final ScheduleSourceType sourceType;
  final String title;
  final TimeRange range;
}
