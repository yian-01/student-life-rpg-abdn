// Isolated UI adapters, not the production BedroomPage or native input evidence.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/app_routes.dart';
import 'package:student_life_rpg/features/bedroom/controllers/player_movement_controller.dart';
import 'package:student_life_rpg/features/bedroom/models/scene_geometry.dart';
import 'package:student_life_rpg/features/interaction/controllers/interaction_controller.dart';
import 'package:student_life_rpg/features/interaction/models/interaction_target.dart';

class TestScene extends StatefulWidget {
  const TestScene({
    super.key,
    required this.movement,
    required this.onController,
    this.navigate,
  });
  final PlayerMovementController movement;
  final ValueChanged<InteractionController> onController;
  final NavigateToRoute? navigate;
  @override
  State<TestScene> createState() => _TestSceneState();
}

class _TestSceneState extends State<TestScene> {
  late final InteractionController controller;
  @override
  void initState() {
    super.initState();
    controller = InteractionController(
      movement: widget.movement,
      target: InteractionTarget(
        id: 'menu',
        label: '进入菜单',
        routeName: AppRoutes.menu,
        worldPoint: SceneGeometry.menuInteractionPoint,
        radius: SceneGeometry.menuInteractionRadius,
      ),
      navigate:
          widget.navigate ??
          (route) async {
            await Navigator.of(context).pushNamed<void>(route);
          },
    );
    widget.onController(controller);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyE) {
          unawaited(controller.triggerInteraction());
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          children: [
            const Text('测试位置，未联调'),
            if (controller.error != null) const Text('导航失败，请重试'),
            if (controller.canInteract)
              TextButton(
                onPressed: controller.triggerInteraction,
                child: const Text('进入菜单'),
              ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'navigation failure is rendered and button retries successfully',
    (tester) async {
      final movement = PlayerMovementController(
        start: SceneGeometry.menuInteractionPoint,
      );
      late InteractionController controller;
      var attempts = 0;
      final pop = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: TestScene(
            movement: movement,
            onController: (value) => controller = value,
            navigate: (_) {
              attempts++;
              if (attempts == 1) {
                return Future<void>.error(StateError('Unavailable'));
              }
              return pop.future;
            },
          ),
        ),
      );
      await tester.tap(find.text('进入菜单'));
      await tester.pumpAndSettle();
      expect(find.text('导航失败，请重试'), findsOneWidget);
      expect(movement.isPaused, isFalse);
      await tester.tap(find.text('进入菜单'));
      await tester.pump();
      expect(attempts, 2);
      expect(find.text('导航失败，请重试'), findsNothing);
      expect(controller.isNavigating, isTrue);
      pop.complete();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      movement.dispose();
    },
  );

  for (final keyboard in [true, false]) {
    testWidgets(
      '${keyboard ? 'E key' : 'touch/button'} waits for actual Navigator pop and preserves movement',
      (tester) async {
        final movement = PlayerMovementController(
          start: SceneGeometry.menuInteractionPoint,
        );
        late InteractionController controller;
        await tester.pumpWidget(
          MaterialApp(
            onGenerateRoute: AppRoutes.generateRoute,
            home: TestScene(
              movement: movement,
              onController: (value) {
                controller = value;
              },
            ),
          ),
        );
        await tester.pump();
        if (keyboard) {
          await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
        } else {
          await tester.tap(find.text('进入菜单'));
        }
        await tester.pumpAndSettle();
        expect(find.text('Menu'), findsOneWidget);
        expect(controller.isNavigating, isTrue);
        expect(movement.isPaused, isTrue);
        for (var i = 0; i < 9; i++) {
          await controller.triggerInteraction();
        }
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        navigator.pop();
        await tester.pumpAndSettle();
        expect(find.text('测试位置，未联调'), findsOneWidget);
        expect(controller.isNavigating, isFalse);
        expect(movement.footPosition, SceneGeometry.menuInteractionPoint);
        expect(movement.isMoving, isFalse);
        await tester.tap(find.text('进入菜单'));
        await tester.pumpAndSettle();
        expect(find.text('Menu'), findsOneWidget);
        navigator.pop();
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        movement.dispose();
      },
    );
  }
  testWidgets('outside range hides button and keyboard cannot bypass guard', (
    tester,
  ) async {
    final movement = PlayerMovementController();
    late InteractionController controller;
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: AppRoutes.generateRoute,
        home: TestScene(
          movement: movement,
          onController: (value) {
            controller = value;
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text('进入菜单'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pumpAndSettle();
    expect(controller.isNavigating, isFalse);
    expect(find.text('Menu'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    movement.dispose();
  });
}
