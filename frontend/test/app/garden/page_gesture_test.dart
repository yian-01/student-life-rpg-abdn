import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/garden/page_gesture.dart';

void main() {
  test('one swipe consumes all inertial peaks and direction rebounds', () {
    final gesture = PageGesture();
    final directions = <int>[];
    var clock = Duration.zero;
    for (final delta in [35.0, 35.0, 35.0, 3.0, 1.0, 100.0, -110.0, 100.0]) {
      clock += const Duration(milliseconds: 70);
      final direction = gesture.add(x: delta, y: 0, time: clock);
      if (direction != null) directions.add(direction);
    }
    expect(directions, [1]);
  });
  test('sparse momentum remains locked, a separate swipe re-arms', () {
    final gesture = PageGesture();
    expect(gesture.add(x: 110, y: 0, time: Duration.zero), 1);
    for (var i = 1; i <= 4; i++) {
      expect(
        gesture.add(x: 110, y: 0, time: Duration(milliseconds: i * 280)),
        isNull,
      );
    }
    expect(
      gesture.add(x: -110, y: 0, time: const Duration(milliseconds: 1500)),
      -1,
    );
  });
  test('small movement, diagonal motion and signed jitter are rejected', () {
    final gesture = PageGesture();
    expect(gesture.add(x: 20, y: 0, time: Duration.zero), isNull);
    expect(
      gesture.add(x: -25, y: 0, time: const Duration(milliseconds: 10)),
      isNull,
    );
    expect(
      gesture.add(x: 110, y: 100, time: const Duration(milliseconds: 20)),
      isNull,
    );
  });
  test('controls consume the stream even when the pointer leaves them', () {
    final gesture = PageGesture();
    expect(
      gesture.add(x: 110, y: 0, time: Duration.zero, blocked: true),
      isNull,
    );
    expect(
      gesture.add(x: 110, y: 0, time: const Duration(milliseconds: 16)),
      isNull,
    );
    expect(
      gesture.add(x: 110, y: 0, time: const Duration(milliseconds: 400)),
      1,
    );
  });
}
