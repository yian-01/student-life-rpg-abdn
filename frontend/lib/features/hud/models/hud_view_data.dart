/// Immutable presentation data supplied by the caller. No reward side effects.
class HudViewData {
  HudViewData({
    required this.displayName,
    required this.level,
    required this.exp,
    required this.expToNextLevel,
  }) {
    if (displayName.trim().isEmpty) {
      throw ArgumentError.value(
        displayName,
        'displayName',
        'Must not be blank.',
      );
    }
    if (level < 1) {
      throw ArgumentError.value(level, 'level', 'Must be at least one.');
    }
    if (exp < 0) {
      throw ArgumentError.value(exp, 'exp', 'Must not be negative.');
    }
    if (expToNextLevel <= 0) {
      throw ArgumentError.value(
        expToNextLevel,
        'expToNextLevel',
        'Must be positive.',
      );
    }
  }

  final String displayName;
  final int level;
  final int exp;
  final int expToNextLevel;

  double get ratio => (exp / expToNextLevel).clamp(0.0, 1.0);
}
