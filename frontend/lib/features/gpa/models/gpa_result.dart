/// Unrounded weighted GPA summary shared by GPA and Dashboard consumers.
class GpaResult {
  const GpaResult({
    required this.value,
    required this.gradedCredits,
    required this.gradedCourseCount,
    required this.missingCount,
  });

  /// Null when no courses have a grade; zero is a valid GPA.
  final double? value;
  final double gradedCredits;
  final int gradedCourseCount;
  final int missingCount;
}
