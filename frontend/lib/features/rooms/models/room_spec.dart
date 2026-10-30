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
    Offset(201, 655),
    Offset(746, 655),
    Offset(930, 1435),
    Offset(18, 1435),
  ];
  static const hallArea = WalkableArea(
    hallFloor,
    bodyBounds: SceneGeometry.playerCollisionBounds,
    floorBounds: SceneGeometry.playerFloorClearance,
    obstacles: [
      Rect.fromLTRB(440, 550, 535, 670),
      Rect.fromLTRB(0, 1050, 110, 1290),
      Rect.fromLTRB(840, 1050, 948, 1290),
    ],
  );
  static const hall = RoomSpec(
    id: 'hall',
    name: '校园大厅',
    asset: 'assets/images/campus_hall_v1.png',
    size: Size(948, 1659),
    start: Offset(474, 1260),
    area: hallArea,
    doors: [
      RoomDoor(
        'schedule',
        '日程手账',
        '/schedule',
        Offset(320, 710),
        Offset(320, 350),
      ),
      RoomDoor('gpa', '学业档案', '/gpa', Offset(624, 710), Offset(624, 350)),
      RoomDoor(
        'finance',
        '生活账本',
        '/finance',
        Offset(175, 1085),
        Offset(200, 850),
      ),
      RoomDoor(
        'dashboard',
        '生活总览',
        '/dashboard',
        Offset(775, 1085),
        Offset(748, 850),
      ),
    ],
  );
}
