import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/app_data.dart';
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
      final bar = find.byType(AppBar).first;
      expect(tester.getSize(bar).width, lessThanOrEqualTo(430));
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final directory = Directory('build/ui-review');
        await directory.create(recursive: true);
        await File(
          '${directory.path}/$name.png',
        ).writeAsBytes(bytes.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('bottom navigation switches modules without growing the stack', (
    tester,
  ) async {
    await tester.pumpWidget(const StudentLifeApp(initialRoute: AppRoutes.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.event_note_outlined).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('学业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手册'));
    await tester.pumpAndSettle();
    expect(find.text('我的校园'), findsOneWidget);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}
