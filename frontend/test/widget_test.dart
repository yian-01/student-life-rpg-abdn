import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/app_routes.dart';
import 'package:student_life_rpg/features/rooms/models/room_spec.dart';
import 'package:student_life_rpg/features/rooms/presentation/room_scene_page.dart';
import 'package:student_life_rpg/app/app_data.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_task_repository.dart';
import 'package:student_life_rpg/features/dashboard/presentation/dashboard_page.dart';
import 'package:student_life_rpg/app/student_life_app.dart';
import 'package:student_life_rpg/features/bedroom/presentation/bedroom_page.dart';
import 'package:student_life_rpg/features/finance/presentation/finance_page.dart';
import 'package:student_life_rpg/features/gpa/presentation/gpa_page.dart';
import 'package:student_life_rpg/features/menu/presentation/menu_page.dart';
import 'package:student_life_rpg/features/schedule/presentation/day_schedule_page.dart';

Future<void> tapText(WidgetTester tester, String text) async {
  if (text == '进入校园大厅' && find.text(text).evaluate().isEmpty) {
    // Exercise the real bedroom input adapter, rather than bypassing the door.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
  }
  final module = {
    'Schedule': 'schedule',
    'GPA': 'gpa',
    'Finance': 'finance',
    'Dashboard': 'dashboard',
  }[text];
  if (module != null && find.byType(MenuPage).evaluate().isNotEmpty) {
    final scene = tester.state<RoomScenePageState>(find.byType(RoomScenePage));
    final door = RoomSpec.hall.doors.firstWhere((door) => door.id == module);
    for (
      var i = 0;
      i < 500 && (scene.movement.footPosition - door.point).distance > 16;
      i++
    ) {
      scene.movement.setMoveDirection(door.point - scene.movement.footPosition);
      scene.movement.update(.05);
    }
    scene.movement.clearInput();
    await tester.pump();
    expect(
      (scene.movement.footPosition - door.point).distance,
      lessThan(door.radius),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pumpAndSettle();
    return;
  }
  final target = find.text(text);
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      100,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.25);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void expectTitle(String title) {
  if (title == 'Student Life RPG' || title == 'Menu') {
    expect(find.text(title == 'Menu' ? '校园大厅' : '我的卧室'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    return;
  }
  expect(
    find.descendant(
      of: find.byType(AppBar),
      matching: find.text(
        const {
              'Schedule': '日程手账',
              'GPA': '学业档案',
              'Finance': '生活账本',
              'Dashboard': '生活总览',
            }[title] ??
            title,
      ),
    ),
    findsOneWidget,
  );
}

/// Schedule / GPA / Finance 已接入真实页面，Dashboard 暂为占位。
Finder moduleBodyFinder(String name) => switch (name) {
  'Schedule' => find.byType(DaySchedulePage),
  'GPA' => find.byType(GpaPage),
  'Finance' => find.byType(FinancePage),
  _ => find.byType(DashboardPage),
};

void main() {
  setUp(() => AppData.useTaskRepository(InMemoryTaskRepository()));
  testWidgets('Starts in bedroom and opens Menu', (tester) async {
    await tester.pumpWidget(const StudentLifeApp());
    expectTitle('Student Life RPG');
    expect(find.byKey(const Key('bedroom-background')), findsOneWidget);
    expect(find.text('进入校园大厅'), findsNothing);
    expect(find.byType(BackButton), findsNothing);

    await tapText(tester, '进入校园大厅');
    expectTitle('Menu');
    for (final door in RoomSpec.hall.doors) {
      expect(find.byKey(Key('door-${door.id}')), findsOneWidget);
    }
  });

  for (final name in ['Schedule', 'GPA', 'Finance', 'Dashboard']) {
    testWidgets('$name opens and pops through the existing Menu and bedroom', (
      tester,
    ) async {
      await tester.pumpWidget(const StudentLifeApp());
      final bedroom = tester.element(find.byType(BedroomPage));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await tapText(tester, '进入校园大厅');
      final menu = tester.element(find.byType(MenuPage));

      await tapText(tester, name);
      expectTitle(name);
      final body = moduleBodyFinder(name);
      expect(body, findsOneWidget);
      expect(ModalRoute.of(tester.element(body))?.settings.name, switch (name) {
        'Schedule' => AppRoutes.schedule,
        'GPA' => AppRoutes.gpa,
        'Finance' => AppRoutes.finance,
        _ => AppRoutes.dashboard,
      });

      await tester.pageBack();
      await tester.pumpAndSettle();
      expectTitle('Menu');
      expect(tester.element(find.byType(MenuPage)), same(menu));

      await tester.pageBack();
      await tester.pumpAndSettle();
      expectTitle('Student Life RPG');
      expect(tester.element(find.byType(BedroomPage)), same(bedroom));
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)),
        same(navigator),
      );
      expect(navigator.canPop(), isFalse);
    });
  }

  testWidgets('Unknown pushed route shows an error and recovers to bedroom', (
    tester,
  ) async {
    await tester.pumpWidget(const StudentLifeApp());
    await tapText(tester, '进入校园大厅');
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed('/missing');
    await tester.pumpAndSettle();
    expectTitle('页面不存在');
    expect(find.text('未知路由：/missing'), findsOneWidget);

    await tapText(tester, '回到卧室');
    expectTitle('Student Life RPG');
    expect(navigator.canPop(), isFalse);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)),
      same(navigator),
    );
    await tapText(tester, '进入校园大厅');
    expectTitle('Menu');
  });

  testWidgets('Unknown initial route can recover to bedroom', (tester) async {
    await tester.pumpWidget(const StudentLifeApp(initialRoute: '/missing'));
    await tester.pumpAndSettle();
    expectTitle('页面不存在');
    await tapText(tester, '回到卧室');
    expectTitle('Student Life RPG');
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
      isFalse,
    );
  });

  testWidgets('All baseline pages fit a narrow short window', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(240, 320);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const StudentLifeApp());
    expect(tester.takeException(), isNull);
    await tapText(tester, '进入校园大厅');
    expect(tester.takeException(), isNull);
    for (final name in ['Schedule', 'GPA', 'Finance', 'Dashboard']) {
      await tapText(tester, name);
      expectTitle(name);
      expect(moduleBodyFinder(name), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .pushNamed('/an-unknown-route-with-a-long-name-that-must-wrap');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tapText(tester, '回到卧室');
    expectTitle('Student Life RPG');
    expect(tester.takeException(), isNull);
  });
}
