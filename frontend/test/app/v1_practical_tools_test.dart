import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/finance/models/finance_record.dart';
import 'package:student_life_rpg/features/finance/models/finance_type.dart';
import 'package:student_life_rpg/features/finance/services/finance_csv_export.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/presentation/focus_timer_page.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_task_repository.dart';
import 'package:student_life_rpg/features/schedule/services/calendar_export.dart';
import 'package:student_life_rpg/features/schedule/services/day_schedule_service.dart';
import 'package:student_life_rpg/features/schedule/services/focus_timer.dart';
import 'package:student_life_rpg/features/schedule/services/today_planner.dart';
import 'package:student_life_rpg/shared/models/schedule_item.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';

class _DayLoader implements DayScheduleLoader {
  _DayLoader(this.day);
  DaySchedule day;

  @override
  Future<DaySchedule> loadDay(DateTime date) async => day;
}

class _Clockwork implements Stopwatch {
  @override
  Duration elapsed = Duration.zero;
  @override
  bool isRunning = false;
  @override
  int get elapsedMicroseconds => elapsed.inMicroseconds;
  @override
  int get elapsedMilliseconds => elapsed.inMilliseconds;
  @override
  int get elapsedTicks => elapsed.inMicroseconds;
  @override
  int get frequency => 1000000;
  @override
  void reset() => elapsed = Duration.zero;
  @override
  void start() => isRunning = true;
  @override
  void stop() => isRunning = false;
}

ScheduleItem event(
  String id,
  DateTime start,
  DateTime end, {
  String? title,
  String? location,
}) => ScheduleItem(
  id: id,
  sourceId: id,
  title: title ?? id,
  location: location,
  sourceType: ScheduleSourceType.event,
  range: TimeRange(start: start, end: end),
);

void main() {
  final date = DateTime(2026, 11, 12);
  DateTime time(int hour, [int minute = 0]) =>
      DateTime(2026, 11, 12, hour, minute);
  DaySchedule day(
    List<ScheduleItem> items, {
    Map<ScheduleDataSource, Object> errors = const {},
  }) => DaySchedule(
    date: date,
    items: items,
    unscheduledTasks: const [],
    completedTaskIds: const {},
    errors: errors,
  );

  test(
    'planner skips overlapping blocks and respects today and upcoming due times',
    () {
      final task = Task(
        id: 'study',
        title: '复习',
        estimatedMinutes: 30,
        dueAt: time(11, 5),
      );
      final busy = [
        event('lecture', time(9), time(10)),
        event('exam', time(9, 30), time(10, 23)),
        event('lab', time(11), time(12)),
      ];
      final proposed = suggestTaskTime(day(busy), task, time(9, 15));
      expect(proposed!.start, time(10, 25));
      expect(proposed.end, time(10, 55));
      expect(suggestTaskTime(day(busy), task, time(10, 40)), isNull);
      expect(
        suggestTaskTime(
          day(
            [],
            errors: {ScheduleDataSource.exams: StateError('read failed')},
          ),
          task,
          time(8),
        ),
        isNull,
      );
    },
  );

  test(
    'planner revalidates a confirmed slot before writing to the task repository',
    () async {
      final tasks = InMemoryTaskRepository();
      final task = Task(id: 'reading', title: '阅读', estimatedMinutes: 30);
      await tasks.insert(task);
      final loader = _DayLoader(day([]));
      final proposal = suggestTaskTime(loader.day, task, time(9))!;
      Future<bool> confirm() => applyTaskSuggestion(
        loader: loader,
        tasks: tasks,
        taskId: task.id,
        proposed: proposal,
        now: time(9),
      );
      loader.day = day([event('new class', time(9, 10), time(10))]);
      expect(await confirm(), isFalse);
      expect((await tasks.getById(task.id))!.scheduledRange, isNull);
      loader.day = day([]);
      expect(await confirm(), isTrue);
      expect((await tasks.getById(task.id))!.scheduledRange!.start, time(9));
      expect(await confirm(), isFalse);
    },
  );

  test(
    'calendar export folds UTF-8, escapes text and exports a spanning event once',
    () {
      final item = event(
        'exam:42',
        time(23),
        DateTime(2026, 11, 13, 1),
        title: '${List.filled(32, '课程').join()}\n复习,测验;练习',
        location: '一号楼,101',
      );
      final file = utf8.decode(
        exportCalendar([item, item], DateTime.utc(2026, 11, 12)),
      );
      final physical = file.split('\r\n');
      expect(physical.every((line) => utf8.encode(line).length <= 75), isTrue);
      final unfolded = file.replaceAll('\r\n ', '');
      expect(RegExp('BEGIN:VEVENT').allMatches(unfolded), hasLength(1));
      expect(unfolded, contains(r'\n复习\,测验\;练习'));
      expect(unfolded, contains(r'LOCATION:一号楼\,101'));
      expect(
        unfolded,
        contains(RegExp(r'DTSTART:\d{8}T\d{6}Z\r\nDTEND:\d{8}T\d{6}Z')),
      );
      expect(unfolded, contains('DTSTAMP:20261112T000000Z'));
    },
  );

  test('ledger CSV keeps cents and quotes multiline and formula-like text', () {
    final bytes = exportFinanceCsv(
      [
        FinanceRecord(
          id: 'record',
          categoryId: 'cat',
          type: FinanceType.expense,
          amountMinor: 1234,
          occurredAt: time(10),
          note: '  =1+1\n"交通"',
          reimbursement: ReimbursementStatus.pending,
        ),
      ],
      {'cat': '@公交,地铁'},
    );
    expect(bytes.take(3), [0xef, 0xbb, 0xbf]);
    final csv = utf8.decode(bytes);
    expect(csv, contains('"\'@公交,地铁","12.34"'));
    expect(csv, contains('"\'  =1+1\n""交通""","待报销","否"\r\n'));
  });

  testWidgets('focus countdown keeps elapsed time across screens and pauses', (
    tester,
  ) async {
    final clock = _Clockwork();
    final timer = FocusTimer(stopwatch: clock);
    Future<void> open() =>
        tester.pumpWidget(MaterialApp(home: FocusTimerPage(timer: timer)));
    await open();
    await tester.tap(find.text('开始'));
    await tester.pump();
    clock.elapsed = const Duration(minutes: 4);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('21:00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(timer.running, isTrue);
    clock.elapsed = const Duration(minutes: 5);
    await open();
    expect(find.text('20:00'), findsOneWidget);
    await tester.tap(find.text('暂停'));
    await tester.pump();
    expect(timer.running, isFalse);
    expect(find.text('已暂停'), findsOneWidget);
  });
}
