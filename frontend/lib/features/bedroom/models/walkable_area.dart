import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

/// WalkableArea — 可行走区域判定与移动解算（Issue D，v1.0 草稿）。
///
/// 规则（与 code/scene_geometry_check.py 的 D 节完全一致）：
///  - 只约束**脚底点**（世界坐标），边界视为包含（贴边滑行前提）；
///  - 位移拆分为 <= 2 世界像素的子步，防止高速穿墙；
///  - 子步失败时依次尝试 x-only、y-only 分量，实现沿边滑动；
///    全失败则停住（不 clamp 到区域边界）。
///
/// 多边形顶点来自唯一配置 SceneGeometry.walkablePolygon，本类不复制数值。
class WalkableArea {
  const WalkableArea(
    this._polygon, {
    this.bodyBounds = Rect.zero,
    this.obstacles = const <Rect>[],
  });

  final Rect bodyBounds;
  final List<Rect> obstacles;

  /// Floor membership and sprite/furniture collision are distinct checks.
  bool canOccupy(Offset foot) {
    if (!foot.dx.isFinite || !foot.dy.isFinite || !contains(foot)) return false;
    final body = bodyBounds.shift(foot);
    return !obstacles.any(body.overlaps);
  }

  final List<Offset> _polygon;

  /// 单个子步的最大长度（世界像素）。
  static const double maxSubstepLength = 2.0;

  /// 脚底点是否在区域内（**边界包含**）。
  bool contains(Offset p) {
    const double eps = 1e-9;
    final n = _polygon.length;
    // 在边上 -> 直接视为包含
    for (var i = 0; i < n; i++) {
      final a = _polygon[i];
      final b = _polygon[(i + 1) % n];
      final cross =
          (p.dx - a.dx) * (b.dy - a.dy) - (p.dy - a.dy) * (b.dx - a.dx);
      if (cross.abs() < eps &&
          p.dx >= math.min(a.dx, b.dx) - eps &&
          p.dx <= math.max(a.dx, b.dx) + eps &&
          p.dy >= math.min(a.dy, b.dy) - eps &&
          p.dy <= math.max(a.dy, b.dy) + eps) {
        return true;
      }
    }
    // 射线法
    var inside = false;
    for (var i = 0; i < n; i++) {
      final a = _polygon[i];
      final b = _polygon[(i + 1) % n];
      final crosses =
          (a.dy > p.dy) != (b.dy > p.dy) &&
          p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx;
      if (crosses) inside = !inside;
    }
    return inside;
  }

  /// 将 [from] 按 [delta] 移动，返回解算后的脚底世界坐标。
  ///
  /// 每个 <= [maxSubstepLength] 的子步依次尝试：整步 -> x-only -> y-only；
  /// 均失败则停止（保留已达位置）。
  Offset resolveMove(Offset from, Offset delta) {
    final dist = delta.distance;
    if (dist == 0) return from;
    final steps = (dist / maxSubstepLength).ceil();
    final step = delta / steps.toDouble();
    var pos = from;
    for (var i = 0; i < steps; i++) {
      final next = pos + step;
      if (canOccupy(next)) {
        pos = next;
        continue;
      }
      final nextX = Offset(pos.dx + step.dx, pos.dy);
      if (canOccupy(nextX)) {
        pos = nextX;
        continue;
      }
      final nextY = Offset(pos.dx, pos.dy + step.dy);
      if (canOccupy(nextY)) {
        pos = nextY;
        continue;
      }
      break; // 受阻停住
    }
    return pos;
  }
}
