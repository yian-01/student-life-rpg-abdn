import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/app_data.dart';
import 'package:student_life_rpg/features/menu/presentation/menu_page.dart';
import 'package:student_life_rpg/app/app_routes.dart';
import 'package:student_life_rpg/app/app_viewport.dart';
import 'package:student_life_rpg/app/student_life_app.dart';
import 'package:student_life_rpg/features/finance/finance_memory_scope.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_task_repository.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';

void main() {
  setUpAll(() async {
    // Real glyphs make the CI renders useful for visual review instead of Ahem
    // rectangles. This changes only the test process, not shipped app assets.
    if (!Platform.isLinux) return;
    final font = File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc');
    if (!await font.exists()) return;
    final bytes = ByteData.sublistView(await font.readAsBytes());
    final icons = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons))).load();
    for (final family in ['Roboto', 'Arial', 'Segoe UI', 'Ahem']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
  });
  setUp(() {
    AppData.useTaskRepository(InMemoryTaskRepository());
    FinanceMemoryScope.resetShared();
  });
  tearDown(FinanceMemoryScope.resetShared);

  final cases = <(String, String, Size)>[
    ('bedroom-390', AppRoutes.bedroom, const Size(390, 844)),
    ('menu-360', AppRoutes.menu, const Size(360, 800)),
    ('menu-390', AppRoutes.menu, const Size(390, 844)),
    ('menu-430', AppRoutes.menu, const Size(430, 932)),
    ('desktop-phone-frame', AppRoutes.menu, const Size(1280, 900)),
    ('schedule', AppRoutes.schedule, const Size(390, 844)),
    ('gpa', AppRoutes.gpa, const Size(390, 844)),
    ('finance', AppRoutes.finance, const Size(390, 844)),
    ('dashboard', AppRoutes.dashboard, const Size(390, 844)),
  ];
  for (final (name, route, size) in cases) {
    testWidgets('mobile layout and rendered review: $name', (tester) async {
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = await AppData.tasks();
        final now = DateTime.now();
        await repository.insert(
          Task(id: 'review-reading', title: '阅读课程资料', estimatedMinutes: 30),
        );
        await repository.insert(
          Task(
            id: 'review-study',
            title: '完成编程练习',
            estimatedMinutes: 60,
            scheduledRange: TimeRange(
              start: DateTime(now.year, now.month, now.day, 16),
              end: DateTime(now.year, now.month, now.day, 17),
            ),
          ),
        );
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: StudentLifeApp(initialRoute: route),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final navigator = find.byType(Navigator).first;
        expect(
          tester.getSize(navigator).width,
          math.min(AppViewport.maxWidth, size.width),
        );
        if (route == AppRoutes.menu || route == AppRoutes.bedroom) {
          expect(find.byType(AppBar), findsNothing);
          final viewport = tester.getRect(
            find.byKey(const Key('scene-viewport')),
          );
          final background = tester.getRect(
            find.byKey(
              Key(
                route == AppRoutes.menu
                    ? 'hall-background'
                    : 'bedroom-background',
              ),
            ),
          );
          expect(background.left, lessThanOrEqualTo(viewport.left + 0.01));
          expect(background.right, greaterThanOrEqualTo(viewport.right - 0.01));
          expect(background.top, lessThanOrEqualTo(viewport.top + 0.01));
          expect(
            background.bottom,
            greaterThanOrEqualTo(viewport.bottom - 0.01),
          );
        } else {
          expect(
            tester.getSize(find.byType(AppBar).first).width,
            lessThanOrEqualTo(430),
          );
        }
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          final directory = Directory('build/ui-review');
          await directory.create(recursive: true);
          await File(
            '${directory.path}/$name.png',
          ).writeAsBytes(bytes.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox());
      } finally {
        debugDisableShadows = previousShadows;
      }
    });
  }

  testWidgets(
    'high density phone uses logical width and keeps the task form above the keyboard',
    (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(1170, 2532);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        const StudentLifeApp(initialRoute: AppRoutes.schedule),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(Navigator)).width, 390);
      await tester.tap(find.byKey(const Key('day-schedule-add-task')));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      await tester.pumpAndSettle();
      final title = find.byKey(const Key('add-task-title'));
      await tester.ensureVisible(title);
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(title).dy, lessThanOrEqualTo(544));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('hall has four guarded doors and no app-style navigation', (
    tester,
  ) async {
    await tester.pumpWidget(const StudentLifeApp(initialRoute: AppRoutes.menu));
    await tester.pumpAndSettle();
    expect(find.byType(MenuPage), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    for (final id in ['schedule', 'gpa', 'finance', 'dashboard']) {
      await tester.tap(find.byKey(Key('door-$id')));
      await tester.pumpAndSettle();
      expect(find.byType(MenuPage), findsOneWidget);
    }
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
      isFalse,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
