import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Shared material, interaction and motion primitives for the platform.
/// Decorative layers never intercept input or expose meaningless semantics.
class AtmosphereBackdrop extends StatelessWidget {
  const AtmosphereBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const Positioned.fill(
        child: IgnorePointer(child: RepaintBoundary(
          child: CustomPaint(painter: _AtmospherePainter()),
        )),
      ),
      child,
    ],
  );
}

class _AtmospherePainter extends CustomPainter {
  const _AtmospherePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(AppTheme.background, BlendMode.src);
    void glow(Offset point, double radius, Color color) {
      canvas.drawCircle(point, radius, Paint()..shader = RadialGradient(
        colors: [color, color.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: point, radius: radius)));
    }
    glow(Offset(size.width * .9, size.height * .05), size.width * .85,
        const Color(0x162DDBB1));
    glow(Offset(0, size.height * .65), size.width * .75,
        const Color(0x162C56AD));
    final grid = Paint()..color = const Color(0x067FA4B4)..strokeWidth = .6;
    for (double x = 0; x < size.width; x += 44) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 44) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final noise = Paint()..color = const Color(0x0AFFFFFF);
    final random = math.Random(27);
    for (var i = 0; i < 600; i++) {
      canvas.drawCircle(Offset(random.nextDouble() * size.width,
          random.nextDouble() * size.height), .45, noise);
    }
  }

  @override
  bool shouldRepaint(_AtmospherePainter oldDelegate) => false;
}

/// Finite entrance motion also acts as scroll reveal for lazily built children.
class SurfaceReveal extends StatelessWidget {
  const SurfaceReveal({super.key, required this.child, this.order = 0});
  final Widget child;
  final int order;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero : Duration(milliseconds: 380 + (order % 5) * 65),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (context, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(offset: Offset(0, 14 * (1 - value)), child: child),
    ),
  );
}

/// Glass surface with visible hover/focus and press feedback on touch devices.
class GlassSurface extends StatefulWidget {
  const GlassSurface({super.key, required this.child,
    this.padding = const EdgeInsets.all(18), this.onTap,
    this.radius = 22, this.tint, this.blur = false});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final Color? tint;
  final bool blur;

  @override
  State<GlassSurface> createState() => _GlassSurfaceState();
}

class _GlassSurfaceState extends State<GlassSurface> {
  bool _hover = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = _hover || _focused || _pressed;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final surface = ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Material(
        color: widget.tint ?? AppTheme.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(widget.radius),
          side: BorderSide(color: active
              ? AppTheme.accent.withValues(alpha: .55) : AppTheme.line),
        ),
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (value) => setState(() => _focused = value),
          borderRadius: BorderRadius.circular(widget.radius),
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() { _hover = false; _pressed = false; }),
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: reduced ? Duration.zero : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          transformAlignment: Alignment.center,
          transform: Matrix4.identity()
            ..translateByDouble(0, reduced ? 0 : active ? -2 : 0, 0, 1)
            ..scaleByDouble(_pressed && !reduced ? .985 : 1,
                _pressed && !reduced ? .985 : 1, 1, 1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: [BoxShadow(
              color: active ? AppTheme.accent.withValues(alpha: .08)
                  : const Color(0x24000000),
              blurRadius: active ? 24 : 16, offset: const Offset(0, 8),
            )],
          ),
          child: widget.blur ? ClipRRect(
            borderRadius: BorderRadius.circular(widget.radius),
            child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                child: surface),
          ) : surface,
        ),
      ),
    );
  }
}

/// A projected 3D latitude sphere, orbital rings and a deterministic star field.
/// The introduction stops after 1.2s; pointer parallax needs no idle ticker.
class OrbitalScene extends StatefulWidget {
  const OrbitalScene({super.key});
  @override
  State<OrbitalScene> createState() => _OrbitalSceneState();
}

class _OrbitalSceneState extends State<OrbitalScene> {
  Offset _pointer = Offset.zero;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: LayoutBuilder(builder: (context, constraints) => MouseRegion(
      onHover: (event) {
        if (MediaQuery.disableAnimationsOf(context)) return;
        setState(() => _pointer = Offset(
          event.localPosition.dx / constraints.maxWidth - .5,
          event.localPosition.dy / constraints.maxHeight - .5,
        ));
      },
      onExit: (_) => setState(() => _pointer = Offset.zero),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero : const Duration(milliseconds: 1200),
        curve: Curves.easeOutCubic,
        builder: (_, progress, _) => RepaintBoundary(child: CustomPaint(
          size: Size.infinite,
          painter: _OrbitPainter(progress: progress, pointer: _pointer),
        )),
      ),
    )),
  );
}

class _OrbitPainter extends CustomPainter {
  const _OrbitPainter({required this.progress, required this.pointer});
  final double progress;
  final Offset pointer;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .55 + pointer.dx * 14,
        size.height * .5 + pointer.dy * 10);
    final r = math.min(size.width, size.height) * .29;
    canvas.drawCircle(center, r * 2, Paint()..shader = const RadialGradient(
      colors: [Color(0x322BCAB1), Color(0x052BCAB1), Colors.transparent],
    ).createShader(Rect.fromCircle(center: center, radius: r * 2)));
    final rotation = .5 + progress * .6 + pointer.dx * .4;
    Offset project(double x, double y, double z) {
      final xr = x * math.cos(rotation) + z * math.sin(rotation);
      final zr = -x * math.sin(rotation) + z * math.cos(rotation);
      final scale = 3 / (3 - zr * .45);
      return center + Offset(xr * r * scale, (y + zr * .2) * r * scale);
    }
    final mesh = Paint()..style = PaintingStyle.stroke..strokeWidth = .7
      ..color = const Color(0x4475D8C3);
    for (var latitude = -2; latitude <= 2; latitude++) {
      final y = latitude / 3;
      final radius = math.sqrt(1 - y * y);
      final path = Path();
      for (var i = 0; i <= 72; i++) {
        final angle = i * math.pi / 36;
        final p = project(math.cos(angle) * radius, y, math.sin(angle) * radius);
        if (i == 0) { path.moveTo(p.dx, p.dy); } else { path.lineTo(p.dx, p.dy); }
      }
      canvas.drawPath(path, mesh);
    }
    for (var meridian = 0; meridian < 7; meridian++) {
      final longitude = meridian * math.pi / 7;
      final path = Path();
      for (var i = 0; i <= 72; i++) {
        final a = i * math.pi / 36;
        final p = project(math.cos(a) * math.cos(longitude),
            math.sin(a), math.cos(a) * math.sin(longitude));
        if (i == 0) { path.moveTo(p.dx, p.dy); } else { path.lineTo(p.dx, p.dy); }
      }
      canvas.drawPath(path, mesh);
    }
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-.36);
    final ring = Rect.fromCenter(center: Offset.zero, width: r * 3.1, height: r * .82);
    canvas.drawOval(ring, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2
      ..color = AppTheme.accent.withValues(alpha: .7));
    canvas.drawOval(ring.inflate(7), mesh);
    canvas.restore();
    final random = math.Random(46);
    for (var i = 0; i < 34; i++) {
      final p = Offset(random.nextDouble() * size.width,
          random.nextDouble() * size.height);
      canvas.drawCircle(p, i % 6 == 0 ? 1.8 : .7, Paint()..color =
          (i % 6 == 0 ? AppTheme.accent : const Color(0xFF83B5BD))
              .withValues(alpha: i % 6 == 0 ? .8 : .35));
    }
    final satellite = project(math.cos(rotation * 2) * 1.4, -.32,
        math.sin(rotation * 2) * 1.4);
    canvas.drawCircle(satellite, 4, Paint()..color = AppTheme.accent);
    canvas.drawCircle(satellite, 9, Paint()..color = AppTheme.accent.withValues(alpha: .12));
  }

  @override
  bool shouldRepaint(_OrbitPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.pointer != pointer;
}
