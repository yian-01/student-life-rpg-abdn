import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../../bedroom/controllers/player_movement_controller.dart';
import '../../bedroom/models/scene_geometry.dart';
import '../models/interaction_target.dart';

/// Completes when the pushed route is popped, not when it is first displayed.
typedef NavigateToRoute = Future<void> Function(String routeName);

class InteractionController extends ChangeNotifier {
  InteractionController({
    required this.movement,
    required this.target,
    required this.navigate,
  }) {
    movement.addListener(_onMovementChanged);
  }

  final PlayerMovementController movement;
  final InteractionTarget target;
  final NavigateToRoute navigate;
  bool _isNavigating = false;
  bool _disposed = false;
  Object? _error;

  bool get canInteract =>
      !_disposed &&
      !_isNavigating &&
      target.containsWorldPoint(movement.footPosition);
  bool get isNavigating => _isNavigating;
  Object? get error => _error;

  void _onMovementChanged() {
    if (!_disposed) notifyListeners();
  }

  /// Optional scene-pointer adapter. Supply SceneViewport-local coordinates;
  /// globalToLocal belongs to the page and must happen at most once.
  Future<void> triggerAtLocalPosition({
    required Offset localPosition,
    required SceneTransform transform,
  }) async {
    if (_disposed) return;
    final worldPoint = transform.localToWorldChecked(localPosition);
    if (worldPoint == null || !target.containsWorldPoint(worldPoint)) return;
    await triggerInteraction();
  }

  /// Keyboard, mouse and touch adapters must all call this guarded entry.
  Future<void> triggerInteraction() async {
    if (!canInteract) return;
    _isNavigating = true;
    _error = null;
    try {
      movement.pause();
      movement.clearInput();
      notifyListeners();
      if (_disposed) return;
      await navigate(target.routeName);
    } catch (error) {
      if (!_disposed) _error = error;
    } finally {
      if (!_disposed) {
        movement.clearInput();
        movement.resume();
        _isNavigating = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    movement.removeListener(_onMovementChanged);
    // Detach while movement is still live. A covered/disposed scene must not
    // start moving again. Its owner decides whether to reuse and resume it;
    // a pending route Future must never touch movement after this point.
    if (_isNavigating) {
      movement.clearInput();
      _isNavigating = false;
    }
    super.dispose();
  }
}
