import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/hud/models/hud_view_data.dart';

HudViewData data({
  String name = 'Demo Player',
  int level = 1,
  int exp = 0,
  int threshold = 100,
}) => HudViewData(
  displayName: name,
  level: level,
  exp: exp,
  expToNextLevel: threshold,
);

void main() {
  for (final sample in [(0, 0.0), (25, 0.25), (100, 1.0), (150, 1.0)]) {
    test(
      'ratio for ${sample.$1}/100 does not change raw experience or level',
      () {
        final model = data(exp: sample.$1);
        expect(model.ratio, sample.$2);
        expect(model.exp, sample.$1);
        expect(model.level, 1);
      },
    );
  }
  test(
    'blank names, invalid level, negative exp and zero/negative threshold rejected',
    () {
      expect(() => data(name: ' \n'), throwsArgumentError);
      expect(() => data(level: 0), throwsArgumentError);
      expect(() => data(level: -1), throwsArgumentError);
      expect(() => data(exp: -1), throwsArgumentError);
      expect(() => data(threshold: 0), throwsArgumentError);
      expect(() => data(threshold: -1), throwsArgumentError);
    },
  );
}
