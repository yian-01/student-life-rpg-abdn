import '../../../shared/models/time_range.dart';
import 'local_datetime_json.dart';

const Object _unset = Object();

const Set<String> _taskJsonKeys = <String>{
  'id',
  'title',
  'estimatedMinutes',
  'isCompleted',
  'dueAt',
  'scheduledRange',
  'priority',
  'steps',
  'note',
};

enum TaskPriority {
  low('低'),
  normal('普通'),
  high('高');

  const TaskPriority(this.label);
  final String label;
}

class TaskStep {
  TaskStep({required this.id, required this.title, this.done = false}) {
    if (id.trim().isEmpty || title.trim().isEmpty) {
      throw ArgumentError('Blank task step');
    }
  }

  final String id;
  final String title;
  final bool done;

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'done': done};

  factory TaskStep.fromJson(Object? json) {
    if (json is! Map<String, dynamic> || json.length != 3) {
      throw const FormatException('Invalid task step');
    }
    final id = json['id'];
    final title = json['title'];
    final done = json['done'];
    if (id is! String || title is! String || done is! bool) {
      throw const FormatException('Invalid task step');
    }
    return TaskStep(id: id, title: title, done: done);
  }

  @override
  bool operator ==(Object other) =>
      other is TaskStep &&
      other.id == id &&
      other.title == title &&
      other.done == done;

  @override
  int get hashCode => Object.hash(id, title, done);
}

TaskPriority _readPriority(Object? value) {
  if (value == null) return TaskPriority.normal;
  for (final priority in TaskPriority.values) {
    if (priority.name == value) return priority;
  }
  throw const FormatException('Unknown task priority');
}

/// H 的任务模型：不可变，ID 不可修改，时间使用本地民用时间。
///
/// `dueAt` 与 `scheduledRange` 相互独立，任何转换都不得由 `dueAt` 反推排程，
/// 也不得把排程结束当作截止时间。
class Task {
  Task({
    required this.id,
    required this.title,
    required this.estimatedMinutes,
    this.isCompleted = false,
    this.dueAt,
    this.scheduledRange,
    this.note,
    this.priority = TaskPriority.normal,
    List<TaskStep> steps = const [],
  }) : steps = List.unmodifiable(steps) {
    if (this.steps.map((step) => step.id).toSet().length != this.steps.length) {
      throw ArgumentError('Duplicate task step ID');
    }
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (title.trim().isEmpty) {
      throw ArgumentError.value(title, 'title', 'must not be empty');
    }
    if (estimatedMinutes <= 0) {
      throw ArgumentError.value(
        estimatedMinutes,
        'estimatedMinutes',
        'must be a positive integer',
      );
    }
    final due = dueAt;
    if (due != null) {
      encodeLocalDateTime(due, 'dueAt');
    }
  }

  final String id;
  final String title;
  final int estimatedMinutes;
  final bool isCompleted;
  final DateTime? dueAt;
  final TimeRange? scheduledRange;
  final String? note;
  final TaskPriority priority;
  final List<TaskStep> steps;

  /// 返回新对象；不提供修改 `id` 的能力，可空字段用 `null` 显式清空。
  Task copyWith({
    String? title,
    int? estimatedMinutes,
    bool? isCompleted,
    Object? dueAt = _unset,
    Object? scheduledRange = _unset,
    Object? note = _unset,
    TaskPriority? priority,
    List<TaskStep>? steps,
  }) {
    final nextDueAt = identical(dueAt, _unset) ? this.dueAt : dueAt;
    if (nextDueAt != null && nextDueAt is! DateTime) {
      throw ArgumentError.value(nextDueAt, 'dueAt', 'must be DateTime?');
    }

    final nextScheduledRange = identical(scheduledRange, _unset)
        ? this.scheduledRange
        : scheduledRange;
    if (nextScheduledRange != null && nextScheduledRange is! TimeRange) {
      throw ArgumentError.value(
        nextScheduledRange,
        'scheduledRange',
        'must be TimeRange?',
      );
    }

    return Task(
      id: id,
      title: title ?? this.title,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      isCompleted: isCompleted ?? this.isCompleted,
      dueAt: nextDueAt as DateTime?,
      scheduledRange: nextScheduledRange as TimeRange?,
      note: identical(note, _unset) ? this.note : note as String?,
      priority: priority ?? this.priority,
      steps: steps ?? this.steps,
    );
  }

  Map<String, dynamic> toJson() {
    final due = dueAt;
    final scheduled = scheduledRange;
    return {
      'id': id,
      'title': title,
      'estimatedMinutes': estimatedMinutes,
      'isCompleted': isCompleted,
      'dueAt': due == null ? null : encodeLocalDateTime(due, 'dueAt'),
      'scheduledRange': scheduled?.toJson(),
      if (note != null) 'note': note,
      if (priority != TaskPriority.normal) 'priority': priority.name,
      if (steps.isNotEmpty)
        'steps': steps.map((step) => step.toJson()).toList(),
    };
  }

  /// 契约：`isCompleted` 必填且必须为 bool；可空字段缺失按 null 处理；
  /// 领域值非法时把构造校验错误转换成 [FormatException]。
  factory Task.fromJson(Map<String, dynamic> json) {
    rejectUnknownKeys(json, _taskJsonKeys, 'Task');
    final id = json['id'];
    final title = json['title'];
    final estimatedMinutes = json['estimatedMinutes'];
    final isCompleted = json['isCompleted'];
    if (id is! String ||
        title is! String ||
        estimatedMinutes is! int ||
        isCompleted is! bool) {
      throw const FormatException(
        'Task requires String id, String title, int estimatedMinutes and '
        'bool isCompleted',
      );
    }

    final dueAtValue = json['dueAt'];
    final scheduledRangeValue = json['scheduledRange'];
    final dueAt = dueAtValue == null
        ? null
        : decodeLocalDateTime(dueAtValue, 'Task.dueAt');
    final scheduledRange = scheduledRangeValue == null
        ? null
        : decodeTimeRange(scheduledRangeValue, 'Task.scheduledRange');

    final rawSteps = json['steps'];
    final note = json['note'];
    if ((rawSteps != null && rawSteps is! List) ||
        (note != null && note is! String)) {
      throw const FormatException('Invalid task note or steps');
    }
    try {
      return Task(
        id: id,
        title: title,
        estimatedMinutes: estimatedMinutes,
        isCompleted: isCompleted,
        dueAt: dueAt,
        scheduledRange: scheduledRange,
        note: note as String?,
        priority: _readPriority(json['priority']),
        steps: (rawSteps as List?)?.map(TaskStep.fromJson).toList() ?? [],
      );
    } on ArgumentError catch (error) {
      throw FormatException('Task contains an invalid value: ${error.message}');
    }
  }

  @override
  bool operator ==(Object other) {
    return other is Task &&
        other.id == id &&
        other.title == title &&
        other.estimatedMinutes == estimatedMinutes &&
        other.isCompleted == isCompleted &&
        other.dueAt == dueAt &&
        other.note == note &&
        other.priority == priority &&
        other.steps.length == steps.length &&
        Iterable<int>.generate(
          steps.length,
        ).every((i) => other.steps[i] == steps[i]) &&
        _sameRange(other.scheduledRange, scheduledRange);
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    estimatedMinutes,
    isCompleted,
    dueAt,
    scheduledRange?.start,
    scheduledRange?.end,
    note,
    priority,
    Object.hashAll(steps),
  );

  @override
  String toString() => 'Task($id)';
}

bool _sameRange(TimeRange? a, TimeRange? b) {
  if (identical(a, b)) {
    return true;
  }
  return a != null && b != null && a.start == b.start && a.end == b.end;
}
