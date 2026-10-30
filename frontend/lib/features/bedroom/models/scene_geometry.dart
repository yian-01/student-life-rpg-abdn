import 'dart:ui' show Offset, Rect, Size;

/// SceneGeometry — 卧室场景唯一坐标来源（Issue C / BASE-04，交付 v1.1，待组长审核冻结）。
///
/// 坐标系：以 bedroom_world_v1.png 左上角为 (0,0)，x 向右、y 向下，
/// 单位为原图像素（941 x 1672）。测量与审核依据见
/// docs/development/scene-geometry.md 及标注图
/// docs/development/images/scene-geometry-v1.2.png。
///
/// 本类只保存固定世界几何；视口、scale、offset 由 [SceneTransform] 另行保存，
/// 窗口/组件尺寸变化时不得修改本类顶点。
///
/// 注意：D（移动）与 E（交互）必须读取本类常量，禁止复制坐标数值。
class SceneGeometry {
  const SceneGeometry._();

  /// 世界（底图）尺寸。
  static const double worldWidth = 941;
  static const double worldHeight = 1672;

  /// 角色精灵 player_idle_down.png 原始尺寸：103 x 205（RGBA）。
  static const Size playerSpriteSize = Size(103, 205);

  /// 角色在世界中的渲染宽度（原图像素）。首版按 1:1 原尺寸渲染。
  static const double playerRenderWidth = 103;

  /// 角色渲染缩放：spriteScale = playerRenderWidth / 原图宽。
  static double get spriteScale => playerRenderWidth / playerSpriteSize.width;

  /// 角色渲染高度 = 原图高 x spriteScale。
  static double get playerRenderHeight => playerSpriteSize.height * spriteScale;

  /// 脚底锚点（精灵图内部坐标，自左上角量起）——**设计选择的参考点**：
  /// x 取双脚中心附近（51），y 取主要鞋底接地参考线（195）。
  /// 它不是"最低不透明行"：alpha>128 包围盒覆盖 x=8..94、y=8..196，
  /// 第 196 行仍有左脚不透明像素；首版允许少量脚尖低于参考线，
  /// 最终贴地效果以叠图确认为准。若后续改为 y=196，须同步更新
  /// 唯一配置、标注、文档与测试，并经组长确认。
  static const Offset playerFootAnchor = Offset(51, 195);

  /// 玩家初始脚底位置（世界坐标）。位于走廊中央空旷处，
  /// 在 [walkablePolygon] 内，且存在区域内路径抵达 [menuInteractionPoint]
  /// （v1.1 数学核查通过，见 docs/development/scene-geometry.md 第 8 节）。
  static const Offset playerStart = Offset(360, 1160);

  /// Convex floor envelope, extended up the aisle beside the bed to y=780.
  /// Furniture inside this envelope is excluded separately by canOccupy.
  /// The top edge stops below the cabinet; this is not permission to walk
  /// through the bed. Keep movement's padded footprint inside this envelope.
  static const List<Offset> walkablePolygon = <Offset>[
    Offset(300, 780),
    Offset(590, 780),
    Offset(550, 1060),
    Offset(550, 1385),
    Offset(75, 1385),
  ];

  /// Furniture obstacles in world space. Collisions use the ground footprint
  /// below, not the character's head: a person standing in front of the bed
  /// naturally draws over its footboard without occupying the bed's floor area.
  static const List<Rect> furnitureObstacles = <Rect>[
    Rect.fromLTRB(416, 570, 650, 952),
    Rect.fromLTRB(293, 650, 443, 765),
    Rect.fromLTRB(555, 960, 818, 1420),
  ];

  /// Ground occupancy relative to the foot, preserving horizontal body clearance
  /// at the desk without adding the full 195-pixel character height to the bed.
  static const Rect playerCollisionBounds = Rect.fromLTRB(-43, -14, 44, 8);

  /// Wider floor clearance keeps the sprite visibly off the walls and fence.
  /// All four corners must lie inside the existing convex floor polygon.
  static const Rect playerFloorClearance = Rect.fromLTRB(-58, -14, 58, 8);

  /// Full sprite rectangle relative to the foot anchor, including transparent
  /// padding. Rendering only; this is not the ground collision shape.
  static Rect get playerBodyBounds => Rect.fromLTWH(
    -playerFootAnchor.dx * spriteScale,
    -playerFootAnchor.dy * spriteScale,
    playerRenderWidth,
    playerRenderHeight,
  );

  /// Menu 交互点（世界坐标，门前地板上）。门体绿色门板范围约
  /// x 130..250、y 720..1225，门底中心约 (190,1180)；交互点取门前地板 (200,1170)。
  static const Offset menuInteractionPoint = Offset(200, 1170);

  /// Menu 交互半径（原图像素，有限正数）。约一格地砖宽度。
  /// E 的距离判定：欧氏距离 <= 70 可触发（核查点 (269/270/271,1170)
  /// 对应 可触发/可触发/不可触发）。
  static const double menuInteractionRadius = 70;

  /// 给定脚底世界坐标，返回精灵图绘制时的左上角**世界坐标**。
  /// spriteTopLeftWorld = footWorld - playerFootAnchor x spriteScale。
  /// 之后对角色与背景使用同一次场景变换（scale/offset），
  /// 不得对锚点重复缩放。
  static Offset spriteTopLeftWorld(Offset footWorld) {
    return footWorld - playerFootAnchor * spriteScale;
  }
}

/// 场景变换：world（原图像素）与 local（场景组件内部坐标，Flutter 逻辑像素）
/// 的互逆换算。
///
///   local = offset + world * scale
///   world = (local - offset) / scale
///
/// viewportWidth/viewportHeight 是卧室场景组件**实际获得的布局宽高**
/// （Flutter 逻辑像素）：若 SafeArea、导航栏或工具栏占用空间，
/// 使用扣除后组件的实际约束，不直接使用整屏尺寸。
///
/// 指针事件：若事件提供 globalPosition，先通过场景 RenderBox.globalToLocal
/// 转为 local；若已取得该场景的 localPosition，不得重复转换。
/// 显示偏移只扣一次；几何计算与交互距离始终使用 world 坐标。
/// 组件尺寸改变时重新计算 scale 与 offset（世界顶点不变）。
class SceneTransform {
  const SceneTransform._(
    this.scale,
    this.offset, [
    this.worldSize = const Size(
      SceneGeometry.worldWidth,
      SceneGeometry.worldHeight,
    ),
  ]);

  final Size worldSize;

  /// 以等比缩放居中方式适配组件视口。
  /// [viewportWidth]/[viewportHeight] 为组件实际可用布局宽高（逻辑像素）。
  /// 非正或非有限的视口尺寸不参与除法计算，直接抛出 [ArgumentError]。
  factory SceneTransform.fit(double viewportWidth, double viewportHeight) {
    if (!viewportWidth.isFinite ||
        !viewportHeight.isFinite ||
        viewportWidth <= 0 ||
        viewportHeight <= 0) {
      throw ArgumentError(
        'viewport size must be positive and finite: '
        '$viewportWidth x $viewportHeight',
      );
    }
    final double scaleX = viewportWidth / SceneGeometry.worldWidth;
    final double scaleY = viewportHeight / SceneGeometry.worldHeight;
    final double scale = scaleX < scaleY ? scaleX : scaleY;
    final double dx = (viewportWidth - SceneGeometry.worldWidth * scale) / 2;
    final double dy = (viewportHeight - SceneGeometry.worldHeight * scale) / 2;
    // scale 运行时保护（交付 v1.1，复审意见 2）：不用 assert（release 模式
    // 会被剥离），计算后以 if 检查——scale 必须有限且 > 0（极小正数视口
    // 可能使 scale 下溢为 0），偏移必须有限；不合法抛 ArgumentError。
    if (!scale.isFinite || scale <= 0) {
      throw ArgumentError(
        'computed scale must be finite and positive: $scale '
        '(viewport $viewportWidth x $viewportHeight)',
      );
    }
    if (!dx.isFinite || !dy.isFinite) {
      throw ArgumentError(
        'computed offset must be finite: ($dx, $dy) '
        '(viewport $viewportWidth x $viewportHeight)',
      );
    }
    return SceneTransform._(scale, Offset(dx, dy));
  }

  /// Fill the viewport without distortion. The camera follows the player and
  /// clamps to the world edges, so cropped doors can be approached normally.
  factory SceneTransform.cover(
    double width,
    double height, {
    required Size worldSize,
    required Offset focus,
  }) {
    if (![
          width,
          height,
          worldSize.width,
          worldSize.height,
        ].every((v) => v.isFinite && v > 0) ||
        !focus.dx.isFinite ||
        !focus.dy.isFinite) {
      throw ArgumentError(
        'finite positive viewport/world and finite focus required',
      );
    }
    final sx = width / worldSize.width;
    final sy = height / worldSize.height;
    final scale = sx > sy ? sx : sy;
    if (!scale.isFinite ||
        scale <= 0 ||
        !(worldSize.width * scale).isFinite ||
        !(worldSize.height * scale).isFinite) {
      throw ArgumentError('invalid camera scale');
    }
    final dx = (width * .5 - focus.dx * scale).clamp(
      (width - worldSize.width * scale).clamp(double.negativeInfinity, 0.0),
      0.0,
    );
    final dy = (height * .65 - focus.dy * scale).clamp(
      (height - worldSize.height * scale).clamp(double.negativeInfinity, 0.0),
      0.0,
    );
    return SceneTransform._(scale, Offset(dx, dy), worldSize);
  }

  /// 等比缩放系数（world 原图像素 -> local 逻辑像素）。
  final double scale;

  /// 居中偏移（local 逻辑像素）。
  final Offset offset;

  /// 场景在组件内的实际显示区域（local 逻辑像素）：
  /// `Rect.fromLTWH(offsetX, offsetY, worldWidth * scale, worldHeight * scale)`。
  ///
  /// 公共接口，供两类调用方使用：
  ///  - F（HUD/覆盖层）：以此为场景边界定位 HUD，不得自行推算缩放；
  ///  - 指针处理：判定点击是否落在场景内（见 [localToWorldChecked]）。
  ///
  /// 等比居中后，视口在场景两侧/上下可能留有空白（letterbox），
  /// 空白区域不属于 [sceneRect]。
  Rect get sceneRect => Rect.fromLTWH(
    offset.dx,
    offset.dy,
    worldSize.width * scale,
    worldSize.height * scale,
  );

  /// local 点是否落在 [sceneRect] 内。
  ///
  /// 边界语义与 dart:ui `Rect.contains` 一致：**左/上边包含、右/下边排除**
  /// （left <= x < left+width，top <= y < top+height）。
  /// 注意：这与 [SceneGeometry.walkablePolygon] 的多边形边界**刻意不同**——
  /// 多边形判定（WalkableArea.contains）边界包含，用于贴边滑行；
  /// 本方法用于指针命中场景区域，半开区间避免相邻区域重叠归属。
  bool containsLocal(Offset local) => sceneRect.contains(local);

  /// world -> local（场景组件内部坐标）。
  Offset worldToLocal(Offset world) => offset + world * scale;

  /// local -> world 的**纯数学换算**，不做范围判断。
  /// 调用方（如指针事件处理）必须先通过 [containsLocal] 或
  /// [localToWorldChecked] 确认点在场景内，再使用换算结果。
  Offset localToWorld(Offset local) => (local - offset) / scale;

  /// 安全指针转换：local 点落在 [sceneRect] 内时返回 world 坐标，
  /// 落在场景外（如宽窗口两侧空白）时返回 null —— **拒绝该次点击，不做 clamp**。
  ///
  /// 这是指针事件的推荐入口：globalPosition 先经 RenderBox.globalToLocal
  /// 转换一次，再调用本方法；返回 null 即忽略，不得改用具想象性的最近点。
  Offset? localToWorldChecked(Offset local) {
    return containsLocal(local) ? localToWorld(local) : null;
  }
}
