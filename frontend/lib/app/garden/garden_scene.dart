import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'garden_settings.dart';
import 'garden_audio.dart';
import 'pixel_leaves.dart';

class _Layer {
  _Layer(this.image, this.factor, this.lag, this.detach);
  final ui.Image image;
  final double factor, lag;
  final bool detach;
}

class _Art {
  _Art(this.width, this.height, this.base, this.layers, this.bones, this.hits);
  final double width, height, base;
  final List<_Layer> layers;
  final List<double> bones;
  final List<List<int>> hits;
}

class GardenArtwork {
  static Future<Map<String, _Art>>? _cache;
  static Future<void> load() async {
    await _cached();
  }

  static Future<Map<String, _Art>> _cached() => _cache ??= _load();
  static Future<Map<String, _Art>> _load() async {
    final json =
        jsonDecode(await rootBundle.loadString('assets/garden/plants.json'))
            as Map<String, dynamic>;
    final result = <String, _Art>{};
    for (final entry in json.entries) {
      final data = entry.value as Map<String, dynamic>;
      final layers = <_Layer>[];
      for (final raw in data['sheets'] as List) {
        final codec = await ui.instantiateImageCodec(
          base64Decode(raw['src'] as String),
        );
        final frame = await codec.getNextFrame();
        layers.add(
          _Layer(
            frame.image,
            (raw['factor'] as num).toDouble(),
            (raw['lag'] as num).toDouble(),
            raw['detach'] as bool,
          ),
        );
        codec.dispose();
      }
      result[entry.key] = _Art(
        (data['width'] as num).toDouble(),
        (data['height'] as num).toDouble(),
        (data['bendBase'] as num).toDouble(),
        layers,
        (data['bones'] as List).map((v) => (v as num).toDouble()).toList(),
        (data['hit'] as List).map((v) => (v as List).cast<int>()).toList(),
      );
    }
    await PixelLeaves.load();
    return result;
  }
}

class _Pose {
  _Pose(this.name, this.art);
  final String name;
  final _Art art;
  Offset origin = Offset.zero;
  double scale = 1, force = 0, velocity = 0, grabY = 100, growth = 1;
  final holes = <(int, Rect)>[];
}

class _Leaf {
  _Leaf(this.name, this.position, this.velocity, this.phase, this.scale);
  final String name;
  Offset position, velocity;
  final double phase, scale;
  double age = 0;
}

/// Flutter-native art and physics. No embedded HTML, sample records or web view.
class GardenScene extends StatefulWidget {
  const GardenScene({super.key, required this.settings, required this.plant});
  final GardenSettings settings;
  final String plant;
  @override
  State<GardenScene> createState() => _GardenSceneState();
}

class _GardenSceneState extends State<GardenScene>
    with SingleTickerProviderStateMixin {
  final _paint = ValueNotifier<int>(0), _random = math.Random();
  final _memory = <String, _Pose>{};
  final _leaves = <_Leaf>[];
  Map<String, _Art>? _art;
  Object? _error;
  late final Ticker _ticker;
  Duration _previous = Duration.zero;
  Size _size = Size.zero;
  List<_Pose> _poses = [];
  _Pose? _grab;
  bool _reduced = false, _hover = false;
  double _time = 0, _nextDrop = .35, _nextSound = 0;
  @visibleForTesting
  int get debugLeafCount => _leaves.length;
  int _regrowth = 0;
  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _load();
  }

  Future<void> _load() async {
    try {
      final art = await GardenArtwork._cached();
      if (mounted) setState(() => _art = art);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    final animate = !_reduced && TickerMode.valuesOf(context).enabled;
    if (animate && !_ticker.isActive) {
      _previous = Duration.zero;
      _ticker.start();
    }
    if (!animate && _ticker.isActive) _ticker.stop();
  }

  List<String> get _names => widget.settings.view == 'all'
      ? ['cherry', 'bush', 'maple']
      : widget.settings.view == 'single'
      ? [
          const [
            'cherry',
            'bush',
            'maple',
            'ginkgo',
            'bamboo',
          ][widget.settings.plant],
        ]
      : [widget.plant];
  void _arrange(Size size) {
    final art = _art;
    if (art == null) return;
    _size = size;
    final names = _names,
        total =
            names.fold<double>(0, (s, n) => s + art[n]!.width) +
            18 * (names.length - 1);
    final scale = math.max(
      .05,
      math.min(
        (size.width - 18) / total,
        math.min((size.height - 25) / 235, 2.05),
      ),
    );
    var x = (size.width - total * scale) / 2;
    _poses = [
      for (final name in names)
        _memory.putIfAbsent(name, () => _Pose(name, art[name]!)),
    ];
    for (final p in _poses) {
      p.scale = scale;
      p.origin = Offset(x, size.height - 23 - p.art.base * scale);
      x += (p.art.width + 18) * scale;
    }
    if (_regrowth != widget.settings.regrowth) {
      _regrowth = widget.settings.regrowth;
      _leaves.clear();
      for (final p in _poses) {
        p.holes.clear();
        p.growth = _reduced ? 1 : 0;
      }
    }
  }

  double _wind(double time) {
    final s = widget.settings;
    return _reduced || !s.weather
        ? 0
        : s.direction *
              s.strength *
              (.65 +
                  s.gusts *
                      (math.sin(time * 1.1) * .22 +
                          math.sin(time * 2.7 + 1) * .13 +
                          .35));
  }

  double _offset(_Pose p, _Layer layer, double y) {
    if (_reduced || layer.factor == 0) return 0;
    final flex = ((p.art.base - y) / (p.art.base - 8)).clamp(0.0, 1.0),
        t = _time - layer.lag * 7;
    final breath = math.sin(t * .82) * 1.3 + math.sin(t * 1.57 + .8) * .4;
    final wind = _wind(t) * (14 + math.sin(t * .95) * 4);
    final local = _grab == p ? math.exp(-(y - p.grabY).abs() / 95) : 1.0;
    return (p.force * local + wind + breath) *
        widget.settings.sway *
        layer.factor *
        flex *
        flex;
  }

  void _tick(Duration elapsed) {
    if (elapsed - _previous < const Duration(milliseconds: 32)) return;
    final dt = ((elapsed - _previous).inMicroseconds / 1000000).clamp(0.0, .05);
    _previous = elapsed;
    _time += dt;
    for (final p in _poses) {
      if (_grab != p) {
        p.velocity += (-p.force * 28 - p.velocity * 3.6) * dt;
        p.force += p.velocity * dt;
      }
      p.growth = math.min(1, p.growth + dt / .7);
    }
    final wind = _wind(_time);
    for (final leaf in _leaves) {
      leaf.age += dt;
      leaf.velocity = Offset(
        leaf.velocity.dx +
            (wind * 37 +
                    math.sin(_time * 1.4 + leaf.phase) * 15 -
                    leaf.velocity.dx) *
                .9 *
                dt,
        leaf.velocity.dy + (28 - leaf.velocity.dy) * 1.15 * dt,
      );
      leaf.position +=
          Offset(
            leaf.velocity.dx,
            leaf.velocity.dy + math.cos(_time * 2 + leaf.phase) * 5,
          ) *
          dt;
    }
    _leaves.removeWhere((l) => l.age > 11 || l.position.dy > _size.height);
    if (_time > _nextDrop) {
      final storm = widget.settings.weather && widget.settings.strength > .55;
      for (final p in _poses) {
        _drop(p, storm ? 2 : 1, detach: false);
      }
      _nextDrop = _time + (storm ? .45 : 1.1) + _random.nextDouble() * .45;
    }
    if (_time > _nextSound) {
      GardenAudio.wind(wind);
      _nextSound = _time + .2;
    }
    _paint.value++;
  }

  _Pose? _hit(Offset position) {
    for (final p in _poses) {
      final local = (position - p.origin) / p.scale;
      for (final row in p.art.hits) {
        if (local.dy.floor() == row[0] &&
            local.dx >= row[1] &&
            local.dx <= row[2]) {
          return p;
        }
      }
    }
    return null;
  }

  void _drop(_Pose p, int count, {bool detach = true}) {
    if (_reduced) return;
    final layers = [
      for (var i = 0; i < p.art.layers.length; i++)
        if (p.art.layers[i].detach) i,
    ];
    final canopy = p.art.hits.where((hit) => hit[0] < p.art.base * .8).toList();
    if (layers.isEmpty || canopy.isEmpty) return;
    for (var i = 0; i < count; i++) {
      final hit = canopy[_random.nextInt(canopy.length)];
      final x = hit[1] + _random.nextDouble() * (hit[2] - hit[1] + 1),
          y = hit[0].toDouble(),
          layer = layers[_random.nextInt(layers.length)];
      if (detach) {
        if (p.holes.length >= 180) p.holes.removeAt(0);
        p.holes.add((layer, Rect.fromLTWH(x - 2, y - 2, 5, 5)));
      }
      _leaves.add(
        _Leaf(
          p.name,
          p.origin +
              Offset(x + _offset(p, p.art.layers[layer], y), y) * p.scale,
          Offset(
            (_random.nextDouble() - .5) * 18,
            -12 - _random.nextDouble() * 12,
          ),
          _random.nextDouble() * 6,
          p.scale.clamp(.6, 1.3) * (.8 + _random.nextDouble() * .35),
        ),
      );
    }
    if (_leaves.length > 180) _leaves.removeRange(0, _leaves.length - 180);
  }

  void _shake(_Pose? pose) {
    if (pose == null) return;
    if (!_reduced) {
      pose.velocity += 34;
      _drop(pose, 18);
      if (widget.settings.sound) GardenAudio.rustle();
    }
    widget.settings.change(() => widget.settings.shakes++);
    _paint.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _paint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: TextButton(
          onPressed: () {
            GardenArtwork._cache = null;
            setState(() => _error = null);
            _load();
          },
          child: const Text('植物素材读取失败，点击重试'),
        ),
      );
    }
    if (_art == null) return const SizedBox.expand();
    return LayoutBuilder(
      builder: (context, box) {
        _arrange(box.biggest);
        return Semantics(
          container: true,
          excludeSemantics: true,
          label: '互动像素植物',
          button: true,
          onTap: () => _shake(_poses.firstOrNull),
          child: FocusableActionDetector(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            },
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  _shake(_poses.firstOrNull);
                  return null;
                },
              ),
            },
            child: MouseRegion(
              cursor: _hover
                  ? SystemMouseCursors.grab
                  : SystemMouseCursors.basic,
              onHover: (e) {
                final hover = _hit(e.localPosition) != null;
                if (hover != _hover) setState(() => _hover = hover);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: (e) => _shake(_hit(e.localPosition)),
                onPanStart: (e) {
                  _grab = _hit(e.localPosition);
                  if (_grab != null) {
                    _grab!.grabY =
                        (e.localPosition.dy - _grab!.origin.dy) / _grab!.scale;
                  }
                },
                onPanUpdate: (e) {
                  if (!_reduced && _grab != null) {
                    _grab!.force = (_grab!.force + e.delta.dx / 6).clamp(
                      -20,
                      20,
                    );
                  }
                },
                onPanEnd: (_) {
                  final p = _grab;
                  _grab = null;
                  _shake(p);
                },
                onPanCancel: () => _grab = null,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _GardenPainter(this, _paint),
                    size: box.biggest,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GardenPainter extends CustomPainter {
  _GardenPainter(this.world, Listenable clock) : super(repaint: clock);
  final _GardenSceneState world;
  static final _imagePaint = Paint()..filterQuality = FilterQuality.none;
  @override
  void paint(Canvas canvas, Size size) {
    for (final p in world._poses) {
      for (var index = 0; index < p.art.layers.length; index++) {
        final layer = p.art.layers[index],
            holes = p.holes.where((h) => h.$1 == index);
        final masked = holes.isNotEmpty && layer.detach;
        if (masked) canvas.saveLayer(Offset.zero & size, Paint());
        if (layer.detach && p.growth < 1) {
          canvas.saveLayer(
            Offset.zero & size,
            Paint()..color = Colors.white.withValues(alpha: p.growth),
          );
        }
        for (double y = 0; y < p.art.height; y += 2) {
          final rows = math.min(2.0, p.art.height - y),
              offset = world._offset(p, layer, y);
          canvas.drawImageRect(
            layer.image,
            Rect.fromLTWH(0, y, p.art.width, rows),
            Rect.fromLTWH(
              p.origin.dx + offset * p.scale,
              p.origin.dy + y * p.scale,
              p.art.width * p.scale,
              rows * p.scale + .2,
            ),
            _imagePaint,
          );
        }
        if (layer.detach && p.growth < 1) canvas.restore();
        if (masked) {
          for (final h in holes) {
            final r = h.$2;
            canvas.drawRect(
              Rect.fromLTWH(
                p.origin.dx +
                    (r.left + world._offset(p, layer, r.top)) * p.scale,
                p.origin.dy + r.top * p.scale,
                r.width * p.scale,
                r.height * p.scale,
              ),
              Paint()..blendMode = BlendMode.clear,
            );
          }
          canvas.restore();
        }
      }
      if (world.widget.settings.bones) {
        final paint = Paint()
          ..color = const Color(0xFF7FAA90)
          ..strokeWidth = 1;
        for (var i = 0; i < p.art.bones.length; i += 7) {
          final b = p.art.bones;
          canvas.drawLine(
            p.origin + Offset(b[i], b[i + 1]) * p.scale,
            p.origin + Offset(b[i + 2], b[i + 3]) * p.scale,
            paint,
          );
        }
      }
    }
    for (final leaf in world._leaves) {
      final scale = leaf.scale * world.widget.settings.leafSize;
      canvas.save();
      canvas.translate(leaf.position.dx, leaf.position.dy);
      canvas.rotate(
        leaf.phase + leaf.age * .7 + math.sin(leaf.age * 2 + leaf.phase) * .45,
      );
      final flip = math.cos(leaf.age * 1.8 + leaf.phase);
      canvas.scale(
        (flip < 0 ? -1 : 1) * math.max(.23, flip.abs()) * scale,
        scale,
      );
      final alpha = ((11 - leaf.age) / 1.2).clamp(0.0, 1.0);
      _leaf(canvas, leaf.name, alpha);
      canvas.restore();
    }
  }

  static void _leaf(Canvas canvas, String name, double alpha) {
    canvas.drawImage(
      PixelLeaves.image(name),
      const Offset(-8, -8),
      Paint()
        ..isAntiAlias = false
        ..filterQuality = FilterQuality.none
        ..color = Colors.white.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(_GardenPainter oldDelegate) => true;
}
