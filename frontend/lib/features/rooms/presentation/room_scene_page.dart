import 'dart:async';
import 'dart:ui' show ViewFocusEvent, ViewFocusState;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../../bedroom/controllers/player_movement_controller.dart';
import '../../bedroom/models/scene_geometry.dart';
import '../../bedroom/presentation/movement_joystick.dart';
import '../../interaction/controllers/interaction_controller.dart';
import '../models/room_spec.dart';

/// Shared input, camera and guarded door navigation for both rooms.
class RoomScenePage extends StatefulWidget {
  const RoomScenePage({super.key, required this.room, this.movement});
  final RoomSpec room;
  final PlayerMovementController? movement;
  @override
  State<RoomScenePage> createState() => RoomScenePageState();
}

class RoomScenePageState extends State<RoomScenePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _focus = FocusNode(debugLabel: 'room-input');
  final _keys = <LogicalKeyboardKey>{};
  late final PlayerMovementController _movement;
  late final List<InteractionController> _doors;
  late final Ticker _ticker;
  Duration? _lastTick;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    _movement =
        widget.movement ??
        PlayerMovementController(
          start: widget.room.start,
          area: widget.room.area,
        );
    _ticker = createTicker(_tick);
    _doors = [
      for (final door in widget.room.doors)
        InteractionController(
          movement: _movement,
          target: door.target,
          navigate: (route) async {
            _clearInput();
            await Navigator.of(context).pushNamed<void>(route);
            if (mounted && _foreground) _focus.requestFocus();
          },
        ),
    ];
    for (final door in _doors) {
      door.addListener(_changed);
    }
    WidgetsBinding.instance.addObserver(this);
  }

  PlayerMovementController get movement => _movement;

  bool get _acceptsInput =>
      mounted &&
      _foreground &&
      !_doors.any((d) => d.isNavigating) &&
      (ModalRoute.of(context)?.isCurrent ?? true);
  InteractionController? get _active {
    if (!_acceptsInput) return null;
    final nearby = _doors.where((d) => d.canInteract).toList()
      ..sort(
        (a, b) => (a.target.worldPoint - _movement.footPosition).distance
            .compareTo((b.target.worldPoint - _movement.footPosition).distance),
      );
    return nearby.isEmpty ? null : nearby.first;
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _syncTicker();
  }

  void _tick(Duration elapsed) {
    final previous = _lastTick;
    _lastTick = elapsed;
    if (!_acceptsInput || !_focus.hasFocus || !_movement.isMoving) {
      _clearInput();
      return;
    }
    if (previous != null) {
      _movement.update((elapsed - previous).inMicroseconds / 1000000);
    }
  }

  void _syncTicker() {
    if (_acceptsInput && _focus.hasFocus && _movement.isMoving) {
      if (!_ticker.isActive) {
        _lastTick = null;
        _ticker.start();
      }
    } else {
      _ticker.stop();
      _lastTick = null;
    }
  }

  void _clearInput() {
    _keys.clear();
    _movement.clearInput();
    _ticker.stop();
    _lastTick = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _clearInput();
    if (mounted) setState(() {});
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.state == ViewFocusState.unfocused) _clearInput();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_acceptsInput) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.keyE) {
      if (event is KeyDownEvent && _active != null) {
        unawaited(_active!.triggerInteraction());
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        event is KeyDownEvent &&
        Navigator.of(context).canPop()) {
      _clearInput();
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    final mapping = {
      LogicalKeyboardKey.keyW: MoveDirection.up,
      LogicalKeyboardKey.arrowUp: MoveDirection.up,
      LogicalKeyboardKey.keyS: MoveDirection.down,
      LogicalKeyboardKey.arrowDown: MoveDirection.down,
      LogicalKeyboardKey.keyA: MoveDirection.left,
      LogicalKeyboardKey.arrowLeft: MoveDirection.left,
      LogicalKeyboardKey.keyD: MoveDirection.right,
      LogicalKeyboardKey.arrowRight: MoveDirection.right,
    };
    if (!mapping.containsKey(event.logicalKey)) return KeyEventResult.ignored;
    if (event is KeyUpEvent) {
      _keys.remove(event.logicalKey);
    } else {
      _keys.add(event.logicalKey);
    }
    _movement.setPressedKeys({for (final key in _keys) mapping[key]!});
    _syncTicker();
    return KeyEventResult.handled;
  }

  void _onJoystick(Offset value) {
    if (!_acceptsInput) return;
    _keys.clear();
    _focus.requestFocus();
    _movement.setJoystickVector(value);
    _syncTicker();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clearInput();
    for (final door in _doors) {
      door.removeListener(_changed);
      door.dispose();
    }
    _ticker.dispose();
    _focus.dispose();
    if (widget.movement == null) _movement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final touch =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final active = _active;
    return Scaffold(
      backgroundColor: const Color(0xFF171612),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        onFocusChange: (focused) {
          if (!focused) {
            _clearInput();
          } else {
            _syncTicker();
          }
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
              return const SizedBox.shrink();
            }
            final transform = SceneTransform.cover(
              constraints.maxWidth,
              constraints.maxHeight,
              worldSize: room.size,
              focus: _movement.footPosition,
            );
            final sprite = transform.worldToLocal(
              SceneGeometry.spriteTopLeftWorld(_movement.footPosition),
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  key: const Key('scene-viewport'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (event) {
                    if (!_acceptsInput) return;
                    _focus.requestFocus();
                    if (active != null) {
                      unawaited(
                        active.triggerAtLocalPosition(
                          localPosition: event.localPosition,
                          transform: transform,
                        ),
                      );
                    }
                  },
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned.fromRect(
                          rect: transform.sceneRect,
                          child: Image.asset(
                            room.asset,
                            key: Key('${room.id}-background'),
                            fit: BoxFit.fill,
                            semanticLabel: room.name,
                          ),
                        ),
                        Positioned(
                          left: sprite.dx,
                          top: sprite.dy,
                          width:
                              SceneGeometry.playerRenderWidth * transform.scale,
                          height:
                              SceneGeometry.playerRenderHeight *
                              transform.scale,
                          child: IgnorePointer(
                            child: Image.asset(
                              'assets/images/player_idle_down.png',
                              key: Key('${room.id}-player'),
                              fit: BoxFit.fill,
                              semanticLabel: '角色',
                            ),
                          ),
                        ),
                        for (var i = 0; i < room.doors.length; i++)
                          _sign(room.doors[i], _doors[i], transform),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  child: Stack(
                    children: [
                      Positioned(
                        left: 12,
                        top: 12,
                        child: _RoomBadge(
                          name: room.name,
                          canGoBack: Navigator.of(context).canPop(),
                          onBack: () {
                            _clearInput();
                            Navigator.of(context).pop();
                          },
                        ),
                      ),
                      if (touch)
                        Positioned(
                          left: 16,
                          bottom: 16,
                          child: MovementJoystick(
                            enabled: _acceptsInput,
                            onChanged: _onJoystick,
                          ),
                        ),
                      if (active != null)
                        Positioned(
                          right: 16,
                          bottom: 24,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth * .46,
                            ),
                            child: FilledButton.icon(
                              key: Key('${active.target.id}-interaction'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF34291E),
                                foregroundColor: const Color(0xFFFFE6A6),
                                side: const BorderSide(
                                  color: Color(0xFFBC9658),
                                  width: 2,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                              ),
                              onPressed: active.triggerInteraction,
                              icon: Icon(
                                touch
                                    ? Icons.touch_app_outlined
                                    : Icons.keyboard,
                                size: 18,
                              ),
                              label: Text(
                                '${touch ? '' : 'E · '}进入${active.target.label}',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      if (_doors.any((d) => d.error != null))
                        const Positioned(
                          left: 16,
                          right: 16,
                          bottom: 100,
                          child: _RoomBadge(
                            name: '门暂时无法打开，请重试',
                            canGoBack: false,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sign(
    RoomDoor door,
    InteractionController controller,
    SceneTransform transform,
  ) {
    final position = transform.worldToLocal(door.sign);
    final width = 190 * transform.scale;
    return Positioned(
      left: position.dx - width / 2,
      top: position.dy - 20 * transform.scale,
      width: width,
      child: Semantics(
        label: '${door.label}门，靠近后交互',
        button: true,
        child: GestureDetector(
          key: Key('door-${door.id}'),
          onTap: () {
            if (_acceptsInput) unawaited(controller.triggerInteraction());
          },
          child: Container(
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(
              horizontal: 6 * transform.scale,
              vertical: 5 * transform.scale,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF33261C).withValues(alpha: .94),
              border: Border.all(
                color: controller.canInteract
                    ? const Color(0xFFFFDA77)
                    : const Color(0xFFAB8247),
                width: controller.canInteract ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              door.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFFFFE5AC),
                fontSize: 26 * transform.scale,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomBadge extends StatelessWidget {
  const _RoomBadge({required this.name, required this.canGoBack, this.onBack});
  final String name;
  final bool canGoBack;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(
      maxWidth: MediaQuery.sizeOf(context).width - 24,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFF241F19).withValues(alpha: .85),
      border: Border.all(color: const Color(0xFFB18A50)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canGoBack)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: BackButton(
              color: const Color(0xFFFFE5AC),
              onPressed: onBack,
            ),
          ),
        Flexible(
          child: Text(
            name,
            style: const TextStyle(
              color: Color(0xFFFFE5AC),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
