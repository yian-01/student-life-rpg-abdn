import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/finance/models/finance_record.dart';
import 'package:student_life_rpg/features/finance/models/finance_type.dart';
import 'package:student_life_rpg/features/finance/services/weekly_finance.dart';
import 'package:student_life_rpg/features/gpa/models/gpa_result.dart';
import 'package:student_life_rpg/features/gpa/services/gpa_forecast.dart';
import 'package:student_life_rpg/features/schedule/presentation/week_timetable_grid.dart';
import 'package:student_life_rpg/features/schedule/services/week_timetable_layout.dart';
import 'package:student_life_rpg/shared/models/schedule_item.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';

ScheduleItem event(String id, DateTime start, DateTime end) => ScheduleItem(
  id: id,
  sourceId: id,
  sourceType: ScheduleSourceType.event,
  title: id,
  range: TimeRange(start: start, end: end),
);

void main() {
  final monday = DateTime(2026, 11, 2);
  test('week grid clips midnight and separates overlapping entries', () {
    final rows = [
      event('overnight', DateTime(2026, 11, 1, 23), DateTime(2026, 11, 2, 1)),
      event('overlap', DateTime(2026, 11, 2, 0, 30), DateTime(2026, 11, 2, 2)),
      event('adjacent', DateTime(2026, 11, 2, 2), DateTime(2026, 11, 2, 3)),
    ];
    final placed = placeWeekDay(monday, rows);
    expect(placed.map((row) => (row.start, row.end, row.lane, row.laneCount)), [
      (0, 60, 0, 2),
      (30, 120, 1, 2),
      (120, 180, 0, 1),
    ]);
  });

  testWidgets(
    'week timetable opens cards and exposes all seven days on narrow windows',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(330, 520);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final dates = [for (var i = 0; i < 7; i++) DateTime(2026, 11, 2 + i)];
      final rows = [
        event('周一活动', DateTime(2026, 11, 2, 9), DateTime(2026, 11, 2, 10)),
      ];
      ScheduleItem? opened;
      DateTime? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WeekTimetableGrid(
              dates: dates,
              items: [rows, for (var i = 0; i < 6; i++) const <ScheduleItem>[]],
              onSelectDate: (value) => selected = value,
              onOpen: (value) => opened = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('周一活动'));
      expect(opened?.id, '周一活动');
      await tester.drag(
        find.byKey(const Key('week-grid-horizontal')),
        const Offset(-560, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('周日 · 11/8'));
      expect(selected, dates.last);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'weekly finance counts exact cents across month boundaries and compares prior week',
    () {
      FinanceRecord row(
        String id,
        DateTime date,
        int amount, {
        FinanceType type = FinanceType.expense,
      }) => FinanceRecord(
        id: id,
        categoryId: 'food',
        type: type,
        amountMinor: amount,
        occurredAt: date,
      );
      final week = weeklyFinance([
        row('previous', DateTime(2026, 10, 25, 23, 59), 90),
        row('start', DateTime(2026, 10, 26), 1250),
        row('sunday', DateTime(2026, 11, 1, 23, 59), 175),
        row('income', DateTime(2026, 11, 1), 2125, type: FinanceType.income),
        row('next', DateTime(2026, 11, 2), 999),
      ], DateTime(2026, 11, 1));
      expect(week.days.first.date, DateTime(2026, 10, 26));
      expect(week.days.last.expense, 175);
      expect(week.expense, 1425);
      expect(week.income, 2125);
      expect(week.previousExpense, 90);
      expect(week.categories.single.amount, 1425);
    },
  );

  test(
    '5.0 GPA forecast respects graded credits and shows impossible goals',
    () {
      const current = GpaResult(
        value: 3.5,
        gradedCredits: 20,
        gradedCourseCount: 5,
        missingCount: 2,
      );
      final reachable = forecastGpa(
        current,
        target: 4,
        futureCredits: 10,
        scaleMax: 5,
      );
      expect(reachable.requiredAverage, 5);
      expect(reachable.maximumReachable, closeTo(4, 1e-10));
      expect(reachable.reachable, isTrue);
      expect(
        forecastGpa(
          current,
          target: 4.5,
          futureCredits: 10,
          scaleMax: 5,
        ).reachable,
        isFalse,
      );
      expect(
        () => forecastGpa(current, target: 4, futureCredits: 0, scaleMax: 5),
        throwsFormatException,
      );
    },
  );
}
