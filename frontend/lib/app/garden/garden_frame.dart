import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoSlider;
import 'package:flutter/services.dart';
import '../cloud/cloud_page.dart';
import 'garden_audio.dart';
import 'garden_routes.dart';
import 'garden_scene.dart';
import 'garden_settings.dart';
import 'garden_theme.dart';
import 'page_gesture.dart';

class GardenFrame extends StatefulWidget {
  const GardenFrame({
    super.key,
    required this.settings,
    required this.route,
    required this.popup,
    required this.navigator,
    required this.child,
  });
  final GardenSettings settings;
  final ValueNotifier<String> route;
  final ValueNotifier<bool> popup;
  final GlobalKey<NavigatorState> navigator;
  final Widget child;
  @override
  State<GardenFrame> createState() => _GardenFrameState();
}

class _GardenFrameState extends State<GardenFrame> {
  final _gesture = PageGesture();
  final _clock = Stopwatch()..start();
  bool _navigation = false, _settings = false, _dots = false;
  Timer? _closeTimer, _dotTimer;
  int get _section => GardenRoutes.section(widget.route.value);
  bool get _editing {
    final focus = FocusManager.instance.primaryFocus?.context;
    return focus?.widget is EditableText ||
        focus?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _open(String route) {
    if (widget.popup.value) return;
    setState(() => _navigation = false);
    if (widget.route.value != route) {
      widget.navigator.currentState?.pushReplacementNamed(route);
    }
  }

  void _step(int delta) {
    if (_settings || widget.popup.value || _editing) return;
    final next = (_section + delta).clamp(0, GardenRoutes.hubs.length - 1);
    _showDots();
    if (next == _section) return;
    _open(GardenRoutes.hubs[next]);
  }

  void _showDots() {
    _dotTimer?.cancel();
    if (!_dots) setState(() => _dots = true);
    _dotTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _dots = false);
    });
  }

  void _closeSoon() {
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 160), () {
      if (mounted) setState(() => _navigation = false);
    });
  }

  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        HardwareKeyboard.instance.isControlPressed) {
      return;
    }
    final direction = _gesture.add(
      x: event.scrollDelta.dx,
      y: event.scrollDelta.dy,
      time: _clock.elapsed,
      blocked: _settings || widget.popup.value || _editing,
    );
    final horizontal =
        event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs() * 1.25;
    if (horizontal && !_settings && !widget.popup.value && !_editing) {
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {
        if (direction != null) {
          _step(direction);
        } else {
          _showDots();
        }
      });
    }
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _dotTimer?.cancel();
    GardenAudio.enable(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.settings, widget.route, widget.popup]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest,
            section = _section,
            hub = GardenRoutes.hubs.contains(widget.route.value),
            home = widget.route.value == '/';
        final immersive =
            widget.route.value == '/bedroom' || widget.route.value == '/menu';
        final colors = Theme.of(context).colorScheme;
        final contentInsets = hub || immersive
            ? EdgeInsets.zero
            : EdgeInsets.fromLTRB(
                size.width >= 1300 ? 168 : 125,
                78,
                size.width >= 1300 ? 270 : 205,
                36,
              );
        final sceneRect = home
            ? Rect.fromLTWH(
                size.width * .27,
                size.height * .29,
                size.width * .46,
                size.height * .55,
              )
            : hub
            ? Rect.fromLTWH(
                size.width * .55,
                size.height * .19,
                size.width * .38,
                size.height * .62,
              )
            : Rect.fromLTWH(
                size.width * .78,
                size.height * .32,
                size.width * .2,
                size.height * .45,
              );
        return Focus(
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent ||
                _editing ||
                _settings ||
                widget.popup.value) {
              return KeyEventResult.ignored;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _step(-1);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              _step(1);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Listener(
            onPointerSignal: _wheel,
            onPointerPanZoomUpdate: (event) {
              final direction = _gesture.add(
                x: -event.panDelta.dx,
                y: -event.panDelta.dy,
                time: _clock.elapsed,
                blocked:
                    event.scale != 1 ||
                    _settings ||
                    widget.popup.value ||
                    _editing,
              );
              if (direction != null) _step(direction);
            },
            child: ColoredBox(
              color: Theme.of(context).brightness == Brightness.dark
                  ? GardenTheme.night
                  : GardenTheme.paper,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(padding: contentInsets, child: widget.child),
                  ),
                  Positioned.fromRect(
                    rect: sceneRect,
                    child: Visibility(
                      visible: !widget.popup.value && !immersive,
                      maintainState: true,
                      child: GardenScene(
                        key: const Key('garden-scene'),
                        settings: widget.settings,
                        plant: GardenRoutes.plants[section],
                      ),
                    ),
                  ),
                  if (!widget.popup.value) ...[
                    if (_navigation)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: 138,
                        child: ColoredBox(
                          key: const Key('garden-navigation-background'),
                          color: colors.surface,
                        ),
                      ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 24,
                      child: MouseRegion(
                        onEnter: (_) {
                          _closeTimer?.cancel();
                          setState(() => _navigation = true);
                        },
                        onExit: (_) => _closeSoon(),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Positioned(
                      left: 28,
                      top: 22,
                      child: TextButton(
                        key: const Key('garden-brand'),
                        onPressed: () =>
                            setState(() => _navigation = !_navigation),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(80, 32),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              'assets/garden/blossom.png',
                              width: 28,
                              height: 28,
                              filterQuality: FilterQuality.none,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'KEYU',
                              style: TextStyle(
                                fontSize: 13,
                                letterSpacing: 3,
                                color: colors.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_navigation)
                      Positioned(
                        left: 30,
                        top: math.min(144, size.height * .16),
                        bottom: 28,
                        width: 108,
                        child: MouseRegion(
                          onEnter: (_) => _closeTimer?.cancel(),
                          onExit: (_) => _closeSoon(),
                          child: Material(
                            key: const Key('garden-navigation'),
                            color: colors.surface,
                            textStyle: Theme.of(context).textTheme.bodyMedium,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '一日一叶',
                                  style: TextStyle(
                                    fontSize: 12,
                                    letterSpacing: 2,
                                    color: colors.onSurfaceVariant.withValues(
                                      alpha: .65,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 22),
                                for (var i = 0; i < 5; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 13),
                                    child: TextButton(
                                      key: ValueKey('garden-nav-$i'),
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        alignment: Alignment.centerLeft,
                                        minimumSize: const Size(98, 28),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () =>
                                          _open(GardenRoutes.hubs[i]),
                                      child: Row(
                                        children: [
                                          Text(
                                            '0${i + 1}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: colors.onSurfaceVariant
                                                  .withValues(alpha: .5),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            GardenRoutes.names[i],
                                            style: TextStyle(
                                              fontSize: 12,
                                              letterSpacing: 2,
                                              color: i == section
                                                  ? colors.primary
                                                  : colors.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                const Spacer(),
                                _navAction('互动设置', () {
                                  setState(() {
                                    _navigation = false;
                                    _settings = true;
                                  });
                                }, key: const Key('garden-open-settings')),
                                _navAction(
                                  widget.settings.theme == ThemeMode.dark
                                      ? '切换浅色'
                                      : '切换深色',
                                  widget.settings.toggleTheme,
                                  key: const Key('garden-theme'),
                                ),
                                _navAction(
                                  '我的账号',
                                  () => _open(CloudPage.route),
                                  key: const Key('garden-account'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (_dots)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 22,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < 5; i++)
                              SizedBox(
                                width: 24,
                                height: 26,
                                child: TextButton(
                                  onPressed: () => _open(GardenRoutes.hubs[i]),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                  ),
                                  child: Container(
                                    width: i == section ? 6 : 3,
                                    height: i == section ? 6 : 3,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: i == section ? 1 : .55,
                                      ),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: colors.onSurfaceVariant
                                            .withValues(alpha: .2),
                                        width: .5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (_settings)
                      Positioned(
                        right: size.width * .04,
                        top: size.height * .1,
                        width: 286,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: size.height * .84,
                          ),
                          child: Material(
                            color: colors.surface,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(14),
                              child: _settingsPanel(context),
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  Widget _navAction(String text, VoidCallback action, {Key? key}) => TextButton(
    key: key,
    style: TextButton.styleFrom(
      padding: EdgeInsets.zero,
      alignment: Alignment.centerLeft,
      minimumSize: const Size(98, 30),
      textStyle: const TextStyle(fontFamily: 'GardenSerif', fontSize: 12),
    ),
    onPressed: action,
    child: Text(text),
  );
  Widget _settingsPanel(BuildContext context) {
    final s = widget.settings;
    Widget line(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11)),
          child,
        ],
      ),
    );
    Widget range(String label, double value, ValueChanged<double> change) =>
        Column(
          children: [
            line(
              label,
              Text(
                '${(value * 100).round()}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            SizedBox(
              height: 36,
              child: LayoutBuilder(
                builder: (context, bounds) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTapUp: (event) => s.change(
                    () => change(
                      ((event.localPosition.dx - 22) / (bounds.maxWidth - 44))
                          .clamp(0.0, 1.0),
                    ),
                  ),
                  child: CupertinoSlider(
                    key: ValueKey('garden-range-$label'),
                    activeColor: Theme.of(context).colorScheme.primary,
                    thumbColor: Theme.of(context).colorScheme.primary,
                    value: value,
                    onChanged: (v) => s.change(() => change(v)),
                  ),
                ),
              ),
            ),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '互动设置',
              style: TextStyle(fontSize: 19, letterSpacing: 2),
            ),
            TextButton(
              key: const Key('garden-close-settings'),
              onPressed: () => setState(() => _settings = false),
              child: const Text('收起'),
            ),
          ],
        ),
        line('风', Switch(value: s.weather, onChanged: s.toggleWind)),
        Row(
          children: [
            TextButton(
              onPressed: () => s.preset(false),
              child: const Text('微风'),
            ),
            TextButton(
              onPressed: () => s.preset(true),
              child: const Text('风暴'),
            ),
          ],
        ),
        line(
          '风向',
          Row(
            children: [
              TextButton(
                onPressed: () => s.change(() => s.direction = -1),
                child: const Text('向左'),
              ),
              TextButton(
                onPressed: () => s.change(() => s.direction = 1),
                child: const Text('向右'),
              ),
            ],
          ),
        ),
        range('风速', s.strength, (v) {
          s.strength = v;
          s.weather = v > 0;
        }),
        range('阵风', s.gusts, (v) => s.gusts = v),
        line(
          '骨架显示',
          Switch(value: s.bones, onChanged: (v) => s.change(() => s.bones = v)),
        ),
        line(
          '风声与枝叶声',
          Switch(
            value: s.sound,
            onChanged: (v) async {
              final success = await GardenAudio.enable(v);
              if (mounted) s.change(() => s.sound = success && v);
            },
          ),
        ),
        line(
          '植物场景',
          MenuAnchor(
            menuChildren: [
              for (final option in const {
                'page': '跟随页面',
                'all': '三株并置',
                'single': '单株试验场',
              }.entries)
                MenuItemButton(
                  onPressed: () => s.change(() => s.view = option.key),
                  child: Text(option.value),
                ),
            ],
            builder: (context, controller, child) => TextButton(
              onPressed: controller.isOpen ? controller.close : controller.open,
              child: Text(
                const {
                  'page': '跟随页面',
                  'all': '三株并置',
                  'single': '单株试验场',
                }[s.view]!,
              ),
            ),
          ),
        ),
        if (s.view == 'single')
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => s.change(() => s.plant = (s.plant + 4) % 5),
                child: const Text('上一株'),
              ),
              Text(const ['樱花', '灌木', '枫树', '银杏', '竹丛'][s.plant]),
              TextButton(
                onPressed: () => s.change(() => s.plant = (s.plant + 1) % 5),
                child: const Text('下一株'),
              ),
            ],
          ),
        line(
          '轻摇 ${s.shakes} 次',
          TextButton(
            onPressed: () => s.change(() => s.regrowth++),
            child: const Text('重新长叶'),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '点击落叶，拖动枝叶。横滑一次切一页，首页在最左端，首尾不循环。',
          style: TextStyle(fontSize: 11, height: 1.8),
        ),
      ],
    );
  }
}
