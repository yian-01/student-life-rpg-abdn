import 'dart:ui' show Offset;

/// A world-space target. The composition root supplies C's unique geometry
/// and A's route; this model does not create another scene configuration.
class InteractionTarget {
  InteractionTarget({
    required this.id,
    required this.label,
    required this.routeName,
    required this.worldPoint,
    required this.radius,
  }) {
    for (final entry in {
      'id': id,
      'label': label,
      'routeName': routeName,
    }.entries) {
      if (entry.value.trim().isEmpty) {
        throw ArgumentError.value(entry.value, entry.key, 'Must not be blank.');
      }
    }
    if (!worldPoint.dx.isFinite || !worldPoint.dy.isFinite) {
      throw ArgumentError.value(worldPoint, 'worldPoint', 'Must be finite.');
    }
    if (!radius.isFinite || radius <= 0) {
      throw ArgumentError.value(
        radius,
        'radius',
        'Must be positive and finite.',
      );
    }
  }

  final String id;
  final String label;
  final String routeName;
  final Offset worldPoint;
  final double radius;

  bool containsWorldPoint(Offset point) {
    if (!point.dx.isFinite || !point.dy.isFinite) return false;
    final dx = (point.dx - worldPoint.dx).abs();
    final dy = (point.dy - worldPoint.dy).abs();
    if (dx > radius || dy > radius) return false;
    // Divide before squaring so finite, large radii do not overflow.
    final x = dx / radius;
    final y = dy / radius;
    return x * x + y * y <= 1;
  }
}
