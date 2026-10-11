import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../models/scene_geometry.dart';
import '../models/walkable_area.dart';

/// 移动方向（键盘适配层的输入抽象，WASD 与方向键都映射到这四个方向）。
enum MoveDirection { up, down, left, right }

/// PlayerMovementController — 卧室场景角色移动（Issue D，交付 v1.1）。
///
/// 统一移动入口（复审意见 3）：
///  - [setMoveDirection] 是**唯一方向入口**：校验有限值，零方向停止，
///    非零方向归一化；
///  - 键盘 [setPressedKeys] 与摇杆 [setJoystickVector] 仅为**适配入口**，
///    各自完成按键合成/死区/钳制后，最终都调用 [setMoveDirection]；
///  - [update] 只消费统一方向状态 [_direction]；
///  - [clearInput] 清除全部方向状态（三入口汇聚一处，清 [_direction] 即全清）。
///
/// 移动规则（与 code/scene_geometry_check.py 同规则复算）：
///  - 世界速度恒定 120 原图像素/秒；方向归一化，斜行不加速；
///  - 键盘相反方向在适配层合成向量时抵消（left+right = 零方向）；
///  - [update] 的 dt 拒绝负值/非有限值（抛 [ArgumentError]），上限 0.05s
///    （超出截断）；dt=0 为合法空操作；
///  - 位移经 [WalkableArea.resolveMove] 拆 <=2px 子步并沿边滑动；
///    只约束脚底点；窗口缩放不影响移动（全部在 world 坐标进行）。
///
/// Menu 进出与返回规则（复审意见 4）：
///  - 进入 Menu 前调 [pauseForMenu]：暂停更新并清输入，**位置保留**；
///  - 从 Menu 返回调 [resumeFromMenu]：恢复更新，保留进入前的
///    [footPosition]，因输入已清空不会自动续走；
///  - [reset] **仅用于明确重新开始**（回 playerStart），普通返回不得调用。
class PlayerMovementController extends ChangeNotifier {
  PlayerMovementController({Offset? start})
    : _footPosition = start ?? SceneGeometry.playerStart;

  /// 世界移动速度（原图像素/秒）。
  static const double speedWorldPxPerSecond = 120;

  /// dt 上限（秒）。
  static const double maxDt = 0.05;

  /// 摇杆死区（钳制后幅度小于该值视为无输入）。
  static const double joystickDeadZone = 0.15;

  final WalkableArea _area = WalkableArea(SceneGeometry.walkablePolygon);

  Offset _footPosition;
  Offset _direction = Offset.zero; // 统一方向状态（归一化或零向量）
  bool _paused = false;

  /// 当前脚底世界坐标（E 的交互距离判定读取此值）。
  Offset get footPosition => _footPosition;

  bool get isPaused => _paused;

  /// 当前统一方向（归一化或 Offset.zero；供调试与测试断言）。
  Offset get moveDirection => _direction;

  /// 是否存在有效方向输入（且未暂停）。
  bool get isMoving => !_paused && _direction != Offset.zero;

  /// 统一移动入口：设置移动方向。
  /// - 分量必须有限，否则抛 [ArgumentError]；
  /// - 零方向 = 停止；
  /// - 非零方向归一化（速度恒定，与输入幅度无关）。
  void setMoveDirection(Offset direction) {
    if (!direction.dx.isFinite || !direction.dy.isFinite) {
      throw ArgumentError('move direction must be finite: $direction');
    }
    _direction = direction == Offset.zero
        ? Offset.zero
        : direction / direction.distance;
  }

  /// 键盘适配入口（Windows）：传入当前按下的方向集合，整体替换。
  /// 相反方向在合成向量时抵消；零向量经统一入口转为停止。
  void setPressedKeys(Set<MoveDirection> keys) {
    var dx = 0.0, dy = 0.0;
    if (keys.contains(MoveDirection.left)) dx -= 1;
    if (keys.contains(MoveDirection.right)) dx += 1;
    if (keys.contains(MoveDirection.up)) dy -= 1;
    if (keys.contains(MoveDirection.down)) dy += 1;
    setMoveDirection(Offset(dx, dy));
  }

  /// 摇杆适配入口（Android）：[vector] 为摇杆偏移。
  /// 非有限分量抛 [ArgumentError]；幅度钳制 <=1；钳制后幅度 < 死区
  /// 视为无输入；其余经统一入口归一化（v1 匀速，幅度不映射速度）。
  void setJoystickVector(Offset vector) {
    if (!vector.dx.isFinite || !vector.dy.isFinite) {
      throw ArgumentError('joystick vector must be finite: $vector');
    }
    final mag = vector.distance;
    final clamped = mag > 1 ? vector / mag : vector;
    setMoveDirection(
      clamped.distance < joystickDeadZone ? Offset.zero : clamped,
    );
  }

  /// 每帧推进。[dt] 秒；负值/非有限抛 [ArgumentError]；超过 [maxDt] 截断。
  /// 暂停期间为空操作。只消费统一方向 [_direction]。
  void update(double dt) {
    if (!dt.isFinite || dt < 0) {
      throw ArgumentError('dt must be finite and >= 0: $dt');
    }
    if (_paused) return;
    final clamped = dt > maxDt ? maxDt : dt;
    if (clamped == 0) return;
    if (_direction == Offset.zero) return;
    final next = _area.resolveMove(
      _footPosition,
      _direction * speedWorldPxPerSecond * clamped,
    );
    if (next != _footPosition) {
      _footPosition = next;
      notifyListeners();
    }
  }

  /// 暂停更新（保留位置与方向状态）。
  void pause() => _paused = true;

  /// 恢复更新。dt 上限已防止恢复后的跳帧位移。
  void resume() => _paused = false;

  /// 进入 Menu 前调用：暂停更新并清除全部输入。
  /// [footPosition] 保留，供返回后继续使用。
  void pauseForMenu() {
    pause();
    clearInput();
  }

  /// 从 Menu 返回调用：恢复更新。位置保留在进入前状态；
  /// 因输入已清空，不会自动续走。
  void resumeFromMenu() => resume();

  /// 清除全部方向状态（失焦/离开页面时调用；位置与暂停状态不变）。
  /// 键盘、摇杆、直接方向三入口汇聚于 [_direction]，清它即全清。
  void clearInput() {
    _direction = Offset.zero;
  }

  /// **仅用于明确重新开始**：清空输入、解除暂停、脚底回到
  /// [SceneGeometry.playerStart]。普通 Menu 返回不得调用（应使用
  /// [pauseForMenu] / [resumeFromMenu]）。
  void reset() {
    clearInput();
    _paused = false;
    _footPosition = SceneGeometry.playerStart;
    notifyListeners();
  }
}
