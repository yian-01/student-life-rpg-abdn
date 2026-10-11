import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/interaction/models/interaction_target.dart';

InteractionTarget target({
  String id = 'menu',
  String label = 'Menu',
  String route = '/menu',
  Offset point = Offset.zero,
  double radius = 70,
}) => InteractionTarget(
  id: id,
  label: label,
  routeName: route,
  worldPoint: point,
  radius: radius,
);

void main() {
  test(
    'blank identity, label and route are rejected; valid text is preserved',
    () {
      expect(() => target(id: ' '), throwsArgumentError);
      expect(() => target(label: ''), throwsArgumentError);
      expect(() => target(route: '\n'), throwsArgumentError);
      expect(target(id: ' menu ').id, ' menu ');
    },
  );
  test(
    'non-finite coordinates and non-positive/non-finite radius are rejected',
    () {
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(() => target(point: Offset(value, 0)), throwsArgumentError);
        expect(() => target(point: Offset(0, value)), throwsArgumentError);
        expect(() => target(radius: value), throwsArgumentError);
      }
      for (final value in [0.0, -1.0]) {
        expect(() => target(radius: value), throwsArgumentError);
      }
    },
  );
  test(
    'distance is Euclidean and finite large radii avoid squared overflow',
    () {
      expect(target(radius: 5).containsWorldPoint(const Offset(3, 4)), isTrue);
      expect(target(radius: 5).containsWorldPoint(const Offset(4, 4)), isFalse);
      expect(
        target(radius: 1e300).containsWorldPoint(const Offset(8e299, 8e299)),
        isFalse,
      );
      expect(
        target(radius: 1e300).containsWorldPoint(const Offset(6e299, 8e299)),
        isTrue,
      );
      expect(
        target().containsWorldPoint(const Offset(double.infinity, 0)),
        isFalse,
      );
    },
  );
}
