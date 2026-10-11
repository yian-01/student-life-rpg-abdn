// 状态：已在 frontend 内实际执行通过（flutter test，分支
// feat/8-bedroom-movement，pubspec name = student_life_rpg 已核实）。
// 所有期望值同时由交付包 scene_geometry_check.py（68 项全 PASS）独立复算印证。

//
// 覆盖检查 ①–⑧；v1.1（复审意见 1/2）：
//  - containsLocal 半开区间（与 Rect.contains 一致）：四边、四角、边内外；
//  - scale 运行时保护（if 抛 ArgumentError，非 assert）：
//    宽高非法值 + 极小正数导致 scale 下溢为 0。

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:student_life_rpg/features/bedroom/models/scene_geometry.dart';

/// 射线法点在多边形内（含边界由调用方另行核查；测试点均不在边上）。
bool _pointInPolygon(Offset p, List<Offset> poly) {
  var inside = false;
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    final crosses =
        (a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx;
    if (crosses) inside = !inside;
  }
  return inside;
}

/// 验证路径全程在区域内。**本 Dart 版仅做密集采样**（2001 个采样点）；
/// 精确的线段-多边形边求交核查在 docs/development/scene-geometry-check.py
/// （数学核查脚本，已执行通过）中完成，两处互为印证。
bool _segmentInsidePolygon(Offset a, Offset b, List<Offset> poly) {
  for (var i = 0; i <= 2000; i++) {
    final t = i / 2000;
    final p = Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
    if (!_pointInPolygon(p, poly)) return false;
  }
  return true;
}

double _dist(Offset a, Offset b) {
  final dx = a.dx - b.dx;
  final dy = a.dy - b.dy;
  return math.sqrt(dx * dx + dy * dy);
}

void main() {
  group('SceneGeometry 配置检查（③ ④ ⑤）', () {
    test('③ playerStart 与 menuInteractionPoint 均在 walkablePolygon 内', () {
      expect(
        _pointInPolygon(
          SceneGeometry.playerStart,
          SceneGeometry.walkablePolygon,
        ),
        isTrue,
      );
      expect(
        _pointInPolygon(
          SceneGeometry.menuInteractionPoint,
          SceneGeometry.walkablePolygon,
        ),
        isTrue,
      );
    });

    test('④ playerStart 至 menuInteractionPoint 存在区域内直线路径', () {
      expect(
        _segmentInsidePolygon(
          SceneGeometry.playerStart,
          SceneGeometry.menuInteractionPoint,
          SceneGeometry.walkablePolygon,
        ),
        isTrue,
      );
    });

    test('⑤ menuInteractionRadius 有限且 > 0', () {
      expect(SceneGeometry.menuInteractionRadius.isFinite, isTrue);
      expect(SceneGeometry.menuInteractionRadius, greaterThan(0));
    });

    test('初始位置不出现交互提示（距离 160.31 > 70）', () {
      final d = _dist(
        SceneGeometry.playerStart,
        SceneGeometry.menuInteractionPoint,
      );
      expect(d, greaterThan(SceneGeometry.menuInteractionRadius));
    });

    test('E 交互核查点：(269,1170)/(270,1170)/(271,1170) => 可触发/可触发/不可触发', () {
      final m = SceneGeometry.menuInteractionPoint;
      expect(_dist(const Offset(269, 1170), m), lessThanOrEqualTo(70));
      expect(_dist(const Offset(270, 1170), m), lessThanOrEqualTo(70));
      expect(_dist(const Offset(271, 1170), m), greaterThan(70));
    });
  });

  group('SceneTransform 视口计算（320x640 与 800x600）', () {
    test('320x640：scale=320/941，offsetX=0，offsetY≈35.7067', () {
      final t = SceneTransform.fit(320, 640);
      expect(t.scale, closeTo(320 / 941, 1e-9));
      expect(t.offset.dx, closeTo(0, 1e-9));
      expect(t.offset.dy, closeTo(35.7067, 1e-3));
      // 角色脚底与 Menu 入口的 local 预期位置（v1.1 文档第 8 节记录值）
      final foot = t.worldToLocal(SceneGeometry.playerStart);
      expect(foot.dx, closeTo(122.423, 1e-3));
      expect(foot.dy, closeTo(430.181, 1e-3));
      final menu = t.worldToLocal(SceneGeometry.menuInteractionPoint);
      expect(menu.dx, closeTo(68.013, 1e-3));
      expect(menu.dy, closeTo(433.581, 1e-3));
    });

    test('800x600：scale=600/1672，offsetX≈231.1603，offsetY=0', () {
      final t = SceneTransform.fit(800, 600);
      expect(t.scale, closeTo(600 / 1672, 1e-9));
      expect(t.offset.dx, closeTo(231.1603, 1e-3));
      expect(t.offset.dy, closeTo(0, 1e-9));
      final foot = t.worldToLocal(SceneGeometry.playerStart);
      expect(foot.dx, closeTo(360.347, 1e-3));
      expect(foot.dy, closeTo(416.268, 1e-3));
      final menu = t.worldToLocal(SceneGeometry.menuInteractionPoint);
      expect(menu.dx, closeTo(302.931, 1e-3));
      expect(menu.dy, closeTo(419.856, 1e-3));
    });

    test('非法视口（非正/非有限）抛出 ArgumentError，不参与除法', () {
      expect(() => SceneTransform.fit(0, 600), throwsArgumentError);
      expect(() => SceneTransform.fit(-5, 600), throwsArgumentError);
      expect(() => SceneTransform.fit(double.nan, 600), throwsArgumentError);
      expect(
        () => SceneTransform.fit(double.infinity, 600),
        throwsArgumentError,
      );
    });

    test('scale 运行时保护（复审意见 2）：极小正数视口使 scale 下溢为 0，抛 ArgumentError', () {
      // double.minPositive = 5e-324，除以 941 后下溢为 0.0，
      // 入口校验（>0 且有限）拦不住，必须由计算后 if 保护捕获。
      expect(
        () => SceneTransform.fit(double.minPositive, 600),
        throwsArgumentError,
      );
      expect(
        () => SceneTransform.fit(600, double.minPositive),
        throwsArgumentError,
      );
    });

    test('scale 运行时保护：正常视口 scale 有限且 >0，sceneRect 不超出视口', () {
      for (final size in [(320.0, 640.0), (800.0, 600.0)]) {
        final t = SceneTransform.fit(size.$1, size.$2);
        expect(t.scale.isFinite, isTrue);
        expect(t.scale, greaterThan(0));
        final r = t.sceneRect;
        expect(r.left, greaterThanOrEqualTo(-1e-9));
        expect(r.top, greaterThanOrEqualTo(-1e-9));
        expect(r.width, lessThanOrEqualTo(size.$1 + 1e-9));
        expect(r.height, lessThanOrEqualTo(size.$2 + 1e-9));
      }
    });
  });

  group('SceneTransform 往返误差（① ②）', () {
    for (final size in [(320.0, 640.0), (800.0, 600.0)]) {
      test('视口 ${size.$1}x${size.$2}：双方向往返最大误差 <= 0.01', () {
        final t = SceneTransform.fit(size.$1, size.$2);
        var errLocal = 0.0;
        var errWorld = 0.0;
        for (var gy = 0.0; gy <= SceneGeometry.worldHeight; gy += 19) {
          for (var gx = 0.0; gx <= SceneGeometry.worldWidth; gx += 17) {
            final w = Offset(gx, gy);
            final l = t.worldToLocal(w);
            // ② world -> local -> world
            final w2 = t.localToWorld(l);
            errWorld = math.max(
              errWorld,
              math.max((w2.dx - w.dx).abs(), (w2.dy - w.dy).abs()),
            );
            // ① local -> world -> local
            final l2 = t.worldToLocal(w2);
            errLocal = math.max(
              errLocal,
              math.max((l2.dx - l.dx).abs(), (l2.dy - l.dy).abs()),
            );
          }
        }
        expect(errLocal, lessThanOrEqualTo(0.01));
        expect(errWorld, lessThanOrEqualTo(0.01));
      });
    }
  });

  group('角色锚点与渲染位置', () {
    test('spriteScale=1.0，渲染高度 205，锚点不重复缩放', () {
      expect(SceneGeometry.spriteScale, closeTo(1.0, 1e-12));
      expect(SceneGeometry.playerRenderHeight, closeTo(205, 1e-9));
      final topLeft = SceneGeometry.spriteTopLeftWorld(
        SceneGeometry.playerStart,
      );
      // footWorld(360,1160) - anchor(51,195) x 1.0 = (309,965)
      expect(topLeft.dx, closeTo(309, 1e-9));
      expect(topLeft.dy, closeTo(965, 1e-9));
    });
  });

  group('sceneRect 公共接口与边界策略（⑥ ⑦ ⑧，v1.2 新增）', () {
    test('sceneRect = (offsetX, offsetY, 941*scale, 1672*scale)', () {
      final t = SceneTransform.fit(800, 600);
      final r = t.sceneRect;
      expect(r.left, closeTo(231.1603, 1e-3));
      expect(r.top, closeTo(0, 1e-9));
      expect(r.width, closeTo(941 * 600 / 1672, 1e-6)); // ≈ 337.6794
      expect(r.height, closeTo(600, 1e-9));
    });

    test('边界半开（复审意见 1）：左/上包含、右/下排除——四边、四角、边内外', () {
      final t = SceneTransform.fit(800, 600);
      final r = t.sceneRect;
      // 四边：左包含、右排除、上包含、下排除（与 Rect.contains 一致）
      expect(t.containsLocal(Offset(r.left, 300)), isTrue); // 左边包含
      expect(t.containsLocal(Offset(r.right, 300)), isFalse); // 右边排除
      expect(t.containsLocal(Offset(400, r.top)), isTrue); // 上边包含
      expect(t.containsLocal(Offset(400, r.bottom)), isFalse); // 下边排除
      // 四角：仅左上在内
      expect(t.containsLocal(Offset(r.left, r.top)), isTrue);
      expect(t.containsLocal(Offset(r.right, r.top)), isFalse);
      expect(t.containsLocal(Offset(r.left, r.bottom)), isFalse);
      expect(t.containsLocal(Offset(r.right, r.bottom)), isFalse);
      // 边内外（1e-3 步长）
      expect(t.containsLocal(Offset(r.left - 1e-3, 300)), isFalse);
      expect(t.containsLocal(Offset(r.right - 1e-3, 300)), isTrue);
      expect(t.containsLocal(Offset(400, r.top - 1e-3)), isFalse);
      expect(t.containsLocal(Offset(400, r.bottom - 1e-3)), isTrue);
      // localToWorldChecked 同步遵循：右边界点拒绝，左边界点接受
      expect(t.localToWorldChecked(Offset(r.right, 300)), isNull);
      expect(t.localToWorldChecked(Offset(r.left, 300)), isNotNull);
    });

    test('⑥ 宽窗口（800x600）两侧空白点击被拒绝，不 clamp', () {
      final t = SceneTransform.fit(800, 600);
      // 左侧空白：x < sceneRect.left ≈ 231.16
      expect(t.containsLocal(const Offset(100, 300)), isFalse);
      expect(t.localToWorldChecked(const Offset(100, 300)), isNull);
      // 右侧空白：x > sceneRect.right ≈ 568.83
      expect(t.containsLocal(const Offset(700, 300)), isFalse);
      expect(t.localToWorldChecked(const Offset(700, 300)), isNull);
      // 窄窗口（320x640）上下空白同样拒绝：y < offsetY ≈ 35.71
      final tall = SceneTransform.fit(320, 640);
      expect(tall.containsLocal(const Offset(160, 10)), isFalse);
      expect(tall.localToWorldChecked(const Offset(160, 10)), isNull);
    });

    test('⑦ 场景内点击接受，local↔world 往返误差 <= 0.01', () {
      final t = SceneTransform.fit(800, 600);
      // Menu 交互点的 local 预期位置（v1.1 记录值 (302.931, 419.856)）
      const local = Offset(302.931, 419.856);
      expect(t.containsLocal(local), isTrue);
      final world = t.localToWorldChecked(local);
      expect(world, isNotNull);
      expect(world!.dx, closeTo(200, 0.01));
      expect(world.dy, closeTo(1170, 0.01));
      final back = t.worldToLocal(world);
      expect(back.dx, closeTo(local.dx, 0.01));
      expect(back.dy, closeTo(local.dy, 0.01));
    });

    test('⑧ 窗口尺寸变化后世界常量与同一视口变换结果不变', () {
      final before = SceneTransform.fit(320, 640);
      final footBefore = before.worldToLocal(SceneGeometry.playerStart);
      // 模拟窗口变化：800x600 后再回到 320x640
      SceneTransform.fit(800, 600);
      final after = SceneTransform.fit(320, 640);
      final footAfter = after.worldToLocal(SceneGeometry.playerStart);
      // 同一视口的变换结果一致
      expect(after.scale, before.scale);
      expect(after.offset, before.offset);
      expect(footAfter, footBefore);
      // 世界常量未被修改
      expect(SceneGeometry.playerStart, const Offset(360, 1160));
      expect(SceneGeometry.walkablePolygon.first, const Offset(240, 960));
      expect(SceneGeometry.walkablePolygon.length, 6);
      expect(SceneGeometry.menuInteractionPoint, const Offset(200, 1170));
    });
  });
}
