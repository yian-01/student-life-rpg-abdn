import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/schedule/presentation/conflict_details.dart';
import 'package:student_life_rpg/shared/models/schedule_item.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';

void main() {
  testWidgets(
    'same-name three-way overlap counts pairs with explicit exam label',
    (tester) async {
      final items = [
        for (final type in [
          ScheduleSourceType.course,
          ScheduleSourceType.task,
          ScheduleSourceType.event,
        ])
          ScheduleItem(
            id: type.name,
            sourceId: type.name,
            sourceType: type,
            title: '同名',
            range: TimeRange(
              start: DateTime(2026, 11, 6, 9),
              end: DateTime(2026, 11, 6, 10),
            ),
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConflictDetails(
                items: items,
                typeLabels: const {'event': '考试'},
              ),
            ),
          ),
        ),
      );
      expect(find.text('3对冲突'), findsOneWidget);
      expect(find.text('考试 · 同名（event）'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}
