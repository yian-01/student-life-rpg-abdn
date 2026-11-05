import 'package:flutter/material.dart';

import '../../player/player_profile.dart';
import '../controllers/player_movement_controller.dart';

/// 玩家精灵：按 性别 × 朝向 × 行走帧 选择素材并渲染。
///
/// 素材位于 `assets/images/player/player_{gender}_{dir}_{frame}.png`：
///  - gender ∈ {male, female}（取自 [PlayerProfile.gender]）
///  - dir ∈ down/up/left/right（取自 [PlayerMovementController.facing]）
///  - frame ∈ idle/walk1/walk2（isMoving 时按 walkFrame 取 walk1/walk2）
///
/// 监听两个数据源：移动控制器（朝向/行走帧随每帧 update 变化）与
/// 性别档案（切换性别时重建）。两者任一变化都会刷新当前帧图片。
class PlayerSprite extends StatelessWidget {
  const PlayerSprite({super.key, required this.controller});

  final PlayerMovementController controller;

  static const Map<MoveDirection, String> _dirName = {
    MoveDirection.down: 'down',
    MoveDirection.up: 'up',
    MoveDirection.left: 'left',
    MoveDirection.right: 'right',
  };

  static String assetFor({
    required String gender,
    required MoveDirection facing,
    required bool isMoving,
    required int walkFrame,
  }) {
    final dir = _dirName[facing]!;
    final frame = isMoving ? 'walk${walkFrame + 1}' : 'idle';
    return 'assets/images/player/player_${gender}_${dir}_$frame.png';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, PlayerProfile.gender]),
      builder: (context, _) {
        return Image.asset(
          assetFor(
            gender: PlayerProfile.gender.value,
            facing: controller.facing,
            isMoving: controller.isMoving,
            walkFrame: controller.walkFrame,
          ),
          fit: BoxFit.fill,
          semanticLabel: '角色',
          errorBuilder: (_, _, _) => const Icon(Icons.person),
        );
      },
    );
  }
}
