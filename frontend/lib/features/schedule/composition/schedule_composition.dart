import '../../../shared/models/schedule_item.dart';
import '../../../shared/models/time_range.dart';
import '../../../shared/repositories/entity_repository.dart';
import '../models/event.dart';
import '../models/task.dart';
import '../repositories/in_memory_event_repository.dart';
import '../repositories/in_memory_task_repository.dart';
import '../repositories/task_repository.dart';
import '../services/day_schedule_service.dart';

/// I 模块组合入口：把 Task/Event 仓库和课程发生项回调组装为 [DayScheduleService]。
///
/// 组合根（A）应使用公开构造注入真实仓库（例如 #7 的持久化 TaskRepository）；
/// [ScheduleComposition.inMemoryDemo] 仅供原型演示，数据重启不保留。
class ScheduleComposition implements DayScheduleLoader {
  ScheduleComposition({
    required this.taskRepository,
    required this.eventRepository,
    required this.courseOccurrencesForDate,
  }) : _service = DayScheduleService(
         taskRepository: taskRepository,
         eventRepository: eventRepository,
         courseOccurrencesForDate: courseOccurrencesForDate,
       ),
       _isDemo = false;

  /// 原型演示装配：内存仓库 + 每周一固定课程发生项（标注为演示数据）。
  factory ScheduleComposition.inMemoryDemo() {
    final taskRepository = InMemoryTaskRepository();
    final eventRepository = InMemoryEventRepository();
    return ScheduleComposition._demo(
      taskRepository: taskRepository,
      eventRepository: eventRepository,
    );
  }

  ScheduleComposition._demo({
    required InMemoryTaskRepository taskRepository,
    required InMemoryEventRepository eventRepository,
  }) : taskRepository = taskRepository,
       eventRepository = eventRepository,
       courseOccurrencesForDate = demoCourseOccurrences,
       _isDemo = true,
       _service = DayScheduleService(
         taskRepository: taskRepository,
         eventRepository: eventRepository,
         courseOccurrencesForDate: demoCourseOccurrences,
       );

  final TaskRepository taskRepository;
  final EntityRepository<Event> eventRepository;
  final CourseOccurrencesForDate courseOccurrencesForDate;
  final DayScheduleService _service;
  final bool _isDemo;
  Future<void>? _pendingDemoSeed;

  @override
  Future<DaySchedule> loadDay(DateTime date) async {
    if (_isDemo) {
      await (_pendingDemoSeed ??= _seedDemoData());
    }
    return _service.loadDay(date);
  }

  Future<void> _seedDemoData() async {
    final day = _startOfDay(DateTime.now());
    await eventRepository.insert(
      Event(
        id: 'demo-event-team-sync',
        title: '小组会议',
        range: TimeRange(
          start: day.add(const Duration(hours: 9)),
          end: day.add(const Duration(hours: 10)),
        ),
      ),
    );
    await taskRepository.insert(
      Task(
        id: 'demo-task-read-chapter',
        title: '阅读第一章',
        estimatedMinutes: 45,
        scheduledRange: TimeRange(
          start: day.add(const Duration(hours: 20)),
          end: day.add(const Duration(hours: 21)),
        ),
      ),
    );
    await taskRepository.insert(
      Task(
        id: 'demo-task-notes',
        title: '整理笔记',
        estimatedMinutes: 30,
        dueAt: day.add(const Duration(days: 2)),
      ),
    );
    await taskRepository.insert(
      Task(
        id: 'demo-task-homework',
        title: '已完成作业',
        estimatedMinutes: 60,
        isCompleted: true,
      ),
    );
  }
}

/// 演示用课程发生项：只在周一返回一门固定课程。
Future<List<ScheduleItem>> demoCourseOccurrences(DateTime date) async {
  if (date.weekday != DateTime.monday) {
    return const <ScheduleItem>[];
  }
  return <ScheduleItem>[
    ScheduleItem(
      id: 'course:demo-java:0:${_compactDate(date)}',
      sourceId: 'demo-java',
      sourceType: ScheduleSourceType.course,
      title: 'Java 程序设计（演示）',
      range: TimeRange(
        start: date.add(const Duration(hours: 8)),
        end: date.add(const Duration(hours: 10)),
      ),
    ),
  ];
}

DateTime _startOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _compactDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';
}
