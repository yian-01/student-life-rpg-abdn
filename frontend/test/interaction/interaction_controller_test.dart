import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/bedroom/controllers/player_movement_controller.dart';
import 'package:student_life_rpg/features/bedroom/models/scene_geometry.dart';
import 'package:student_life_rpg/features/interaction/controllers/interaction_controller.dart';
import 'package:student_life_rpg/features/interaction/models/interaction_target.dart';

InteractionTarget menuTarget() => InteractionTarget(
  id: 'menu',
  label: '进入菜单',
  routeName: '/menu',
  worldPoint: SceneGeometry.menuInteractionPoint,
  radius: SceneGeometry.menuInteractionRadius,
);

// The real dependency's input methods do not assert after disposal. This spy
// makes late access observable rather than accepting a falsely passing test.
class TrackedMovement extends PlayerMovementController {
  TrackedMovement() : super(start: const Offset(230, 1170));
  bool disposed = false;
  int lateCalls = 0;
  int resumes = 0;

  @override
  void clearInput() {
    if (disposed) {
      lateCalls++;
    }
    super.clearInput();
  }

  @override
  void resume() {
    if (disposed) {
      lateCalls++;
    }
    resumes++;
    super.resume();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  for (final sample in [(269.0, true), (270.0, true), (271.0, false)]) {
    test('world radius boundary at x=${sample.$1}', () async {
      final movement = PlayerMovementController(start: Offset(sample.$1, 1170));
      var count = 0;
      final controller = InteractionController(
        movement: movement,
        target: menuTarget(),
        navigate: (_) async {
          count++;
        },
      );
      expect(controller.canInteract, sample.$2);
      await controller.triggerInteraction();
      expect(count, sample.$2 ? 1 : 0);
      controller.dispose();
      movement.dispose();
    });
  }

  test(
    'ten triggers stay locked until pop; return keeps position and clears input',
    () async {
      final movement = PlayerMovementController(start: const Offset(230, 1170));
      final visits = <Completer<void>>[];
      final controller = InteractionController(
        movement: movement,
        target: menuTarget(),
        navigate: (route) {
          expect(route, '/menu');
          final done = Completer<void>();
          visits.add(done);
          return done.future;
        },
      );
      movement.setMoveDirection(const Offset(1, 0));
      final before = movement.footPosition;
      final pending = controller.triggerInteraction();
      for (var i = 0; i < 9; i++) {
        await controller.triggerInteraction();
      }
      expect(visits, hasLength(1));
      expect(controller.isNavigating, isTrue);
      expect(controller.canInteract, isFalse);
      expect(movement.isPaused, isTrue);
      movement.update(0.05);
      expect(movement.footPosition, before);
      // Input arriving while covered must also be neutral on return.
      movement.setMoveDirection(const Offset(1, 0));
      visits.single.complete();
      await pending;
      expect(controller.isNavigating, isFalse);
      expect(movement.isPaused, isFalse);
      expect(movement.isMoving, isFalse);
      movement.update(0.05);
      expect(movement.footPosition, before);
      final next = controller.triggerInteraction();
      expect(visits, hasLength(2));
      visits.last.complete();
      await next;
      controller.dispose();
      movement.dispose();
    },
  );

  for (final synchronous in [true, false]) {
    test(
      'navigation error ($synchronous synchronous) is visible and retryable',
      () async {
        final movement = PlayerMovementController(
          start: const Offset(230, 1170),
        );
        final failure = StateError('Navigation unavailable');
        var attempts = 0;
        final controller = InteractionController(
          movement: movement,
          target: menuTarget(),
          navigate: (_) {
            attempts++;
            if (attempts == 1) {
              if (synchronous) throw failure;
              return Future<void>.error(failure);
            }
            return Future<void>.value();
          },
        );
        var notifications = 0;
        controller.addListener(() {
          notifications++;
        });
        await controller.triggerInteraction();
        expect(controller.error, same(failure));
        expect(controller.isNavigating, isFalse);
        expect(movement.isPaused, isFalse);
        expect(controller.canInteract, isTrue);
        expect(notifications, greaterThanOrEqualTo(2));
        await controller.triggerInteraction();
        expect(controller.error, isNull);
        expect(attempts, 2);
        controller.dispose();
        movement.dispose();
      },
    );
  }

  test(
    'movement notification changes range; trigger rechecks latest position',
    () async {
      final movement = PlayerMovementController(start: const Offset(269, 1170));
      var navigations = 0;
      var notifications = 0;
      final controller = InteractionController(
        movement: movement,
        target: menuTarget(),
        navigate: (_) async {
          navigations++;
        },
      );
      controller.addListener(() {
        notifications++;
      });
      expect(controller.canInteract, isTrue);
      movement.setMoveDirection(const Offset(1, 0));
      movement.update(0.05);
      expect(controller.canInteract, isFalse);
      expect(notifications, 1);
      await controller.triggerInteraction();
      expect(navigations, 0);
      controller.dispose();
      movement.dispose();
    },
  );

  test(
    'dispose detaches listener but leaves external movement usable',
    () async {
      final movement = PlayerMovementController(start: const Offset(230, 1170));
      final controller = InteractionController(
        movement: movement,
        target: menuTarget(),
        navigate: (_) async {},
      );
      var notifications = 0;
      controller.addListener(() {
        notifications++;
      });
      controller.dispose();
      movement.setMoveDirection(const Offset(1, 0));
      movement.update(0.05);
      expect(notifications, 0);
      expect(movement.isMoving, isTrue);
      await controller.triggerInteraction();
      movement.dispose();
    },
  );

  test(
    'dispose during navigation stays paused; late Future cannot touch disposed movement',
    () async {
      final movement = TrackedMovement();
      final pop = Completer<void>();
      final controller = InteractionController(
        movement: movement,
        target: menuTarget(),
        navigate: (_) => pop.future,
      );
      final pending = controller.triggerInteraction();
      controller.dispose();
      expect(movement.isPaused, isTrue);
      expect(movement.isMoving, isFalse);
      expect(movement.resumes, 0);
      movement.dispose();
      pop.completeError(StateError('late route failure'));
      await pending;
      expect(movement.lateCalls, 0);
    },
  );

  test(
    'disposed interaction never resumes a scene still covered by Menu',
    () async {
      final movement = TrackedMovement();
      final pop = Completer<void>();
      final controller = InteractionController(
        movement: movement,
        target: menuTarget(),
        navigate: (_) => pop.future,
      );
      final before = movement.footPosition;
      final pending = controller.triggerInteraction();
      controller.dispose();
      movement.setMoveDirection(const Offset(1, 0));
      movement.update(0.05);
      expect(movement.footPosition, before);
      expect(movement.isPaused, isTrue);
      pop.complete();
      await pending;
      expect(movement.resumes, 0);
      // Reuse is an explicit decision by the owner, after the old route ends.
      movement.clearInput();
      movement.resume();
      expect(movement.isMoving, isFalse);
      movement.dispose();
    },
  );

  test(
    'local pointer ignores letterbox, non-target and right/bottom boundaries',
    () async {
      final movement = PlayerMovementController(start: const Offset(230, 1170));
      var count = 0;
      final controller = InteractionController(
        movement: movement,
        target: menuTarget(),
        navigate: (_) async {
          count++;
        },
      );
      final transform = SceneTransform.fit(800, 600);
      for (final point in [
        const Offset(100, 300),
        Offset(transform.sceneRect.right, 300),
        Offset(400, transform.sceneRect.bottom),
        transform.worldToLocal(SceneGeometry.playerStart),
        const Offset(double.nan, 0),
      ]) {
        await controller.triggerAtLocalPosition(
          localPosition: point,
          transform: transform,
        );
      }
      expect(count, 0);
      await controller.triggerAtLocalPosition(
        localPosition: transform.worldToLocal(
          SceneGeometry.menuInteractionPoint,
        ),
        transform: transform,
      );
      expect(count, 1);
      movement.reset();
      await controller.triggerAtLocalPosition(
        localPosition: transform.worldToLocal(
          SceneGeometry.menuInteractionPoint,
        ),
        transform: transform,
      );
      expect(count, 1, reason: 'Pointer cannot bypass player distance.');
      controller.dispose();
      movement.dispose();
    },
  );
}
