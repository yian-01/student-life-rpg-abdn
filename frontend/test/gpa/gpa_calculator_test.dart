import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/gpa/services/gpa_calculator.dart';

Course course(
  String id, {
  double credits = 3,
  double? point,
  String semester = 's',
}) => Course(
  id: id,
  semesterId: semester,
  name: id,
  credits: credits,
  gradePoint: point,
  slots: [],
  scoreScaleMax: 100,
);

// Test-only malformed values exercise J's own input validation independently of G.
class InvalidCourse extends Course {
  InvalidCourse({this.badCredits = 3, this.badPoint})
    : super(
        id: 'bad',
        semesterId: 's',
        name: 'bad',
        credits: 3,
        slots: [],
        scoreScaleMax: 4,
      );
  final double badCredits;
  final double? badPoint;
  @override
  double get credits => badCredits;
  @override
  double? get gradePoint => badPoint;
}

void main() {
  final calculator = GpaCalculator();
  test(
    'weighted GPA includes zero, excludes missing and does not round or mutate',
    () {
      final items = [
        course('a', credits: 5, point: 3.7),
        course('b', credits: 3, point: 0),
        course('c', credits: 2),
      ];
      final before = items.map((c) => c.toJson()).toList();
      final result = calculator.calculate(
        List.unmodifiable(items),
        scoreScaleMax: 4,
      );
      expect(result.value, closeTo(18.5 / 8, 1e-9));
      expect(result.gradedCredits, 8);
      expect(result.gradedCourseCount, 2);
      expect(result.missingCount, 1);
      expect(items.map((c) => c.toJson()).toList(), before);
    },
  );
  test('empty and all missing have null GPA and zero graded credits', () {
    for (final items in <List<Course>>[
      [],
      [course('a'), course('b')],
    ]) {
      final result = calculator.calculate(items, scoreScaleMax: 4);
      expect(result.value, isNull);
      expect(result.gradedCredits, 0);
      expect(result.gradedCourseCount, 0);
      expect(result.missingCount, items.length);
    }
    expect(
      calculator.calculate([course('zero', point: 0)], scoreScaleMax: 4).value,
      0,
    );
  });
  test('scale is injected and validated even for empty input', () {
    expect(
      calculator.calculate([course('a', point: 90)], scoreScaleMax: 100).value,
      90,
    );
    for (final max in [
      0.0,
      -1.0,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        () => calculator.calculate([], scoreScaleMax: max),
        throwsArgumentError,
      );
    }
    expect(
      () => calculator.calculate([course('a', point: 5)], scoreScaleMax: 4),
      throwsArgumentError,
    );
  });
  test(
    'rejects duplicate IDs including ungraded and retains original ID identity',
    () {
      expect(
        () =>
            calculator.calculate([course('a'), course('a')], scoreScaleMax: 4),
        throwsArgumentError,
      );
      expect(
        calculator.calculate([
          course('a'),
          course(' a '),
        ], scoreScaleMax: 4).missingCount,
        2,
      );
    },
  );
  test('rejects invalid credits even when grade is missing', () {
    for (final credits in [
      0.0,
      -1.0,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        () => calculator.calculate([
          InvalidCourse(badCredits: credits),
        ], scoreScaleMax: 4),
        throwsArgumentError,
      );
    }
  });
  test('rejects nonfinite, negative and out of scale grades', () {
    for (final point in [
      -1.0,
      4.01,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        () => calculator.calculate([
          InvalidCourse(badPoint: point),
        ], scoreScaleMax: 4),
        throwsArgumentError,
      );
    }
  });
  test('rejects overflow in product, weighted sum and credit sum', () {
    for (final items in [
      [course('a', credits: 1e308, point: 4)],
      [
        course('a', credits: 4e307, point: 3),
        course('b', credits: 4e307, point: 3),
      ],
      [
        course('a', credits: 1e308, point: 0),
        course('b', credits: 1e308, point: 0),
      ],
    ]) {
      expect(
        () => calculator.calculate(items, scoreScaleMax: 4),
        throwsArgumentError,
      );
    }
  });
}
