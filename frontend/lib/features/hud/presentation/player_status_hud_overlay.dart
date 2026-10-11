import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/hud_view_data.dart';
import 'player_status_hud.dart';

/// Place directly in the unscaled SceneViewport Stack, beside the world layer.
/// [sceneRect] is C's local rectangle, recomputed by the caller after resize.
class PlayerStatusHudOverlay extends StatelessWidget {
  const PlayerStatusHudOverlay({
    super.key,
    required this.data,
    required this.sceneRect,
  });

  static const double margin = 12;
  final HudViewData data;
  final Rect sceneRect;

  @override
  Widget build(BuildContext context) {
    final width = sceneRect.width - 2 * margin;
    final height = sceneRect.height - 2 * margin;
    if (!sceneRect.isFinite || width <= 0 || height <= 0) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: sceneRect.left + margin,
      top: sceneRect.top + margin,
      width: math.min(width, 280),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height),
        child: SingleChildScrollView(child: PlayerStatusHud(data: data)),
      ),
    );
  }
}
