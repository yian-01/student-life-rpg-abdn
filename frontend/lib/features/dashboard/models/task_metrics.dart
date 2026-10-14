import '../../../shared/models/time_range.dart';

/// 任务分区指标（契约第 11 节）。
///
/// - totalCount：全部当前任务数。
/// - completedCount：其中已完成数。
/// - todayPendingCount：仅统计未完成且与当天相关的任务。
/// - completionRate：completedCount/totalCount；totalCount 为 0 时为 null，
///   显示层据此呈现“暂无任务”。
class TaskMetrics {
  TaskMetrics({
    required this.totalCount,
    required this.completedCount,
    required this.todayPendingCount,
    required this.completionRate,
  }) {
    if (totalCount < 0) {
      throw ArgumentError.value(totalCount, 'totalCount', '不能为负数。');
    }
    if (completedCount < 0 || completedCount > totalCount) {
      throw ArgumentError.value(
        completedCount,
        'completedCount',
        '必须在 0 至 totalCount 之间。',
      );
    }
    if (todayPendingCount < 0 ||
        todayPendingCount > totalCount - completedCount) {
      throw ArgumentError.value(
        todayPendingCount,
        'todayPendingCount',
        '必须在 0 至 (totalCount - completedCount) 之间。',
      );
    }
    if (totalCount == 0) {
      if (completionRate != null) {
        throw ArgumentError('总任务数为 0 时 completionRate 必须为 null。');
      }
      return;
    }
    final rate = completionRate;
    if (rate == null || !rate.isFinite || rate < 0 || rate > 1) {
      throw ArgumentError.value(
        completionRate,
        'completionRate',
        '总任务数大于 0 时必须是 0 至 1 之间的有限数。',
      );
    }
    final expected = completedCount / totalCount;
    if ((rate - expected).abs() > 1e-9) {
      throw ArgumentError.value(
        completionRate,
        'completionRate',
        '必须等于 completedCount/totalCount。',
      );
    }
  }

  final int totalCount;
  final int completedCount;
  final int todayPendingCount;

  /// 完成率；总任务数为 0 时为 null。
  final double? completionRate;

  @override
  bool operator ==(Object other) =>
      other is TaskMetrics &&
      other.totalCount == totalCount &&
      other.completedCount == completedCount &&
      other.todayPendingCount == todayPendingCount &&
      other.completionRate == completionRate;

  @override
  int get hashCode => Object.hash(
    totalCount,
    completedCount,
    todayPendingCount,
    completionRate,
  );

  @override
  String toString() =>
      'TaskMetrics(total: $totalCount, completed: $completedCount, '
      'todayPending: $todayPendingCount, rate: $completionRate)';
}

/// 参与指标统计的原始任务字段。
///
/// #9 的 Task 合并前，用该记录表达任务；Task 合并后，调用方将
/// Task 的同名字段逐一映射为该记录即可，不复制或替造 Task 类型。
typedef TaskMetricInput = ({
  String id,
  bool isCompleted,
  TimeRange? scheduledRange,
  DateTime? dueAt,
});

/// 基于原始任务字段计算任务指标（Issue #14 指标规则）。
///
/// - 完成率 = 已完成 / 全部；总数为 0 时为 null。
/// - 今日待办仅统计未完成任务：scheduledRange 与 [today] 所在当天相交，
///   或 dueAt 落在当天；同时满足两个条件时按 id 去重。
/// - 无安排且无当天截止时间的任务不计入今日待办。
/// - [today] 与 dueAt 必须是本地时间；日期边界为当天本地午夜至次日本地午夜。
TaskMetrics computeTaskMetrics({
  required Iterable<TaskMetricInput> tasks,
  required DateTime today,
}) {
  if (today.isUtc) {
    throw ArgumentError.value(today, 'today', '必须是本地时间。');
  }
  final dayStart = DateTime(today.year, today.month, today.day);
  final dayEnd = DateTime(today.year, today.month, today.day + 1);

  final taskList = tasks.toList();
  // 在过滤已完成任务、判断安排相交之前统一校验 dueAt：
  // 任何任务携带非 null 的 UTC dueAt 都拒绝，避免已完成任务 continue
  // 或安排相交 return true 绕过 UTC 校验（审核 7b10899 整改）。
  for (final task in taskList) {
    final due = task.dueAt;
    if (due != null && due.isUtc) {
      throw ArgumentError.value(due, 'dueAt', '必须是本地时间。');
    }
  }

  var completedCount = 0;
  final todayPendingIds = <String>{};
  for (final task in taskList) {
    if (task.isCompleted) {
      completedCount++;
      continue;
    }
    if (_isTodayPending(task: task, dayStart: dayStart, dayEnd: dayEnd)) {
      todayPendingIds.add(task.id);
    }
  }

  final total = taskList.length;
  return TaskMetrics(
    totalCount: total,
    completedCount: completedCount,
    todayPendingCount: todayPendingIds.length,
    completionRate: total == 0 ? null : completedCount / total,
  );
}

bool _isTodayPending({
  required TaskMetricInput task,
  required DateTime dayStart,
  required DateTime dayEnd,
}) {
  final range = task.scheduledRange;
  if (range != null) {
    // 半开区间相交：range.start < dayEnd && dayStart < range.end。
    if (range.start.isBefore(dayEnd) && dayStart.isBefore(range.end)) {
      return true;
    }
  }
  final due = task.dueAt;
  if (due != null && !due.isBefore(dayStart) && due.isBefore(dayEnd)) {
    return true;
  }
  return false;
}
