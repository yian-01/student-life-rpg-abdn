import 'package:flutter/material.dart';

import '../features/bedroom/presentation/bedroom_page.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/finance/presentation/finance_page.dart';
import '../features/gpa/presentation/gpa_page.dart';
import '../features/menu/presentation/menu_page.dart';
import '../features/schedule/presentation/schedule_page.dart';
import 'unknown_route_page.dart';

abstract final class AppRoutes {
  static const bedroom = '/bedroom';
  static const menu = '/menu';
  static const schedule = '/schedule';
  static const gpa = '/gpa';
  static const finance = '/finance';
  static const dashboard = '/dashboard';

  static Route<void> generateRoute(RouteSettings settings) {
    final page = switch (settings.name) {
      bedroom => const BedroomPage(),
      menu => const MenuPage(),
      schedule => const SchedulePage(),
      gpa => const GpaPage(),
      finance => const FinancePage(),
      dashboard => const DashboardPage(),
      _ => UnknownRoutePage(routeName: settings.name),
    };
    return MaterialPageRoute<void>(settings: settings, builder: (_) => page);
  }
}
