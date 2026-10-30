import 'package:flutter/material.dart';

import '../../hud/models/hud_view_data.dart';
import '../../hud/presentation/player_status_hud_overlay.dart';
import '../models/scene_geometry.dart';

/// One local coordinate container for the world, pointer conversion and HUD.
class SceneViewport extends StatelessWidget {
  const SceneViewport({
    super.key,
    required this.footPosition,
    required this.hud,
    required this.onSceneTap,
  });

  final Offset footPosition;
  final HudViewData hud;
  final void Function(Offset local, SceneTransform transform) onSceneTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final SceneTransform transform;
        try {
          transform = SceneTransform.fit(
            constraints.maxWidth,
            constraints.maxHeight,
          );
        } on ArgumentError {
          return const SizedBox.shrink();
        }
        final rect = transform.sceneRect;
        final sprite = transform.worldToLocal(
          SceneGeometry.spriteTopLeftWorld(footPosition),
        );
        return GestureDetector(
          key: const Key('scene-viewport'),
          behavior: HitTestBehavior.opaque,
          onTapUp: (event) => onSceneTap(event.localPosition, transform),
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: const Color(0xFF181F20)),
                Positioned.fromRect(
                  rect: rect,
                  child: Image.asset(
                    'assets/images/bedroom_world_v1.png',
                    key: const Key('bedroom-background'),
                    fit: BoxFit.fill,
                    semanticLabel: '卧室与左侧 Menu 门',
                    errorBuilder: (_, _, _) =>
                        const Center(child: Text('卧室素材加载失败，请重新启动应用')),
                  ),
                ),
                Positioned(
                  left: sprite.dx,
                  top: sprite.dy,
                  width: SceneGeometry.playerRenderWidth * transform.scale,
                  height: SceneGeometry.playerRenderHeight * transform.scale,
                  child: IgnorePointer(
                    child: Image.asset(
                      'assets/images/player_idle_down.png',
                      key: const Key('bedroom-player'),
                      fit: BoxFit.fill,
                      semanticLabel: '角色',
                      errorBuilder: (_, _, _) => const Icon(Icons.person),
                    ),
                  ),
                ),
                PlayerStatusHudOverlay(
                  data: hud,
                  sceneRect: rect,
                  maxHeight: rect.height * 0.3,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
