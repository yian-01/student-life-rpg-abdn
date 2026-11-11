import '../support/campus_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/app_data.dart';
import 'package:student_life_rpg/app/app_routes.dart';
import 'package:student_life_rpg/features/bedroom/controllers/player_movement_controller.dart';
import 'package:student_life_rpg/features/bedroom/models/scene_geometry.dart';
import 'package:student_life_rpg/features/menu/presentation/menu_page.dart';
import 'package:student_life_rpg/features/rooms/models/room_spec.dart';
import 'package:student_life_rpg/features/rooms/presentation/room_scene_page.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_task_repository.dart';

void main() {
  setUp(() {
    AppData.useTaskRepository(InMemoryTaskRepository());
    AppData.useCampusData(emptyCampusData());
  });

  for (final door in RoomSpec.hall.doors) {
    test('hall floor has an unobstructed path from entry to ${door.id}', () {
      final movement = PlayerMovementController(
        start: RoomSpec.hall.start,
        area: RoomSpec.hall.area,
      );
      for (
        var i = 0;
        i < 500 && (movement.footPosition - door.point).distance > 10;
        i++
      ) {
        movement.setMoveDirection(door.point - movement.footPosition);
        movement.update(.05);
        expect(RoomSpec.hall.area.canOccupy(movement.footPosition), isTrue);
      }
      expect((movement.footPosition - door.point).distance, lessThan(12));
      movement.dispose();
    });

    for (final useButton in [false, true]) {
      testWidgets(
        '${door.id} ${useButton ? 'button' : 'E'} opens its module and restores input on return',
        (tester) async {
          final movement = PlayerMovementController(
            start: door.point,
            area: RoomSpec.hall.area,
          );
          await tester.pumpWidget(
            MaterialApp(
              home: MenuPage(movement: movement),
              onGenerateRoute: AppRoutes.generateRoute,
            ),
          );
          await tester.pumpAndSettle();
          final room = tester.element(find.byType(RoomScenePage));
          if (useButton) {
            await tester.tap(find.byKey(Key('${door.id}-interaction')));
          } else {
            await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
          }
          await tester.pumpAndSettle();
          expect(movement.isPaused, isTrue);
          expect(
            ModalRoute.of(tester.element(find.byType(AppBar)))!.settings.name,
            door.route,
          );
          await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
          expect(tester.element(find.byType(RoomScenePage)), same(room));
          expect(movement.footPosition, door.point);
          expect(movement.moveDirection, Offset.zero);
          expect(movement.isPaused, isFalse);
          await tester.pump(const Duration(seconds: 1));
          expect(movement.footPosition, door.point);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
          expect(movement.footPosition.dy, greaterThan(door.point.dy));
          expect(movement.moveDirection, Offset.zero);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          movement.dispose();
        },
      );
    }
  }

  testWidgets('rapid E presses open only one route', (tester) async {
    final door = RoomSpec.hall.doors.first;
    final movement = PlayerMovementController(
      start: door.point,
      area: RoomSpec.hall.area,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MenuPage(movement: movement),
        onGenerateRoute: AppRoutes.generateRoute,
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    }
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(RoomScenePage), findsOneWidget);
    expect(movement.isPaused, isFalse);
    await tester.pumpWidget(const SizedBox());
    movement.dispose();
  });

  testWidgets('room unlocks after the returning route finishes its animation', (
    tester,
  ) async {
    final door = RoomSpec.hall.doors.first;
    final movement = PlayerMovementController(
      start: door.point,
      area: RoomSpec.hall.area,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MenuPage(movement: movement),
        onGenerateRoute: AppRoutes.generateRoute,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('${door.id}-interaction')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 50));
    expect(movement.isPaused, isTrue);
    await tester.pumpAndSettle();
    expect(movement.isPaused, isFalse);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'room-input');
    await tester.pumpWidget(const SizedBox());
    movement.dispose();
  });

  testWidgets('hall clears held input on lifecycle pause', (tester) async {
    final movement = PlayerMovementController(
      start: RoomSpec.hall.start,
      area: RoomSpec.hall.area,
    );
    await tester.pumpWidget(MaterialApp(home: MenuPage(movement: movement)));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    final stopped = movement.footPosition;
    expect(movement.moveDirection, Offset.zero);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await tester.pump(const Duration(seconds: 1));
    expect(movement.footPosition, stopped);
    await tester.pumpWidget(const SizedBox());
    movement.dispose();
  });

  testWidgets('returning while inactive restores room focus on resume', (
    tester,
  ) async {
    final door = RoomSpec.hall.doors.first;
    final movement = PlayerMovementController(
      start: door.point,
      area: RoomSpec.hall.area,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MenuPage(movement: movement),
        onGenerateRoute: AppRoutes.generateRoute,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('${door.id}-interaction')));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(movement.isPaused, isFalse);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'room-input');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
    expect(movement.footPosition.dy, greaterThan(door.point.dy));
    await tester.pumpWidget(const SizedBox());
    movement.dispose();
  });

  testWidgets('four modules survive twenty enter and return cycles', (
    tester,
  ) async {
    for (final door in RoomSpec.hall.doors) {
      final movement = PlayerMovementController(
        start: door.point,
        area: RoomSpec.hall.area,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MenuPage(movement: movement),
          onGenerateRoute: AppRoutes.generateRoute,
        ),
      );
      await tester.pumpAndSettle();
      final room = tester.element(find.byType(RoomScenePage));
      for (var cycle = 0; cycle < 5; cycle++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
        await tester.pumpAndSettle();
        expect(movement.isPaused, isTrue);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(tester.element(find.byType(RoomScenePage)), same(room));
        expect(movement.isPaused, isFalse);
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'room-input');
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      movement.dispose();
    }
  });

  testWidgets('phone door signs and action button keep a usable touch area', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final door = RoomSpec.hall.doors.first;
    final movement = PlayerMovementController(
      start: door.point,
      area: RoomSpec.hall.area,
    );
    await tester.pumpWidget(MaterialApp(home: MenuPage(movement: movement)));
    await tester.pumpAndSettle();
    for (final entry in RoomSpec.hall.doors) {
      final sign = tester.getSize(find.byKey(Key('door-${entry.id}')));
      expect(sign.width, greaterThanOrEqualTo(48));
      expect(sign.height, greaterThanOrEqualTo(48));
    }
    final action = tester.getSize(find.byKey(Key('${door.id}-interaction')));
    expect(action.width, greaterThanOrEqualTo(48));
    expect(action.height, greaterThanOrEqualTo(48));
    await tester.pumpWidget(const SizedBox());
    movement.dispose();
  });

  test('hall rug stays walkable while added furniture blocks movement', () {
    final hall = RoomSpec.hall;
    // Cross the whole rug from the entry toward the rear doors.
    final movement = PlayerMovementController(
      start: hall.start,
      area: hall.area,
    );
    movement.setMoveDirection(const Offset(0, -1));
    for (var i = 0; i < 70; i++) {
      movement.update(.05);
      expect(hall.area.canOccupy(movement.footPosition), isTrue);
    }
    expect(movement.footPosition.dy, lessThan(740));
    movement.dispose();
    for (final furniture in [
      const Offset(150, 850), // Console/left plant.
      const Offset(990, 850), // Bench/right plant.
      const Offset(570, 455), // Rear plant overlaps the open floor.
    ]) {
      expect(hall.area.contains(furniture), isTrue);
      expect(hall.area.canOccupy(furniture), isFalse);
    }
  });

  test('camera covers phone and short windows without stretching', () {
    for (final viewport in [
      const Size(240, 320),
      const Size(360, 800),
      const Size(390, 844),
      const Size(430, 932),
      const Size(800, 600),
    ]) {
      for (final room in [RoomSpec.bedroom, RoomSpec.hall]) {
        for (final focus in [room.start, ...room.doors.map((d) => d.point)]) {
          final camera = SceneTransform.cover(
            viewport.width,
            viewport.height,
            worldSize: room.size,
            focus: focus,
          );
          expect(camera.sceneRect.left, lessThanOrEqualTo(0));
          expect(camera.sceneRect.top, lessThanOrEqualTo(0));
          expect(
            camera.sceneRect.right,
            greaterThanOrEqualTo(viewport.width - 1e-8),
          );
          expect(
            camera.sceneRect.bottom,
            greaterThanOrEqualTo(viewport.height - 1e-8),
          );
          final local = camera.worldToLocal(focus);
          expect(local.dx, inInclusiveRange(0, viewport.width));
          expect(local.dy, inInclusiveRange(0, viewport.height));
          expect((camera.localToWorld(local) - focus).distance, lessThan(1e-6));
        }
      }
    }
  });

  test('hall collision prevents walking through walls and edge plants', () {
    for (final direction in [
      const Offset(0, -1),
      const Offset(1, 0),
      const Offset(-1, 0),
      const Offset(0, 1),
      const Offset(1, -1),
      const Offset(-1, -1),
    ]) {
      final movement = PlayerMovementController(
        start: RoomSpec.hall.start,
        area: RoomSpec.hall.area,
      );
      movement.setMoveDirection(direction);
      for (var i = 0; i < 700; i++) {
        movement.update(.05);
        expect(RoomSpec.hall.area.canOccupy(movement.footPosition), isTrue);
      }
      movement.dispose();
    }
  });
}
