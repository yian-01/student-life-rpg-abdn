import 'dart:ui';
import '../../bedroom/models/scene_geometry.dart';
import '../../bedroom/models/walkable_area.dart';
import '../../interaction/models/interaction_target.dart';

class RoomDoor {
  const RoomDoor(
    this.id,
    this.label,
    this.route,
    this.point,
    this.sign, {
    this.radius = 96,
  });
  final String id, label, route;
  final Offset point, sign;
  final double radius;
  InteractionTarget get target => InteractionTarget(
    id: id,
    label: label,
    routeName: route,
    worldPoint: point,
    radius: radius,
  );
}

class RoomSpec {
  const RoomSpec({
    required this.id,
    required this.name,
    required this.asset,
    required this.size,
    required this.start,
    required this.area,
    required this.doors,
  });
  final String id, name, asset;
  final Size size;
  final Offset start;
  final WalkableArea area;
  final List<RoomDoor> doors;

  static final bedroom = RoomSpec(
    id: 'bedroom',
    name: '我的卧室',
    asset: 'assets/images/bedroom_world_v1.png',
    size: const Size(SceneGeometry.worldWidth, SceneGeometry.worldHeight),
    start: SceneGeometry.playerStart,
    area: const WalkableArea(
      SceneGeometry.walkablePolygon,
      bodyBounds: SceneGeometry.playerCollisionBounds,
      floorBounds: SceneGeometry.playerFloorClearance,
      obstacles: SceneGeometry.furnitureObstacles,
    ),
    doors: const [
      RoomDoor(
        'menu',
        '校园大厅',
        '/menu',
        SceneGeometry.menuInteractionPoint,
        Offset(190, 850),
        radius: SceneGeometry.menuInteractionRadius,
      ),
    ],
  );

  static const hallFloor = [
    Offset(230, 430),
    Offset(910, 430),
    Offset(1130, 1350),
    Offset(10, 1350),
  ];
  static const hallArea = WalkableArea(
    hallFloor,
    bodyBounds: SceneGeometry.playerCollisionBounds,
    floorBounds: SceneGeometry.playerFloorClearance,
    obstacles: [
      // Plant, left console/plant and right bench/plant ground footprints.
      // The central rug is flat and remains walkable.
      Rect.fromLTRB(505, 340, 630, 470),
      Rect.fromLTRB(40, 720, 190, 980),
      Rect.fromLTRB(945, 720, 1105, 980),
    ],
  );
  static const hall = RoomSpec(
    id: 'hall',
    name: '校园大厅',
    asset: 'assets/images/campus_hall_v1.png',
    size: Size(1139, 1381),
    start: Offset(570, 1130),
    area: hallArea,
    doors: [
      RoomDoor(
        'schedule',
        '日程手账',
        '/schedule',
        Offset(375, 485),
        Offset(375, 235),
      ),
      RoomDoor('gpa', '学业档案', '/gpa', Offset(765, 485), Offset(765, 235)),
      RoomDoor(
        'finance',
        '生活账本',
        '/finance',
        Offset(245, 680),
        Offset(135, 540),
      ),
      RoomDoor(
        'dashboard',
        '生活总览',
        '/dashboard',
        Offset(895, 680),
        Offset(1005, 540),
      ),
    ],
  );
}
