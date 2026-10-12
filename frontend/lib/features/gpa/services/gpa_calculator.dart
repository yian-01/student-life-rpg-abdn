import '../../academic/models/course.dart';
import '../models/gpa_result.dart';

/// Pure, unrounded weighted GPA calculation; callers select the semester.
class GpaCalculator {
  GpaResult calculate(List<Course> courses, {required double scoreScaleMax}) {
    if (!scoreScaleMax.isFinite || scoreScaleMax <= 0) {
      throw ArgumentError.value(scoreScaleMax, 'scoreScaleMax');
    }
    final ids = <String>{};
    var credits = 0.0;
    var weighted = 0.0;
    var count = 0;
    var missing = 0;
    for (final course in courses) {
      if (!ids.add(course.id)) {
        throw ArgumentError.value(course.id, 'courses', 'Duplicate course ID.');
      }
      if (!course.credits.isFinite || course.credits <= 0) {
        throw ArgumentError.value(course.credits, 'credits');
      }
      final point = course.gradePoint;
      if (point == null) {
        missing++;
        continue;
      }
      if (!point.isFinite || point < 0 || point > scoreScaleMax) {
        throw ArgumentError.value(point, 'gradePoint');
      }
      final product = course.credits * point;
      credits += course.credits;
      weighted += product;
      if (!product.isFinite || !credits.isFinite || !weighted.isFinite) {
        throw ArgumentError('GPA multiplication or sum is not finite.');
      }
      count++;
    }
    return GpaResult(
      value: count == 0 ? null : weighted / credits,
      gradedCredits: credits,
      gradedCourseCount: count,
      missingCount: missing,
    );
  }
}
