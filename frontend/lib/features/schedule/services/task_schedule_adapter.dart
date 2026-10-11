import '../../../shared/models/schedule_item.dart';
import '../models/event.dart';
import '../models/task.dart';

/// 把 Event 和已排程 Task 归一为共享 [ScheduleItem]。
/// 未排程 Task 不产生日程项；本适配器只做映射，不创建占位时间。
class TaskScheduleAdapter {
  const TaskScheduleAdapter();

  ScheduleItem eventToScheduleItem(Event event) {
    return ScheduleItem(
      id: buildItemId(ScheduleSourceType.event, event.id, event.range.start),
      sourceId: event.id,
      sourceType: ScheduleSourceType.event,
      title: event.title,
      range: event.range,
    );
  }

  ScheduleItem? taskToScheduleItem(Task task) {
    final range = task.scheduledRange;
    if (range == null) {
      return null;
    }
    return ScheduleItem(
      id: buildItemId(ScheduleSourceType.task, task.id, range.start),
      sourceId: task.id,
      sourceType: ScheduleSourceType.task,
      title: task.title,
      range: range,
    );
  }

  /// 派生日程项 ID：来源类型、编码后的 sourceId、日期与开始时间。
  /// 小数部分使用 millisecond*1000+microsecond 补齐 6 位，避免同秒不同起点碰撞。
  static String buildItemId(
    ScheduleSourceType sourceType,
    String sourceId,
    DateTime occurredAt,
  ) {
    final date =
        '${occurredAt.year.toString().padLeft(4, '0')}'
        '${occurredAt.month.toString().padLeft(2, '0')}'
        '${occurredAt.day.toString().padLeft(2, '0')}';
    final fraction = (occurredAt.millisecond * 1000 + occurredAt.microsecond)
        .toString()
        .padLeft(6, '0');
    final time =
        '${occurredAt.hour.toString().padLeft(2, '0')}'
        '${occurredAt.minute.toString().padLeft(2, '0')}'
        '${occurredAt.second.toString().padLeft(2, '0')}'
        '$fraction';
    return '${sourceType.name}:${Uri.encodeComponent(sourceId)}:$date:$time';
  }
}
