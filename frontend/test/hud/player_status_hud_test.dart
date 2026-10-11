import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/hud/models/hud_view_data.dart';
import 'package:student_life_rpg/features/hud/presentation/player_status_hud.dart';
import 'package:student_life_rpg/features/hud/presentation/player_status_hud_overlay.dart';

HudViewData data({String name = 'Demo Player', int level = 1, int exp = 0}) =>
    HudViewData(displayName: name, level: level, exp: exp, expToNextLevel: 100);

Widget host(
  HudViewData data,
  Rect rect, {
  double worldScale = 1,
  double playerX = 0,
}) => MaterialApp(
  home: Scaffold(
    body: Stack(
      children: [
        Transform.scale(
          scale: worldScale,
          child: Align(
            alignment: Alignment.topLeft,
            child: Transform.translate(
              offset: Offset(playerX, 0),
              child: const SizedBox(width: 5, height: 5),
            ),
          ),
        ),
        PlayerStatusHudOverlay(data: data, sceneRect: rect),
      ],
    ),
  ),
);

void main() {
  testWidgets(
    'external demo data changes level, raw text and progress together',
    (tester) async {
      const rect = Rect.fromLTWH(100, 30, 320, 500);
      await tester.pumpWidget(host(data(), rect));
      expect(find.text('Lv 1'), findsOneWidget);
      expect(find.text('EXP 0/100'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0,
      );
      await tester.pumpWidget(host(data(level: 2, exp: 25), rect));
      expect(find.text('Lv 2'), findsOneWidget);
      expect(find.text('EXP 25/100'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .25,
      );
      await tester.pumpWidget(host(data(exp: 150), rect));
      expect(find.text('Lv 1'), findsOneWidget);
      expect(find.text('EXP 150/100'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        1,
      );
    },
  );

  testWidgets(
    'resize repositions HUD with fixed margin; world transforms do not affect HUD',
    (tester) async {
      await tester.pumpWidget(
        host(data(), const Rect.fromLTWH(200, 10, 300, 500)),
      );
      final initial = tester.getTopLeft(find.byType(PlayerStatusHud));
      final textHeight = tester.getSize(find.text('Lv 1')).height;
      expect(initial, const Offset(212, 22));
      await tester.pumpWidget(
        host(
          data(),
          const Rect.fromLTWH(200, 10, 300, 500),
          worldScale: .3,
          playerX: 90,
        ),
      );
      expect(tester.getTopLeft(find.byType(PlayerStatusHud)), initial);
      expect(tester.getSize(find.text('Lv 1')).height, textHeight);
      await tester.pumpWidget(
        host(data(), const Rect.fromLTWH(0, 35, 160, 500), worldScale: .1),
      );
      expect(
        tester.getTopLeft(find.byType(PlayerStatusHud)),
        const Offset(12, 47),
      );
      expect(tester.getSize(find.byType(PlayerStatusHud)).width, 136);
      expect(tester.getSize(find.text('Lv 1')).height, textHeight);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [26.0, 80.0, 160.0, 320.0]) {
    testWidgets(
      'long name and large text fit scene width $width with vertical scrolling',
      (tester) async {
        final longName = 'A very long student display name 名称测试 ' * 8;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Stack(
                  children: [
                    PlayerStatusHudOverlay(
                      data: data(name: longName),
                      sceneRect: Rect.fromLTWH(0, 0, width, 150),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(find.text(longName), findsOneWidget);
        expect(
          tester.getSize(find.byType(PlayerStatusHud)).width,
          lessThanOrEqualTo(width - 24),
        );
        final text = tester.widget<Text>(find.text(longName));
        expect(text.maxLines, isNull);
        expect(text.overflow, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'zero, negative, insufficient and non-finite rects do not layout HUD',
    (tester) async {
      for (final rect in [
        Rect.zero,
        const Rect.fromLTWH(0, 0, -1, 300),
        const Rect.fromLTWH(0, 0, 24, 300),
        const Rect.fromLTWH(0, 0, 100, 24),
        const Rect.fromLTWH(double.nan, 0, 100, 300),
        const Rect.fromLTWH(0, 0, double.infinity, 300),
      ]) {
        await tester.pumpWidget(host(data(), rect));
        expect(find.byType(PlayerStatusHud), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('accessible label includes name, level, raw exp and threshold', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(data(level: 2, exp: 150), const Rect.fromLTWH(0, 0, 300, 500)),
    );
    expect(
      find.bySemanticsLabel('Demo Player，等级 2，经验 150/100'),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
