import '../models/gpa_result.dart';

typedef GpaForecast = ({
  double requiredAverage,
  double maximumReachable,
  bool reachable,
});

GpaForecast forecastGpa(
  GpaResult current, {
  required double target,
  required double futureCredits,
  required double scaleMax,
}) {
  if (!futureCredits.isFinite || futureCredits <= 0) {
    throw const FormatException('计划学分必须是有限正数。');
  }
  if (!target.isFinite || target < 0 || target > scaleMax) {
    throw FormatException('目标 GPA 必须在 0 到 $scaleMax 之间。');
  }
  final currentAverage = current.value ?? 0;
  final creditFraction =
      current.gradedCredits / (current.gradedCredits + futureCredits);
  final gap = target - currentAverage;
  final needed = gap == 0
      ? target
      : target + gap * (current.gradedCredits / futureCredits);
  final best =
      currentAverage * creditFraction + scaleMax * (1 - creditFraction);
  return (
    requiredAverage: needed.clamp(0.0, double.infinity).toDouble(),
    maximumReachable: best,
    reachable: target <= best + 1e-10,
  );
}
