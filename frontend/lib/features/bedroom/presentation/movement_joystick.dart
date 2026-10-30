import 'package:flutter/material.dart';

/// Fixed UI joystick. Input is normalized by the shared movement controller.
class MovementJoystick extends StatefulWidget {
  const MovementJoystick({
    super.key,
    required this.onChanged,
    this.enabled = true,
  });

  final ValueChanged<Offset> onChanged;
  final bool enabled;

  @override
  State<MovementJoystick> createState() => _MovementJoystickState();
}

class _MovementJoystickState extends State<MovementJoystick> {
  static const double _size = 88;
  static const double _radius = 28;
  Offset _thumb = Offset.zero;

  @override
  void didUpdateWidget(MovementJoystick oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _thumb = Offset.zero;
  }

  void _change(Offset local) {
    if (!widget.enabled) return;
    final raw = (local - const Offset(_size / 2, _size / 2)) / _radius;
    final value = raw.distance > 1 ? raw / raw.distance : raw;
    setState(() => _thumb = value * _radius);
    widget.onChanged(value);
  }

  void _stop() {
    setState(() => _thumb = Offset.zero);
    widget.onChanged(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: '移动摇杆',
      enabled: widget.enabled,
      child: GestureDetector(
        key: const Key('movement-joystick'),
        behavior: HitTestBehavior.opaque,
        onPanDown: widget.enabled
            ? (event) => _change(event.localPosition)
            : null,
        onPanStart: widget.enabled
            ? (event) => _change(event.localPosition)
            : null,
        onPanUpdate: widget.enabled
            ? (event) => _change(event.localPosition)
            : null,
        onPanEnd: widget.enabled ? (_) => _stop() : null,
        onPanCancel: widget.enabled ? _stop : null,
        onTapUp: widget.enabled ? (_) => _stop() : null,
        child: SizedBox.square(
          dimension: _size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.surfaceContainerHighest,
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Center(
              child: Transform.translate(
                offset: _thumb,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.enabled ? colors.primary : colors.outline,
                  ),
                  child: const SizedBox.square(dimension: 32),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
