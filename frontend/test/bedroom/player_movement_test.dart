// 状态：已在 frontend 内实际执行通过（flutter test，分支
// feat/8-bedroom-movement）。所有期望值同时由交付包
// scene_geometry_check.py（68 项全 PASS）独立复算印证。

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

    test('沿边滑动：斜边处右下输入不越界', () {
      final c = PlayerMovementController(start: const Offset(555, 1000));
      c.setPressedKeys({MoveDirection.right, MoveDirection.down});
      final area = WalkableArea(SceneGeometry.walkablePolygon);
      for (var i = 0; i < 5; i++) {
        c.update(0.05);
        expect(area.contains(c.footPosition), isTrue);
      }
    });

    test('角落压迫：右下角 50 步始终不越界，且不超出 x<=550、y<=1385', () {
      final c = PlayerMovementController(start: const Offset(545, 1378));
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
}
