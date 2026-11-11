import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/gpa/services/gpa_calculator.dart';
import 'package:student_life_rpg/features/gpa/services/timetable_weeks.dart';

void main() {
  test('Issue34 exact weighted GPA acceptance and unchanged input', () {
    Course course(String id, double credits, double? point) => Course(
      id: id,
      semesterId: 's',
      name: id,
      credits: credits,
      gradePoint: point,
      slots: [],
      scoreScaleMax: 4,
    );
    final list = [course('a', 2, 3), course('b', 4, 4)];
    final calculator = GpaCalculator();
    expect(
      calculator.calculate(list, scoreScaleMax: 4).value,
      closeTo(22 / 6, 1e-9),
    );
    expect(
      calculator.calculate(list, scoreScaleMax: 4).value!.toStringAsFixed(2),
      '3.67',
    );
    list.add(course('zero', 2, 0));
    list.add(course('missing', 5, null));
    final before = list.map((c) => c.toJson()).toList();
    final result = calculator.calculate(
      List.unmodifiable(list),
      scoreScaleMax: 4,
    );
    expect(result.value, closeTo(2.75, 1e-9));
    expect(result.missingCount, 1);
    expect(result.gradedCredits, 8);
    expect(list.map((c) => c.toJson()).toList(), before);
  });
  test('source discontinuous weeks and odd/even normalization', () {
    expect(parseTimetableWeeks('1-4周,6-12周', maxWeek: 17), [
      1,
      2,
      3,
      4,
      6,
      7,
      8,
      9,
      10,
      11,
      12,
    ]);
    expect(parseTimetableWeeks('1-6周(单)', maxWeek: 6), [1, 3, 5]);
    expect(parseTimetableWeeks('1-6周（双）', maxWeek: 6), [2, 4, 6]);
    expect(parseTimetableWeeks('8-8周', maxWeek: 8), [8]);
    expect(
      () => parseTimetableWeeks('1周', maxWeek: 1).clear(),
      throwsUnsupportedError,
    );
  });
  test(
    'invalid, duplicate, reversed and out-of-semester weeks fail visibly',
    () {
      for (final text in [
        '0周',
        '1-999',
        '3-1周',
        '1,1周',
        '1-3,3-4周',
        '',
        '单周',
        '登录',
        '1-3周(单双)',
      ]) {
        expect(
          () => parseTimetableWeeks(text, maxWeek: 5),
          throwsFormatException,
          reason: text,
        );
      }
      expect(() => parseTimetableWeeks('1', maxWeek: 0), throwsArgumentError);
    },
  );
}
