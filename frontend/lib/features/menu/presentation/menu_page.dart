import 'package:flutter/material.dart';
import '../../bedroom/controllers/player_movement_controller.dart';
import '../../rooms/models/room_spec.dart';
import '../../rooms/presentation/room_scene_page.dart';

class MenuPage extends StatelessWidget {
  const MenuPage({super.key, this.movement});
  final PlayerMovementController? movement;
  @override
  Widget build(BuildContext context) =>
      RoomScenePage(room: RoomSpec.hall, movement: movement);
}
