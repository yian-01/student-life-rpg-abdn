import 'package:flutter/material.dart';
import 'app_routes.dart';

class ModuleNavigation extends StatelessWidget {
  const ModuleNavigation({super.key, required this.selectedIndex});
  final int selectedIndex;
  static const routes = [
    AppRoutes.menu,
    AppRoutes.schedule,
    AppRoutes.gpa,
    AppRoutes.finance,
    AppRoutes.dashboard,
  ];

  void _select(BuildContext context, int index) {
    if (index == selectedIndex) return;
    final navigator = Navigator.of(context);
    if (index == 0) {
      var foundMenu = false;
      navigator.popUntil((route) {
        foundMenu = route.settings.name == AppRoutes.menu;
        return foundMenu || route.isFirst;
      });
      if (!foundMenu) navigator.pushReplacementNamed(AppRoutes.menu);
    } else if (selectedIndex == 0) {
      navigator.pushNamed(routes[index]);
    } else {
      navigator.pushReplacementNamed(routes[index]);
    }
  }

  @override
  Widget build(BuildContext context) => NavigationBar(
    selectedIndex: selectedIndex,
    onDestinationSelected: (index) => _select(context, index),
    height: 72,
    backgroundColor: Colors.white,
    indicatorColor: const Color(0xFFE9EDFF),
    destinations: const [
      NavigationDestination(
        icon: Icon(Icons.grid_view_outlined),
        selectedIcon: Icon(Icons.grid_view_rounded),
        label: '手册',
      ),
      NavigationDestination(
        icon: Icon(Icons.event_note_outlined),
        selectedIcon: Icon(Icons.event_note),
        label: '日程',
      ),
      NavigationDestination(
        icon: Icon(Icons.school_outlined),
        selectedIcon: Icon(Icons.school),
        label: '学业',
      ),
      NavigationDestination(
        icon: Icon(Icons.wallet_outlined),
        selectedIcon: Icon(Icons.wallet),
        label: '账本',
      ),
      NavigationDestination(
        icon: Icon(Icons.pie_chart_outline),
        selectedIcon: Icon(Icons.pie_chart),
        label: '总览',
      ),
    ],
  );
}
