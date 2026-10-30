import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../app/app_routes.dart';
import '../../hud/models/hud_view_data.dart';
import '../../interaction/controllers/interaction_controller.dart';
import '../../interaction/models/interaction_target.dart';
import '../controllers/player_movement_controller.dart';
import '../models/scene_geometry.dart';
import 'movement_joystick.dart';
import 'scene_viewport.dart';

class BedroomPage extends StatefulWidget {
  const BedroomPage({super.key, this.movement});

  /// Optional externally owned controller for composition and integration tests.
  final PlayerMovementController? movement;

  @override
  State<BedroomPage> createState() => _BedroomPageState();
}

class _BedroomPageState extends State<BedroomPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _focus = FocusNode(debugLabel: 'bedroom-input');
  final _keys = <LogicalKeyboardKey>{};
  late final PlayerMovementController _movement;
  late final InteractionController _interaction;
  late final Ticker _ticker;
  Duration? _lastTick;
  bool _foreground = true;

  // This is explicitly demo HUD input, not an implemented reward chain.
  final _hud = HudViewData(
    displayName: 'CS Group6 · 演示数据',
    level: 1,
    exp: 0,
    expToNextLevel: 100,
  );

  @override
  void initState() {
    super.initState();
    _movement = widget.movement ?? PlayerMovementController();
    _ticker = createTicker(_tick);
    _interaction = InteractionController(
      movement: _movement,
      target: InteractionTarget(
        id: 'menu',
        label: '进入菜单',
        routeName: AppRoutes.menu,
        worldPoint: SceneGeometry.menuInteractionPoint,
        radius: SceneGeometry.menuInteractionRadius,
      ),
      navigate: (route) async {
        _clearInput();
        await Navigator.of(context).pushNamed<void>(route);
        if (mounted && _foreground) _focus.requestFocus();
      },
    );
    _interaction.addListener(_syncTicker);
    WidgetsBinding.instance.addObserver(this);
  }

  bool get _acceptsInput =>
      mounted &&
      _foreground &&
      !_interaction.isNavigating &&
      (ModalRoute.of(context)?.isCurrent ?? true);

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

  // Desktop focus loss can happen without changing AppLifecycleState.
  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.state == ViewFocusState.unfocused) _clearInput();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_acceptsInput) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.keyE) {
      if (event is KeyDownEvent) {
        unawaited(_interaction.triggerInteraction());
      }
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
    _ticker.dispose();
    _interaction.removeListener(_syncTicker);
    _interaction.dispose();
    _focus.dispose();
    if (widget.movement == null) _movement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Student Life RPG')),
      body: SafeArea(
        child: Focus(
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
          child: ListenableBuilder(
            listenable: _interaction,
            builder: (context, _) => LayoutBuilder(
              builder: (context, constraints) => Column(
                children: [
                  Expanded(
                    child: SceneViewport(
                      footPosition: _movement.footPosition,
                      hud: _hud,
                      onSceneTap: (local, transform) {
                        if (!_acceptsInput) return;
                        _focus.requestFocus();
                        unawaited(
                          _interaction.triggerAtLocalPosition(
                            localPosition: local,
                            transform: transform,
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    height: math.min(144, constraints.maxHeight * 0.4),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          MovementJoystick(
                            enabled: _acceptsInput,
                            onChanged: _onJoystick,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'WASD / 方向键，或拖动摇杆移动',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (_interaction.canInteract)
                                  FilledButton(
                                    key: const Key('menu-interaction'),
                                    onPressed: _interaction.triggerInteraction,
                                    child: const Text('进入菜单'),
                                  )
                                else
                                  const Text('靠近左侧 Menu 门后按 E 或点击进入'),
                                if (_interaction.error != null)
                                  const Text('导航失败，请靠近门后重试'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
