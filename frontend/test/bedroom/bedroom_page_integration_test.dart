import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/app_routes.dart';
import 'package:student_life_rpg/features/bedroom/controllers/player_movement_controller.dart';
import 'package:student_life_rpg/features/bedroom/models/scene_geometry.dart';
import 'package:student_life_rpg/features/bedroom/presentation/bedroom_page.dart';
import 'package:student_life_rpg/features/bedroom/presentation/scene_viewport.dart';
import 'package:student_life_rpg/features/hud/models/hud_view_data.dart';

Future<void> mount(
  WidgetTester tester,
  PlayerMovementController movement,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BedroomPage(movement: movement),
      onGenerateRoute: AppRoutes.generateRoute,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> holdLeft(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [
    const Size(320, 640),
    const Size(800, 600),
    const Size(1280, 800),
  ]) {
    testWidgets('assets and shared foot anchor fit viewport $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final movement = PlayerMovementController();
      await mount(tester, movement);
      final viewport = tester.getRect(find.byKey(const Key('scene-viewport')));
      final transform = SceneTransform.fit(viewport.width, viewport.height);
      final background = tester.getRect(
        find.byKey(const Key('bedroom-background')),
      );
      final player = tester.getRect(find.byKey(const Key('bedroom-player')));
      expect(background.width, closeTo(transform.sceneRect.width, 1e-6));
      expect(background.height, closeTo(transform.sceneRect.height, 1e-6));
      expect(
        background.left - viewport.left,
        closeTo(transform.offset.dx, 1e-6),
      );
      final footLocal =
          player.topLeft -
          viewport.topLeft +
          SceneGeometry.playerFootAnchor * transform.scale;
      expect(
        (footLocal - transform.worldToLocal(movement.footPosition)).distance,
        lessThan(1e-6),
      );
      expect(find.textContaining('加载失败'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      movement.dispose();
    });
  }

  testWidgets(
    'real keyboard moves, resize preserves world position and anchor',
    (tester) async {
      final movement = PlayerMovementController();
      await mount(tester, movement);
      await holdLeft(tester);
      final foot = movement.footPosition;
      expect(foot.dx, lessThan(SceneGeometry.playerStart.dx));
      expect(movement.moveDirection, Offset.zero);
      expect(find.text('进入菜单'), findsOneWidget);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpAndSettle();
      expect(movement.footPosition, foot);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      movement.dispose();
    },
  );

  testWidgets('E cannot bypass distance; button waits for Menu pop', (
    tester,
  ) async {
    final movement = PlayerMovementController();
    await mount(tester, movement);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pumpAndSettle();
    expect(find.text('Menu'), findsNothing);
    await holdLeft(tester);
    final foot = movement.footPosition;
    await tester.tap(find.text('进入菜单'));
    await tester.pumpAndSettle();
    expect(find.text('Menu'), findsOneWidget);
    expect(movement.isPaused, isTrue);
    expect(movement.moveDirection, Offset.zero);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(movement.isPaused, isFalse);
    expect(movement.footPosition, foot);
    await tester.pump(const Duration(seconds: 1));
    expect(movement.footPosition, foot);
    await tester.pumpWidget(const SizedBox());
    movement.dispose();
  });

  testWidgets('letterbox tap is ignored; nearby scene target opens Menu', (
    tester,
  ) async {
    final movement = PlayerMovementController(start: const Offset(230, 1170));
    await mount(tester, movement);
    final viewport = tester.getRect(find.byKey(const Key('scene-viewport')));
    final transform = SceneTransform.fit(viewport.width, viewport.height);
    expect(transform.sceneRect.left, greaterThan(0));
    await tester.tapAt(Offset(viewport.left + 1, viewport.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('Menu'), findsNothing);
    await tester.tapAt(
      viewport.topLeft +
          transform.worldToLocal(SceneGeometry.menuInteractionPoint),
    );
    await tester.pumpAndSettle();
    expect(find.text('Menu'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    movement.dispose();
  });

  testWidgets('joystick drives same movement and release stops', (
    tester,
  ) async {
    final movement = PlayerMovementController();
    await mount(tester, movement);
    final center = tester.getCenter(find.byKey(const Key('movement-joystick')));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(-28, 0));
    expect(movement.moveDirection.dx, lessThan(0));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(movement.footPosition.dx, lessThan(SceneGeometry.playerStart.dx));
    expect(movement.moveDirection, Offset.zero);
    final foot = movement.footPosition;
    await tester.pump(const Duration(seconds: 1));
    expect(movement.footPosition, foot);
    await tester.pumpWidget(const SizedBox());
    movement.dispose();
  });

  testWidgets('focus loss clears held keyboard input', (tester) async {
    final movement = PlayerMovementController();
    await mount(tester, movement);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    await tester.pump(const Duration(milliseconds: 50));
    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pump();
    expect(movement.moveDirection, Offset.zero);
    final foot = movement.footPosition;
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    await tester.pump(const Duration(seconds: 1));
    expect(movement.footPosition, foot);
    await tester.pumpWidget(const SizedBox());
    movement.dispose();
  });

  testWidgets('inactive app stops and resume does not restore held input', (
    tester,
  ) async {
    final movement = PlayerMovementController();
    await mount(tester, movement);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    await tester.pump(const Duration(milliseconds: 50));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(movement.moveDirection, Offset.zero);
    final foot = movement.footPosition;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    await tester.pumpAndSettle();
    expect(movement.footPosition, foot);
    await tester.pumpWidget(const SizedBox());
    movement.dispose();
  });

  testWidgets('small window and enlarged text have no layout overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(240, 320);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final movement = PlayerMovementController(start: const Offset(230, 1170));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: BedroomPage(movement: movement),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    movement.dispose();
  });

  testWidgets('zero viewport does not draw or accept pointer input', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 0,
            height: 200,
            child: SceneViewport(
              footPosition: SceneGeometry.playerStart,
              hud: HudViewData(
                displayName: 'Demo',
                level: 1,
                exp: 0,
                expToNextLevel: 100,
              ),
              onSceneTap: (_, _) => taps++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bedroom-background')), findsNothing);
    expect(taps, 0);
    expect(tester.takeException(), isNull);
  });
}
