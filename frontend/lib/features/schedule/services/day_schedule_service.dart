import '../../../shared/models/schedule_item.dart';
import '../../../shared/repositories/entity_repository.dart';
import '../../academic/models/assignment.dart';
import '../../academic/models/exam.dart';
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

/// Loading failures are carried with the partial result, never disguised as emptiness.
enum ScheduleDataSource { courses, events, tasks, exams, assignments }

/// 合并课程、事件、已排程任务和考试；作业截止独立呈现。
class DayScheduleService implements DayScheduleLoader {
  DayScheduleService({
    required this.taskRepository,
    required this.eventRepository,
    required this.courseOccurrencesForDate,
    this.examRepository,
    this.assignmentRepository,
    this.adapter = const TaskScheduleAdapter(),
  });

  final EntityRepository<Task> taskRepository;
  final EntityRepository<Event> eventRepository;
  final CourseOccurrencesForDate courseOccurrencesForDate;
  final EntityRepository<Exam>? examRepository;
  final EntityRepository<Assignment>? assignmentRepository;
  final TaskScheduleAdapter adapter;

  @override
  Future<DaySchedule> loadDay(DateTime date) async {
    if (date.isUtc) {
      throw ArgumentError.value(date, 'date', 'must be local civil time');
    }

    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = DateTime(date.year, date.month, date.day + 1);

    final errors = <ScheduleDataSource, Object>{};
    Future<List<T>> read<T>(
      ScheduleDataSource source,
      Future<List<T>> Function() query,
    ) async {
      try {
        return await query();
      } catch (error) {
        errors[source] = error;
        return <T>[];
      }
    }

    // Attach error handlers immediately, including when repositories share a queue.
    final courseRead = read(
      ScheduleDataSource.courses,
      () => courseOccurrencesForDate(dayStart),
    );
    final eventRead = read(ScheduleDataSource.events, eventRepository.list);
    final taskRead = read(ScheduleDataSource.tasks, taskRepository.list);
    final examRead = examRepository == null
        ? Future.value(<Exam>[])
        : read(ScheduleDataSource.exams, examRepository!.list);
    final assignmentRead = assignmentRepository == null
        ? Future.value(<Assignment>[])
        : read(ScheduleDataSource.assignments, assignmentRepository!.list);
    final courseItems = await courseRead;
    final events = await eventRead;
    final tasks = await taskRead;
    final exams = await examRead;
    final assignments = await assignmentRead;

    final items =
        <ScheduleItem>[
            ...courseItems,
            ...events.map(adapter.eventToScheduleItem),
            ...tasks.map(adapter.taskToScheduleItem).whereType<ScheduleItem>(),
            ...exams.map(adapter.examToScheduleItem),
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

    final deadlines =
        assignments
            .where(
              (assignment) =>
                  !assignment.dueAt.isBefore(dayStart) &&
                  assignment.dueAt.isBefore(dayEnd),
            )
            .toList()
          ..sort((a, b) {
            final time = a.dueAt.compareTo(b.dueAt);
            return time != 0 ? time : a.id.compareTo(b.id);
          });

    return DaySchedule(
      date: dayStart,
      items: items,
      unscheduledTasks: unscheduledTasks,
      completedTaskIds: completedTaskIds,
      completedTasks: tasks.where((task) => task.isCompleted).toList(),
      assignmentDeadlines: deadlines,
      errors: errors,
    );
  }
}

/// 不可变日程快照；assignmentDeadlines 是截止点，不进入时段冲突。
class DaySchedule {
  DaySchedule({
    required DateTime date,
    required List<ScheduleItem> items,
    required List<Task> unscheduledTasks,
    required Set<String> completedTaskIds,
    List<Task> completedTasks = const [],
    List<Assignment> assignmentDeadlines = const [],
    Map<ScheduleDataSource, Object> errors = const {},
  }) : date = DateTime(date.year, date.month, date.day),
       items = List<ScheduleItem>.unmodifiable(items),
       unscheduledTasks = List<Task>.unmodifiable(unscheduledTasks),
       completedTaskIds = Set<String>.unmodifiable(completedTaskIds),
       completedTasks = List<Task>.unmodifiable(completedTasks),
       assignmentDeadlines = List<Assignment>.unmodifiable(assignmentDeadlines),
       errors = Map<ScheduleDataSource, Object>.unmodifiable(errors);

  final DateTime date;
  final List<ScheduleItem> items;
  final List<Task> unscheduledTasks;
  final Set<String> completedTaskIds;
  final List<Task> completedTasks;
  final List<Assignment> assignmentDeadlines;
  final Map<ScheduleDataSource, Object> errors;

  /// Preserve the same day's last known data on failed reads/recovery. The error
  /// remains visible; successful sources always replace their previous values.
  DaySchedule retainingFailedSources(DaySchedule? previous) {
    if (previous == null || previous.date != date || errors.isEmpty) {
      return this;
    }
    bool failed(ScheduleItem item) =>
        errors.containsKey(switch (item.sourceType) {
          ScheduleSourceType.course => ScheduleDataSource.courses,
          ScheduleSourceType.event => ScheduleDataSource.events,
          ScheduleSourceType.task => ScheduleDataSource.tasks,
          ScheduleSourceType.exam => ScheduleDataSource.exams,
        });
    final merged = [
      ...items.where((item) => !failed(item)),
      ...previous.items.where(failed),
    ]..sort(_compareScheduleItems);
    final tasksFailed = errors.containsKey(ScheduleDataSource.tasks);
    return DaySchedule(
      date: date,
      items: merged,
      unscheduledTasks: tasksFailed
          ? previous.unscheduledTasks
          : unscheduledTasks,
      completedTaskIds: tasksFailed
          ? previous.completedTaskIds
          : completedTaskIds,
      completedTasks: tasksFailed ? previous.completedTasks : completedTasks,
      assignmentDeadlines: errors.containsKey(ScheduleDataSource.assignments)
          ? previous.assignmentDeadlines
          : assignmentDeadlines,
      errors: errors,
    );
  }

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
    case ScheduleSourceType.exam:
      return 3;
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
