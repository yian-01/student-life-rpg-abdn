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
///    脚底检查地板，地面占位检查家具，四角检查墙边余量；窗口缩放不影响移动（全部在 world 坐标进行）。
///
/// Menu 进出与返回规则（复审意见 4）：
///  - 进入 Menu 前调 [pauseForMenu]：暂停更新并清输入，**位置保留**；
///  - 从 Menu 返回调 [resumeFromMenu]：恢复更新，保留进入前的
///    [footPosition]，因输入已清空不会自动续走；
///  - [reset] **仅用于明确重新开始**（回 playerStart），普通返回不得调用。
class PlayerMovementController extends ChangeNotifier {
  PlayerMovementController({Offset? start, WalkableArea? area})
    : _resetPosition = area == null
          ? SceneGeometry.playerStart
          : (start ?? SceneGeometry.playerStart),
      _area = area ?? _bedroomArea,
      _footPosition = _checkedStart(
        start ?? SceneGeometry.playerStart,
        area ?? _bedroomArea,
      );

  /// 出生点校验（复审意见 1）：坐标必须有限，且落在可行走区域内
  /// （边界合法，与 WalkableArea.contains 的边界包含语义一致）。
  static Offset _checkedStart(Offset start, WalkableArea area) {
    if (!start.dx.isFinite || !start.dy.isFinite) {
      throw ArgumentError('start must be finite: $start');
    }
    if (!area.canOccupy(start)) {
      throw ArgumentError(
        'start must be on clear floor without furniture overlap: $start',
      );
    }
    return start;
  }

  /// 世界移动速度（原图像素/秒）。
  static const double speedWorldPxPerSecond = 120;

  /// dt 上限（秒）。
  static const double maxDt = 0.05;

  /// 摇杆死区（钳制后幅度小于该值视为无输入）。
  static const double joystickDeadZone = 0.15;

  static final WalkableArea _bedroomArea = WalkableArea(
    SceneGeometry.walkablePolygon,
    bodyBounds: SceneGeometry.playerCollisionBounds,
    floorBounds: SceneGeometry.playerFloorClearance,
    obstacles: SceneGeometry.furnitureObstacles,
  );

  final Offset _resetPosition;
  final WalkableArea _area;
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
  /// - 非零方向**稳定归一化**（先按最大分量缩放再求长度，防溢出/下溢），
  ///   保证 [_direction] 始终为零向量或有限单位向量。
  void setMoveDirection(Offset direction) {
    if (!direction.dx.isFinite || !direction.dy.isFinite) {
      throw ArgumentError('move direction must be finite: $direction');
    }
    _direction = _normalizeStable(direction);
  }

  /// 稳定归一化（复审意见 2）：先按最大分量绝对值缩放，再求长度归一。
  /// 避免极大有限分量使 distance 平方和溢出、极小非零分量使长度下溢；
  /// 零向量单独处理。缩放后分量绝对值 ≤ 1，distance ∈ [1, √2]，不溢出。
  static Offset _normalizeStable(Offset v) {
    final ax = v.dx.abs();
    final ay = v.dy.abs();
    final maxAbs = ax > ay ? ax : ay;
    if (maxAbs == 0) return Offset.zero;
    final scaled = v / maxAbs;
    return scaled / scaled.distance;
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
  /// 非有限分量抛 [ArgumentError]；幅度在缩放空间计算（防溢出），
  /// 低于死区视为无输入；其余经统一入口稳定归一化——幅度 >1 自然钳为
  /// 单位向量（v1 匀速，幅度不映射速度）。
  void setJoystickVector(Offset vector) {
    if (!vector.dx.isFinite || !vector.dy.isFinite) {
      throw ArgumentError('joystick vector must be finite: $vector');
    }
    final ax = vector.dx.abs();
    final ay = vector.dy.abs();
    final maxAbs = ax > ay ? ax : ay;
    if (maxAbs == 0) {
      setMoveDirection(Offset.zero);
      return;
    }
    // 实际幅度 = maxAbs × scaled.distance；极大输入时乘积可能为 Infinity，
    // 但仅用于与死区阈值比较（Infinity < 0.15 为 false），不参与后续计算。
    final magnitude = maxAbs * (vector / maxAbs).distance;
    if (magnitude < joystickDeadZone) {
      setMoveDirection(Offset.zero);
    } else {
      setMoveDirection(vector);
    }
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

  /// 从 Menu 返回调用：**先再次清除全部输入**（暂停期间适配层可能重新
  /// 写入方向），再恢复更新。位置保留在进入前状态，不会自动续走。
  void resumeFromMenu() {
    clearInput();
    resume();
  }

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
    _footPosition = _resetPosition;
    notifyListeners();
  }
}
