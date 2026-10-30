// 状态：已在 frontend 内实际执行通过（flutter test，分支
// feat/8-bedroom-movement）。所有期望值同时由交付包
// docs/development/docs/development/scene-geometry-check.py（68 项全 PASS）独立复算印证。

//
// v1.1 变更（复审意见 3/4）：
//  - 统一移动入口 setMoveDirection：有限值校验、零方向停止、非零归一化；
//  - Menu 生命周期：pauseForMenu → resumeFromMenu 位置保留、不自动续走；
//  - reset 仅用于明确重新开始（原"reset 回起点"测试保留为重开测试）。

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/bedroom/controllers/player_movement_controller.dart';
import 'package:student_life_rpg/features/bedroom/models/walkable_area.dart';
import 'package:student_life_rpg/features/bedroom/models/scene_geometry.dart';

void main() {
  group('WalkableArea 边界与滑动（多边形边界包含，勿与 sceneRect 半开混改）', () {
    final area = WalkableArea(SceneGeometry.walkablePolygon);

    test('边界点包含：P3(550,1060)、P4(550,1385) 在区域内', () {
      expect(area.contains(const Offset(550, 1060)), isTrue);
      expect(area.contains(const Offset(550, 1385)), isTrue);
    });

    test('子步 <= 2px：6px 位移拆为 3 个子步，终点精确', () {
      final end = area.resolveMove(
        SceneGeometry.playerStart,
        const Offset(6, 0),
      );
      expect(end.dx, closeTo(366, 1e-9));
      expect(end.dy, closeTo(1160, 1e-9));
    });
  });

  group('ground footprint and wall clearance regression', () {
    test('feet on raw floor do not permit furniture or wall penetration', () {
      for (final foot in [const Offset(550, 1200), const Offset(500, 960)]) {
        expect(
          WalkableArea(SceneGeometry.walkablePolygon).contains(foot),
          isTrue,
        );
        expect(
          () => PlayerMovementController(start: foot),
          throwsArgumentError,
        );
      }
    });

    test(
      'all directions keep ground occupancy clear of furniture and walls',
      () {
        for (final direction in [
          const Offset(1, 0),
          const Offset(0, -1),
          const Offset(1, -1),
          const Offset(1, 1),
          const Offset(-1, 0),
          const Offset(-1, -1),
          const Offset(-1, 1),
          const Offset(0, 1),
        ]) {
          final controller = PlayerMovementController();
          controller.setMoveDirection(direction);
          for (var frame = 0; frame < 400; frame++) {
            controller.update(0.05);
            final body = SceneGeometry.playerCollisionBounds.shift(
              controller.footPosition,
            );
            final floor = SceneGeometry.playerFloorClearance.shift(
              controller.footPosition,
            );
            final area = WalkableArea(SceneGeometry.walkablePolygon);
            for (final corner in [
              floor.topLeft,
              floor.topRight,
              floor.bottomLeft,
              floor.bottomRight,
            ]) {
              expect(area.contains(corner), isTrue);
            }
            for (final furniture in SceneGeometry.furnitureObstacles) {
              expect(body.overlaps(furniture), isFalse);
            }
          }
          controller.dispose();
        }
      },
    );

    test(
      'can stand immediately in front of the bed without a head-height gap',
      () {
        final controller = PlayerMovementController(
          start: const Offset(480, 990),
        );
        controller.setMoveDirection(const Offset(0, -1));
        for (var i = 0; i < 100; i++) {
          controller.update(0.05);
        }
        expect(controller.footPosition.dy, lessThan(990));
        expect(controller.footPosition.dy, greaterThanOrEqualTo(966));
        // Upper body can visually overlap the footboard while feet remain in front.
        expect(
          SceneGeometry.playerBodyBounds
              .shift(controller.footPosition)
              .overlaps(SceneGeometry.furnitureObstacles.first),
          isTrue,
        );
        controller.dispose();
      },
    );

    test('can walk from spawn into the aisle below the bedside cabinet', () {
      final controller = PlayerMovementController();
      controller.setMoveDirection(const Offset(0, -1));
      for (var i = 0; i < 70; i++) {
        controller.update(0.05);
      }
      expect(controller.footPosition.dx, 360);
      expect(controller.footPosition.dy, lessThanOrEqualTo(850));
      expect(controller.footPosition.dy, greaterThanOrEqualTo(794));
      // Turning into the bed at this depth is still blocked.
      controller.setMoveDirection(const Offset(1, 0));
      for (var i = 0; i < 100; i++) {
        controller.update(0.05);
      }
      expect(controller.footPosition.dx, lessThanOrEqualTo(372));
      final footprint = SceneGeometry.playerCollisionBounds.shift(
        controller.footPosition,
      );
      expect(
        footprint.overlaps(SceneGeometry.furnitureObstacles.first),
        isFalse,
      );
      controller.dispose();
    });

    test('door remains reachable with body collision enabled', () {
      final controller = PlayerMovementController();
      controller.setMoveDirection(const Offset(-1, 0));
      for (var i = 0; i < 20; i++) {
        controller.update(0.05);
      }
      expect(
        (controller.footPosition - SceneGeometry.menuInteractionPoint).distance,
        lessThanOrEqualTo(SceneGeometry.menuInteractionRadius),
      );
      controller.dispose();
    });
  });

  group('统一移动入口 setMoveDirection（复审意见 3）', () {
    test('非有限分量抛 ArgumentError', () {
      final c = PlayerMovementController();
      expect(
        () => c.setMoveDirection(const Offset(double.nan, 0)),
        throwsArgumentError,
      );
      expect(
        () => c.setMoveDirection(const Offset(0, double.infinity)),
        throwsArgumentError,
      );
    });

    test('零方向 = 停止', () {
      final c = PlayerMovementController();
      c.setMoveDirection(const Offset(1, 0));
      expect(c.isMoving, isTrue);
      c.setMoveDirection(Offset.zero);
      expect(c.isMoving, isFalse);
      c.update(0.05);
      expect(c.footPosition, SceneGeometry.playerStart);
    });

    test('非零方向归一化：(3,4) 与 (0.6,0.8) 等效，速度恒定', () {
      final c = PlayerMovementController();
      c.setMoveDirection(const Offset(3, 4));
      expect(c.moveDirection.dx, closeTo(0.6, 1e-9));
      expect(c.moveDirection.dy, closeTo(0.8, 1e-9));
      for (var i = 0; i < 20; i++) {
        c.update(0.05);
      }
      expect(c.footPosition.dx, closeTo(360 + 120 * 0.6, 1e-6));
      expect(c.footPosition.dy, closeTo(1160 + 120 * 0.8, 1e-6));
    });

    test('clearInput 清除全部方向状态（键盘/摇杆/直接方向三入口）', () {
      final c = PlayerMovementController();
      c.setPressedKeys({MoveDirection.right});
      c.clearInput();
      expect(c.isMoving, isFalse);
      c.setJoystickVector(const Offset(1, 0));
      c.clearInput();
      expect(c.isMoving, isFalse);
      c.setMoveDirection(const Offset(0, 1));
      c.clearInput();
      expect(c.isMoving, isFalse);
      c.update(0.05);
      expect(c.footPosition, SceneGeometry.playerStart);
    });
  });

  group('键盘适配入口（Windows）验收硬指标', () {
    test('直行：dt=0.05 连走 20 次，x 位移恰好 120', () {
      final c = PlayerMovementController();
      c.setPressedKeys({MoveDirection.right});
      for (var i = 0; i < 20; i++) {
        c.update(0.05);
      }
      expect(c.footPosition.dx, closeTo(480, 1e-9));
      expect(c.footPosition.dy, closeTo(1160, 1e-9));
    });

    test('斜行：dt=0.05 连走 20 次，路径总长仍 120（方向归一化）', () {
      final c = PlayerMovementController();
      c.setPressedKeys({MoveDirection.right, MoveDirection.down});
      for (var i = 0; i < 20; i++) {
        c.update(0.05);
      }
      final d = math.sqrt(
        math.pow(c.footPosition.dx - 360, 2) +
            math.pow(c.footPosition.dy - 1160, 2),
      );
      expect(d, closeTo(120, 1e-6));
      expect(c.footPosition.dx, closeTo(444.8528, 1e-3));
      expect(c.footPosition.dy, closeTo(1244.8528, 1e-3));
    });

    test('相反方向抵消：left+right 经适配层合成为零方向，不动', () {
      final c = PlayerMovementController();
      c.setPressedKeys({MoveDirection.left, MoveDirection.right});
      expect(c.isMoving, isFalse);
      for (var i = 0; i < 10; i++) {
        c.update(0.05);
      }
      expect(c.footPosition, SceneGeometry.playerStart);
    });

    test('沿边滑动：书桌左侧右下输入不越界', () {
      final c = PlayerMovementController(start: const Offset(488, 1200));
      c.setPressedKeys({MoveDirection.right, MoveDirection.down});
      final area = WalkableArea(SceneGeometry.walkablePolygon);
      for (var i = 0; i < 5; i++) {
        c.update(0.05);
        expect(area.contains(c.footPosition), isTrue);
      }
    });

    test('角落压迫：右下角 50 步始终不越界，且不超出 x<=550、y<=1385', () {
      final c = PlayerMovementController(start: const Offset(488, 1370));
      c.setPressedKeys({MoveDirection.right, MoveDirection.down});
      final area = WalkableArea(SceneGeometry.walkablePolygon);
      for (var i = 0; i < 50; i++) {
        c.update(0.05);
        expect(area.contains(c.footPosition), isTrue);
      }
      expect(c.footPosition.dx, lessThanOrEqualTo(550));
      expect(c.footPosition.dy, lessThanOrEqualTo(1385));
    });
  });

  group('dt 规则', () {
    test('负值/NaN/Inf 抛 ArgumentError', () {
      final c = PlayerMovementController();
      expect(() => c.update(-0.01), throwsArgumentError);
      expect(() => c.update(double.nan), throwsArgumentError);
      expect(() => c.update(double.infinity), throwsArgumentError);
    });

    test('dt=0.1 截断为 0.05：位移 6 而非 12', () {
      final c = PlayerMovementController();
      c.setPressedKeys({MoveDirection.right});
      c.update(0.1);
      expect(c.footPosition.dx, closeTo(366, 1e-9));
    });

    test('dt=0 为合法空操作', () {
      final c = PlayerMovementController();
      c.setPressedKeys({MoveDirection.right});
      c.update(0);
      expect(c.footPosition, SceneGeometry.playerStart);
    });
  });

  group('Menu 进出与返回（复审意见 4）', () {
    test('进入 Menu：pauseForMenu 暂停并清输入，位置保留', () {
      final c = PlayerMovementController();
      c.setPressedKeys({MoveDirection.right});
      for (var i = 0; i < 10; i++) {
        c.update(0.05);
      }
      final before = c.footPosition; // (420, 1160)
      c.pauseForMenu();
      expect(c.isPaused, isTrue);
      expect(c.isMoving, isFalse);
      expect(c.footPosition, before);
      c.update(0.05); // Menu 期间即便有帧回调也无位移
      expect(c.footPosition, before);
    });

    test('暂停→清输入→返回→位置不变且不自动续走', () {
      final c = PlayerMovementController();
      c.setPressedKeys({MoveDirection.right});
      for (var i = 0; i < 10; i++) {
        c.update(0.05);
      }
      final before = c.footPosition;
      c.pauseForMenu(); // 进入 Menu：暂停 + 清输入
      c.resumeFromMenu(); // 返回：恢复更新
      expect(c.isPaused, isFalse);
      expect(c.footPosition, before); // 位置保留在进入前
      c.update(0.05); // 输入已清空，不自动续走
      expect(c.footPosition, before);
      expect(c.isMoving, isFalse);
    });

    test('普通返回不得调用 reset：resumeFromMenu 不改变位置', () {
      final c = PlayerMovementController();
      c.setPressedKeys({MoveDirection.down});
      for (var i = 0; i < 10; i++) {
        c.update(0.05);
      }
      final before = c.footPosition;
      c.pauseForMenu();
      c.resumeFromMenu();
      expect(c.footPosition, before);
      expect(c.footPosition, isNot(SceneGeometry.playerStart));
    });
  });

  group('明确重新开始（reset 仅限此用途）', () {
    test('reset 回 playerStart 并清空输入（重开测试，保留自 v1.0）', () {
      final c = PlayerMovementController();
      c.setPressedKeys({MoveDirection.right});
      for (var i = 0; i < 10; i++) {
        c.update(0.05);
      }
      c.reset();
      expect(c.footPosition, SceneGeometry.playerStart);
      expect(c.isMoving, isFalse);
      c.update(0.05);
      expect(c.footPosition, SceneGeometry.playerStart);
    });
  });

  group('摇杆适配入口（Android）', () {
    test('死区 0.15：(0.10,0.10) 不触发移动', () {
      final c = PlayerMovementController();
      c.setJoystickVector(const Offset(0.10, 0.10));
      expect(c.isMoving, isFalse);
      c.update(0.05);
      expect(c.footPosition, SceneGeometry.playerStart);
    });

    test('超幅 (3,4) 钳制后归一化，直行 20 步位移 120（与键盘一致）', () {
      final c = PlayerMovementController();
      c.setJoystickVector(const Offset(3, 4));
      for (var i = 0; i < 20; i++) {
        c.update(0.05);
      }
      expect(c.footPosition.dx, closeTo(360 + 120 * 0.6, 1e-6));
      expect(c.footPosition.dy, closeTo(1160 + 120 * 0.8, 1e-6));
    });

    test('非有限摇杆分量抛 ArgumentError', () {
      final c = PlayerMovementController();
      expect(
        () => c.setJoystickVector(const Offset(double.nan, 0)),
        throwsArgumentError,
      );
    });

    test('摇杆抬起（零向量）即停止', () {
      final c = PlayerMovementController();
      c.setJoystickVector(const Offset(1, 0));
      expect(c.isMoving, isTrue);
      c.setJoystickVector(Offset.zero);
      expect(c.isMoving, isFalse);
    });
  });
  group('start 参数校验（复审意见 1）', () {
    test('非有限坐标抛 ArgumentError', () {
      expect(
        () => PlayerMovementController(start: const Offset(double.nan, 0)),
        throwsArgumentError,
      );
      expect(
        () => PlayerMovementController(start: const Offset(0, double.infinity)),
        throwsArgumentError,
      );
    });

    test('可行走区域外的初始位置抛 ArgumentError', () {
      expect(
        () => PlayerMovementController(start: const Offset(360, 740)),
        throwsArgumentError,
      ); // 上方床区
      expect(
        () => PlayerMovementController(start: const Offset(700, 1200)),
        throwsArgumentError,
      ); // 右侧书桌外
      expect(
        () => PlayerMovementController(start: const Offset(360, 1500)),
        throwsArgumentError,
      ); // 下方栅栏外
    });

    test('默认出生点、区域内部点、合法边界点正常创建', () {
      expect(
        PlayerMovementController().footPosition,
        SceneGeometry.playerStart,
      );
      expect(
        PlayerMovementController(start: const Offset(300, 1200)).footPosition,
        const Offset(300, 1200),
      ); // 内部
      expect(
        PlayerMovementController(start: const Offset(488, 1200)).footPosition,
        const Offset(488, 1200),
      ); // 书桌左侧安全点
      expect(
        PlayerMovementController(start: const Offset(150, 1370)).footPosition,
        const Offset(150, 1370),
      ); // 顶点 P5
    });
  });

  group('稳定归一化（复审意见 2）', () {
    test('极大有限方向：归一化为有限单位向量，update 后位置有限且在区域内', () {
      final c = PlayerMovementController();
      c.setMoveDirection(const Offset(1e308, 1e308));
      expect(c.isMoving, isTrue);
      expect(c.moveDirection.distance, closeTo(1, 1e-9));
      c.update(0.05);
      expect(c.footPosition.dx.isFinite && c.footPosition.dy.isFinite, isTrue);
      expect(
        WalkableArea(SceneGeometry.walkablePolygon).contains(c.footPosition),
        isTrue,
      );
    });

    test('极小非零方向：不下溢，归一化为单位向量', () {
      final c = PlayerMovementController();
      c.setMoveDirection(const Offset(1e-300, 0));
      expect(c.moveDirection, const Offset(1, 0));
      c.update(0.05);
      expect(c.footPosition.dx, greaterThan(SceneGeometry.playerStart.dx));
    });

    test('极大摇杆输入：按幅度钳制为单位向量', () {
      final c = PlayerMovementController();
      c.setJoystickVector(const Offset(1e308, -1e308));
      expect(c.moveDirection.distance, closeTo(1, 1e-9));
      c.update(0.05);
      expect(c.footPosition.dx.isFinite && c.footPosition.dy.isFinite, isTrue);
      expect(
        WalkableArea(SceneGeometry.walkablePolygon).contains(c.footPosition),
        isTrue,
      );
    });

    test('极小摇杆输入：低于死区视为无输入', () {
      final c = PlayerMovementController();
      c.setJoystickVector(const Offset(1e-300, 1e-300));
      expect(c.moveDirection, Offset.zero);
      expect(c.isMoving, isFalse);
    });
  });

  group('Menu 返回再次清输入（复审意见 3）', () {
    test('暂停期间重写方向，返回后位置保持、方向为零、不自动续走', () {
      final c = PlayerMovementController();
      c.setMoveDirection(const Offset(1, 0));
      c.update(0.05);
      final posBefore = c.footPosition;
      c.pauseForMenu();
      c.setMoveDirection(const Offset(0, 1)); // 暂停期间适配层重新写入方向
      c.resumeFromMenu();
      expect(c.isPaused, isFalse);
      expect(c.moveDirection, Offset.zero);
      c.update(0.05);
      expect(c.footPosition, posBefore); // 位置保持，不自动移动
      c.setMoveDirection(const Offset(0, 1)); // 重新输入才开始移动
      c.update(0.05);
      expect(c.footPosition.dy, greaterThan(posBefore.dy));
    });
  });
}
