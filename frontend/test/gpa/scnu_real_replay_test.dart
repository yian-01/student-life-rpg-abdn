import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/gpa/services/scnu_timetable_reader.dart';

void main() {
  test(
    'deidentified real SCNU HTML replays grid once with explicit other-course boundary',
    () {
      final html = File(
        'test/fixtures/issue34/scnu_deidentified.html',
      ).readAsStringSync();
      final periods = <int, ({int start, int end})>{
        1: (start: 510, end: 550),
        2: (start: 560, end: 600),
        3: (start: 620, end: 660),
        4: (start: 670, end: 710),
        5: (start: 840, end: 880),
        6: (start: 890, end: 930),
        7: (start: 940, end: 980),
        8: (start: 990, end: 1030),
        9: (start: 1140, end: 1180),
        10: (start: 1190, end: 1230),
        11: (start: 1240, end: 1280),
      };
      expect(
        () => ScnuTimetableReader().read(html, periods: periods, maxWeek: 17),
        throwsFormatException,
      );
      final rows = ScnuTimetableReader().read(
        html,
        periods: periods,
        maxWeek: 17,
        allowOtherCoursesForPreview: true,
      );
      expect(rows.length, 22);
      expect(rows.every((r) => r.credits != null), isTrue);
      final java = rows
          .where((r) => r.name == 'JAVA语言程序设计*' && r.weekday == 2)
          .single;
      expect(java.weeks, [1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12]);
      expect(java.startMinute, 510);
      expect(java.endMinute, 600);
      expect(java.location, contains('教A409'));
      expect(java.teacher, '合成教师');
    },
  );
}
