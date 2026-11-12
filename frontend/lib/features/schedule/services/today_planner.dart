import '../../../shared/models/time_range.dart';
import '../models/task.dart';
import '../repositories/task_repository.dart';
import 'day_schedule_service.dart';

/// Find the first usable interval today, including ongoing and overlapping
/// appointments. Assignments are deadlines, so they do not block time.
TimeRange? suggestTaskTime(DaySchedule schedule, Task task, DateTime now) {
  if (schedule.errors.keys.any(
        (source) => source != ScheduleDataSource.assignments,
      ) ||
      task.isCompleted ||
      task.scheduledRange != null ||
      !now.isBefore(schedule.dayEnd)) {
    return null;
  }
  final start = now.isBefore(schedule.dayStart) ? schedule.dayStart : now;
  final dueAt = task.dueAt;
  final limit =
      dueAt != null && dueAt.isAfter(start) && dueAt.isBefore(schedule.dayEnd)
      ? dueAt
      : schedule.dayEnd;
  if (task.estimatedMinutes > limit.difference(start).inMinutes) return null;

  DateTime roundUp(DateTime time) {
    final minute = DateTime(
      time.year,
      time.month,
      time.day,
      time.hour,
      time.minute,
    );
    final remainder = time.minute % 5;
    if (remainder == 0 && time == minute) return minute;
    return minute.add(Duration(minutes: 5 - remainder));
  }

  var candidate = roundUp(start);
  final length = Duration(minutes: task.estimatedMinutes);
  final busy =
      schedule.items.where((item) => !schedule.isCompletedTask(item)).toList()
        ..sort((a, b) => a.range.start.compareTo(b.range.start));
  for (final item in busy) {
    final range = item.range;
    if (!range.end.isAfter(candidate)) continue;
    if (!candidate.add(length).isAfter(range.start)) break;
    candidate = roundUp(range.end);
    if (!candidate.isBefore(limit)) return null;
  }
  final end = candidate.add(length);
  return end.isAfter(limit) ? null : TimeRange(start: candidate, end: end);
}

Future<bool> applyTaskSuggestion({
  required DayScheduleLoader loader,
  required TaskRepository tasks,
  required String taskId,
  required TimeRange proposed,
  required DateTime now,
}) async {
  final current = await tasks.getById(taskId);
  if (current == null) return false;
  final day = await loader.loadDay(proposed.start);
  final latest = suggestTaskTime(day, current, now);
  if (latest == null ||
      latest.start != proposed.start ||
      latest.end != proposed.end) {
    return false;
  }
  await tasks.update(current.copyWith(scheduledRange: proposed));
  return true;
}

int comparePlanningTasks(Task a, Task b) {
  final aDue = a.dueAt;
  final bDue = b.dueAt;
  if (aDue != null && bDue != null) {
    final byDate = aDue.compareTo(bDue);
    if (byDate != 0) return byDate;
  } else if (aDue != null || bDue != null) {
    return aDue == null ? 1 : -1;
  }
  final byPriority = b.priority.index.compareTo(a.priority.index);
  return byPriority == 0 ? a.id.compareTo(b.id) : byPriority;
}
