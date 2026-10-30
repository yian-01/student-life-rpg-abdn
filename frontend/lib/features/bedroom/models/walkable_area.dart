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
    this.floorBounds = Rect.zero,
    this.obstacles = const <Rect>[],
  });

  final Rect bodyBounds;
  final Rect floorBounds;
  final List<Rect> obstacles;

  /// Floor membership and sprite/furniture collision are distinct checks.
  bool canOccupy(Offset foot) {
    if (!foot.dx.isFinite || !foot.dy.isFinite || !contains(foot)) return false;
    final floor = floorBounds.shift(foot);
    if (![
      floor.topLeft,
      floor.topRight,
      floor.bottomLeft,
      floor.bottomRight,
    ].every(contains)) {
      return false;
    }
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

  /// Follow a nearby sloping floor edge for vertical input. Projection onto its
  /// tangent preserves the wall distance for both W and S; it never exceeds the
  /// requested step length. Every candidate still passes full occupancy checks.
  Offset? _verticalWallSlide(Offset position, Offset step) {
    if (step.dx.abs() > 1e-9 || step.dy.abs() < 1e-9) return null;
    final floor = floorBounds.shift(position);
    final corners = [
      floor.topLeft,
      floor.topRight,
      floor.bottomLeft,
      floor.bottomRight,
    ];
    Offset? best;
    var nearest = maxSubstepLength + 1e-9;
    for (var i = 0; i < _polygon.length; i++) {
      final a = _polygon[i];
      final edge = _polygon[(i + 1) % _polygon.length] - a;
      if (edge.dx.abs() < 1e-9 || edge.dy.abs() < 1e-9) continue;
      final lengthSquared = edge.distanceSquared;
      for (final corner in corners) {
        final relative = corner - a;
        final along =
            ((relative.dx * edge.dx + relative.dy * edge.dy) / lengthSquared)
                .clamp(0.0, 1.0);
        final distance = (corner - (a + edge * along)).distance;
        if (distance > nearest) continue;
        final tangent = edge / edge.distance;
        final slide = tangent * (step.dx * tangent.dx + step.dy * tangent.dy);
        final candidate = position + slide;
        if (slide.distance > 1e-9 && canOccupy(candidate)) {
          nearest = distance;
          best = candidate;
        }
      }
    }
    return best;
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
      final wallSlide = _verticalWallSlide(pos, step);
      if (wallSlide != null) {
        pos = wallSlide;
        continue;
      }
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
