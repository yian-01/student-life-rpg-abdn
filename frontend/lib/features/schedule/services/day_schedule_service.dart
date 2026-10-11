import '../../../shared/models/schedule_item.dart';
import '../../../shared/repositories/entity_repository.dart';
import '../models/event.dart';
import '../models/task.dart';
import 'task_schedule_adapter.dart';

/// 课程发生项回调：由组合根把 G 的同步单课程算法适配为异步查询。
typedef CourseOccurrencesForDate =
    Future<List<ScheduleItem>> Function(DateTime date);

/// 页面/Controller 依赖的加载接口，便于注入真实组合或测试替身。
abstract interface class DayScheduleLoader {
  Future<DaySchedule> loadDay(DateTime date);
}

/// I 单日日程服务：合并课程、事件和已排程任务，按本地半开区间过滤并排序。
class DayScheduleService implements DayScheduleLoader {
  DayScheduleService({
    required this.taskRepository,
    required this.eventRepository,
    required this.courseOccurrencesForDate,
    this.adapter = const TaskScheduleAdapter(),
  });

  final EntityRepository<Task> taskRepository;
  final EntityRepository<Event> eventRepository;
  final CourseOccurrencesForDate courseOccurrencesForDate;
  final TaskScheduleAdapter adapter;

  @override
  Future<DaySchedule> loadDay(DateTime date) async {
    if (date.isUtc) {
      throw ArgumentError.value(date, 'date', 'must be local civil time');
    }

    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = DateTime(date.year, date.month, date.day + 1);

    final courseItems = await courseOccurrencesForDate(dayStart);
    final events = await eventRepository.list();
    final tasks = await taskRepository.list();

    final items =
        <ScheduleItem>[
            ...courseItems,
            ...events.map(adapter.eventToScheduleItem),
            ...tasks.map(adapter.taskToScheduleItem).whereType<ScheduleItem>(),
          ].where((item) {
            return item.range.start.isBefore(dayEnd) &&
                item.range.end.isAfter(dayStart);
          }).toList()
          ..sort(_compareScheduleItems);

    final unscheduledTasks =
        tasks
            .where((task) => !task.isCompleted && task.scheduledRange == null)
            .toList()
          ..sort(_compareUnscheduledTasks);

    final completedTaskIds = tasks
        .where((task) => task.isCompleted)
        .map((task) => task.id)
        .toSet();

    return DaySchedule(
      date: dayStart,
      items: items,
      unscheduledTasks: unscheduledTasks,
      completedTaskIds: completedTaskIds,
    );
  }
}

/// 单日日程结果：主数据只来自 `items`、`unscheduledTasks` 和 `completedTaskIds`。
class DaySchedule {
  DaySchedule({
    required DateTime date,
    required List<ScheduleItem> items,
    required List<Task> unscheduledTasks,
    required Set<String> completedTaskIds,
  }) : date = DateTime(date.year, date.month, date.day),
       items = List<ScheduleItem>.unmodifiable(items),
       unscheduledTasks = List<Task>.unmodifiable(unscheduledTasks),
       completedTaskIds = Set<String>.unmodifiable(completedTaskIds);

  final DateTime date;
  final List<ScheduleItem> items;
  final List<Task> unscheduledTasks;
  final Set<String> completedTaskIds;

  DateTime get dayStart => date;

  DateTime get dayEnd => DateTime(date.year, date.month, date.day + 1);

  /// 跨日项目保留原始完整 range，仅在展示当天时标记。
  bool isCrossDay(ScheduleItem item) {
    return item.range.start.isBefore(dayStart) ||
        item.range.end.isAfter(dayEnd);
  }

  bool isCompletedTask(ScheduleItem item) {
    return item.sourceType == ScheduleSourceType.task &&
        completedTaskIds.contains(item.sourceId);
  }
}

int _compareScheduleItems(ScheduleItem a, ScheduleItem b) {
  final start = a.range.start.compareTo(b.range.start);
  if (start != 0) {
    return start;
  }

  final end = a.range.end.compareTo(b.range.end);
  if (end != 0) {
    return end;
  }

  final sourceType = _sourceTypeOrder(
    a.sourceType,
  ).compareTo(_sourceTypeOrder(b.sourceType));
  if (sourceType != 0) {
    return sourceType;
  }

  return a.id.compareTo(b.id);
}

int _sourceTypeOrder(ScheduleSourceType sourceType) {
  switch (sourceType) {
    case ScheduleSourceType.course:
      return 0;
    case ScheduleSourceType.event:
      return 1;
    case ScheduleSourceType.task:
      return 2;
  }
}

int _compareUnscheduledTasks(Task a, Task b) {
  final aDueAt = a.dueAt;
  final bDueAt = b.dueAt;
  if (aDueAt == null && bDueAt != null) {
    return 1;
  }
  if (aDueAt != null && bDueAt == null) {
    return -1;
  }
  if (aDueAt != null && bDueAt != null) {
    final dueAt = aDueAt.compareTo(bDueAt);
    if (dueAt != 0) {
      return dueAt;
    }
  }
  return a.id.compareTo(b.id);
}
