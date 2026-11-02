import 'package:flutter/material.dart';

import '../features/bedroom/presentation/bedroom_page.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/finance/presentation/finance_page.dart';
import '../features/gpa/presentation/gpa_page.dart';
import '../features/academic/presentation/academic_management_page.dart';
import '../features/schedule/presentation/event_management_page.dart';
import 'campus_data_host.dart';
import 'campus_recovery.dart';
import '../features/menu/presentation/menu_page.dart';
import 'unknown_route_page.dart';
import 'task_schedule_host.dart';
import 'game_panel_frame.dart';

abstract final class AppRoutes {
  static const bedroom = '/bedroom';
  static const menu = '/menu';
  static const schedule = '/schedule';
  static const gpa = '/gpa';
  static const finance = '/finance';
  static const dashboard = '/dashboard';

  static const academic = '/academic';
  static const events = '/events';

  static Route<void> generateRoute(RouteSettings settings) {
    final page = switch (settings.name) {
      bedroom => const BedroomPage(),
      menu => const MenuPage(),
      schedule => const TaskScheduleHost(),
      gpa => CampusDataHost(
        title: '学业档案',
        builder: (context, data) => GpaPage(
          composition: data.gpa,
          onManage: () => Navigator.of(context).pushNamed<void>(academic),
        ),
      ),
      academic => CampusDataHost(
        title: '学期与课程',
        builder: (_, data) => AcademicManagementPage(data: data),
      ),
      events => CampusDataHost(
        title: '事件安排',
        builder: (_, data) => EventManagementPage(
          data: data,
          initialDate: settings.arguments is DateTime
              ? settings.arguments as DateTime
              : null,
        ),
      ),
      finance => CampusDataHost(
        title: '生活账本',
        builder: (context, data) => FinancePage(
          controller: data.finance,
          isPersistent: true,
          onRecover: () async {
            if (await recoverCampusData(context, data)) {
              await data.finance.retry();
            }
          },
        ),
      ),
      dashboard => const DashboardPage(),
      _ => UnknownRoutePage(routeName: settings.name),
    };
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => settings.name == bedroom || settings.name == menu
          ? page
          : GamePanelFrame(child: page),
    );
  }
}
