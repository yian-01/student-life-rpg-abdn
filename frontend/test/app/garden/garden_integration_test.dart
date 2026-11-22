import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/app_data.dart';
import 'package:student_life_rpg/app/garden/garden_routes.dart';
import 'package:student_life_rpg/app/garden/garden_scene.dart';
import 'package:student_life_rpg/app/student_life_app.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_task_repository.dart';
import '../../support/campus_fixture.dart';

void main() {
  Future<void> prepare(WidgetTester tester, {String route = '/'}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final campus = emptyCampusData();
    addTearDown(campus.dispose);
    AppData.useCampusData(campus);
    AppData.useTaskRepository(InMemoryTaskRepository());
    await tester.runAsync(() => GardenArtwork.load());
    await tester.pumpWidget(StudentLifeApp(initialRoute: route));
    await tester.pumpAndSettle();
  }

  Future<void> navigate(WidgetTester tester, int section) async {
    await tester.tap(find.byKey(const Key('garden-brand')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('garden-nav-$section')));
    await tester.pumpAndSettle();
  }

  testWidgets('desktop has full-width cherry home and hidden text navigation', (
    tester,
  ) async {
    await prepare(tester);
    expect(find.text('今天，也慢慢来。'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const Key('garden-nav-1')), findsNothing);
    expect(tester.getSize(find.byType(Navigator).first).width, 1440);
    expect(find.byType(GardenScene), findsOneWidget);
    await navigate(tester, 1);
    for (final title in ['课程', 'GPA', '作业', '考试']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets('real empty business pages are reached from the new portals', (
    tester,
  ) async {
    await prepare(tester, route: GardenRoutes.study);
    await tester.tap(find.byKey(const ValueKey('garden-tool-/assignments')));
    await tester.pumpAndSettle();
    expect(find.text('先创建或导入课程，再安排作业与考试。'), findsOneWidget);
    expect(find.text('添加作业'), findsOneWidget);
    await navigate(tester, 2);
    await tester.tap(find.byKey(const ValueKey('garden-tool-/todo')));
    await tester.pumpAndSettle();
    expect(find.text('示例内容'), findsNothing);
    expect(find.byType(GardenScene), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('one wheel stream switches once and home/last boundaries stop', (
    tester,
  ) async {
    await prepare(tester);
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    for (final x in [110.0, 80.0, 20.0, 110.0, -110.0]) {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: const Offset(800, 180),
          scrollDelta: Offset(x, 0),
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('garden-tool-/academic')), findsOneWidget);
    navigator.pushReplacementNamed('/');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('今天，也慢慢来。'), findsOneWidget);
    await navigate(tester, 4);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('garden-tool-/backup')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('theme switch keeps current business route', (tester) async {
    await prepare(tester, route: GardenRoutes.study);
    await tester.tap(find.byKey(const ValueKey('garden-tool-/assignments')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('garden-brand')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('garden-theme')));
    await tester.pumpAndSettle();
    expect(find.text('添加作业'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('添加作业'))).brightness,
      Brightness.dark,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop todo entrance can create and display a real task', (
    tester,
  ) async {
    await prepare(tester, route: '/todo');
    await tester.tap(find.byTooltip('添加待办'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('add-task-title')), '桌面真实待办');
    await tester.tap(find.text('添加').last);
    await tester.pumpAndSettle();
    expect((await (await AppData.tasks()).list()).single.title, '桌面真实待办');
    await tester.pumpAndSettle();
    expect(find.text('桌面真实待办'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
