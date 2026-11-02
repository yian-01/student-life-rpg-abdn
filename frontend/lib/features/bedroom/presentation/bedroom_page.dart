import 'package:flutter/material.dart';
import '../controllers/player_movement_controller.dart';
import '../../rooms/models/room_spec.dart';
import '../../rooms/presentation/room_scene_page.dart';

class BedroomPage extends StatelessWidget {
  const BedroomPage({super.key, this.movement});
  final PlayerMovementController? movement;
  @override
  Widget build(BuildContext context) =>
      RoomScenePage(room: RoomSpec.bedroom, movement: movement);
}
