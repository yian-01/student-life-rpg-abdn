import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/app_data.dart';
import 'package:student_life_rpg/app/platform_home_page.dart';
import 'package:student_life_rpg/app/platform_profile_page.dart';
import 'package:student_life_rpg/app/student_life_app.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_task_repository.dart';
import '../support/campus_fixture.dart';

void main() {
  setUpAll(() async {
    final font = File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc');
    if (!await font.exists()) return;
    final bytes = ByteData.sublistView(await font.readAsBytes());
    final icons = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons))).load();
    for (final name in ['Roboto', 'Arial', 'Ahem']) {
      await (FontLoader(name)..addFont(Future.value(bytes))).load();
    }
  });

  for (final width in [320.0, 390.0, 1200.0]) {
    testWidgets('real home, navigation and empty data at width $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final campus = emptyCampusData();
      addTearDown(campus.dispose);
      AppData.useCampusData(campus);
      AppData.useTaskRepository(InMemoryTaskRepository());
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: boundary, child: const StudentLifeApp()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlatformHomePage), findsOneWidget);
      expect(find.text('课屿'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('build/interface-review');
        await dir.create(recursive: true);
        await File(
          '${dir.path}/home-${width.toInt()}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.scrollUntilVisible(
        find.text('今天没有课程安排'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('今天没有课程安排'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('暂时没有未完成事项'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('暂时没有未完成事项'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();
      expect(find.byType(PlatformProfilePage), findsOneWidget);
      await tester.tap(find.text('首页').last);
      await tester.pumpAndSettle();
      expect(find.byType(PlatformHomePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reduced motion and enlarged text keep home usable', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final campus = emptyCampusData();
    addTearDown(campus.dispose);
    AppData.useCampusData(campus);
    AppData.useTaskRepository(InMemoryTaskRepository());
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(390, 844),
        disableAnimations: true, textScaler: TextScaler.linear(1.4)),
      child: const StudentLifeApp(),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.scrollUntilVisible(find.text('今天没有课程安排'), 200,
      scrollable: find.byType(Scrollable).first);
    expect(find.text('今天没有课程安排'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home reads tasks and refreshes after returning from task list', (
    tester,
  ) async {
    final campus = emptyCampusData();
    addTearDown(campus.dispose);
    final tasks = InMemoryTaskRepository();
    await tasks.insert(Task(id: 'task', title: '完成项目设计', estimatedMinutes: 25));
    AppData.useCampusData(campus);
    AppData.useTaskRepository(tasks);
    await tester.pumpWidget(const StudentLifeApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('完成项目设计'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('完成项目设计'));
    await tester.pumpAndSettle();
    await tasks.setCompleted('task', true);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('暂时没有未完成事项'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('完成项目设计'), findsNothing);
    expect(find.text('暂时没有未完成事项'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
