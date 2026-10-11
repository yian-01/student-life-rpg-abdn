import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/gpa/models/gpa_result.dart';

void main() {
  test('GpaResult preserves frozen fields, null and valid zero separately', () {
    const missing = GpaResult(
      value: null,
      gradedCredits: 0,
      gradedCourseCount: 0,
      missingCount: 2,
    );
    const zero = GpaResult(
      value: 0,
      gradedCredits: 3,
      gradedCourseCount: 1,
      missingCount: 1,
    );
    expect(missing.value, isNull);
    expect(missing.gradedCredits, 0);
    expect(missing.gradedCourseCount, 0);
    expect(missing.missingCount, 2);
    expect(zero.value, 0);
    expect(zero.gradedCredits, 3);
    expect(zero.gradedCourseCount, 1);
    expect(zero.missingCount, 1);
  });
}
