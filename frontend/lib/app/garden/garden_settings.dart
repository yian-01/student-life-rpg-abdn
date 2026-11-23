import 'package:flutter/material.dart';

/// Visual preferences contain no account data or authentication state.
class GardenSettings extends ChangeNotifier {
  ThemeMode theme = ThemeMode.light;
  bool weather = false;
  bool storm = false;
  double strength = 0;
  double gusts = .45;
  int direction = 1;
  bool bones = false;
  bool sound = false;
  double sway = 1;
  double leafSize = 1;
  int shakes = 0;
  int regrowth = 0;
  String view = 'page';
  int plant = 0;

  void change(VoidCallback update) {
    update();
    notifyListeners();
  }

  void toggleTheme() => change(() {
    theme = theme == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
  });

  void preset(bool strong) => change(() {
    storm = strong;
    weather = true;
    strength = strong ? 1 : .35;
    gusts = strong ? .85 : .45;
  });

  void toggleWind(bool enabled) => change(() {
    weather = enabled;
    strength = enabled ? (storm ? 1 : .35) : 0;
  });
}

class GardenScope extends InheritedNotifier<GardenSettings> {
  const GardenScope({
    super.key,
    required GardenSettings settings,
    required this.desktop,
    required super.child,
  }) : super(notifier: settings);

  final bool desktop;
  static GardenScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GardenScope>();
  static bool isDesktop(BuildContext context) =>
      maybeOf(context)?.desktop ?? false;
}
