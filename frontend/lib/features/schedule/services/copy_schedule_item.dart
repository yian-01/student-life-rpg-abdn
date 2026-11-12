import 'package:flutter/material.dart';

import '../../../shared/models/time_range.dart';
import '../models/task.dart';

Future<DateTime?> chooseCopyDate(BuildContext context, DateTime initial) =>
    showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
      helpText: '选择副本目标日期',
    );

TimeRange copyRangeToDate(TimeRange range, DateTime date) {
  final source = range.start;
  final start = DateTime(
    date.year,
    date.month,
    date.day,
    source.hour,
    source.minute,
    source.second,
    source.millisecond,
    source.microsecond,
  );
  return TimeRange(start: start, end: start.add(range.end.difference(source)));
}

Task taskCopyDraft(Task task, DateTime date) {
  final range = task.scheduledRange;
  return task.copyWith(
    isCompleted: false,
    scheduledRange: range == null ? null : copyRangeToDate(range, date),
    steps: [
      for (final step in task.steps) TaskStep(id: step.id, title: step.title),
    ],
  );
}
