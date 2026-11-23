import 'package:flutter/material.dart';
import '../features/schedule/models/task.dart';
import '../features/schedule/presentation/focus_timer_page.dart';
import '../features/schedule/presentation/today_planner_page.dart';
import 'app_data.dart';
import 'cloud/cloud_page.dart';
import '../features/local_records/local_records_page.dart';

import '../features/bedroom/presentation/bedroom_page.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/finance/presentation/finance_page.dart';
import '../features/gpa/presentation/gpa_page.dart';
import '../features/academic/presentation/academic_management_page.dart';
import '../features/schedule/presentation/event_management_page.dart';
import 'campus_data_host.dart';
import 'campus_recovery.dart';
import 'full_backup_page.dart';
import '../features/menu/presentation/menu_page.dart';
import 'unknown_route_page.dart';
import 'task_schedule_host.dart';
import 'platform_navigation.dart';
import 'platform_home_page.dart';
import 'platform_profile_page.dart';
import 'garden/garden_routes.dart';
import 'social/social_page.dart';
import 'garden/garden_settings.dart';
import 'garden/garden_business_pages.dart';
import '../features/finance/presentation/finance_filter_page.dart';
import '../features/finance/presentation/weekly_finance_page.dart';

abstract final class AppRoutes {
  static const home = '/';
  static const profile = '/profile';
  static const bedroom = '/bedroom';
  static const menu = '/menu';
  static const schedule = '/schedule';
  static const gpa = '/gpa';
  static const finance = '/finance';
  static const dashboard = '/dashboard';

  static const academic = '/academic';
  static const events = '/events';
  static const todo = '/todo';
  static const search = '/search';
  static const backup = '/backup';
  static const today = '/today';
  static const focus = '/focus';

  static Route<void> generateRoute(RouteSettings settings) {
    final page = switch (settings.name) {
      home => const _AdaptiveHome(),
      GardenRoutes.study => const _AdaptiveGardenHub(section: 1),
      GardenRoutes.days => const _AdaptiveGardenHub(section: 2),
      GardenRoutes.finance => const _AdaptiveGardenHub(section: 3),
      GardenRoutes.more => const _AdaptiveGardenHub(section: 4),
      GardenRoutes.assignments || GardenRoutes.exams => CampusDataHost(
        title: settings.name == GardenRoutes.exams ? '考试' : '作业',
        builder: (_, data) => GardenAcademicRecords(
          data: data,
          exams: settings.name == GardenRoutes.exams,
        ),
      ),
      GardenRoutes.week => const GardenWeekPage(),
      GardenRoutes.statistics => CampusDataHost(
        title: '财务统计',
        builder: (_, data) => WeeklyFinancePage(controller: data.finance),
      ),
      GardenRoutes.categories || GardenRoutes.budgets => CampusDataHost(
        title: '财务设置',
        builder: (_, data) => GardenFinanceSettings(
          data: data,
          budgets: settings.name == GardenRoutes.budgets,
        ),
      ),
      GardenRoutes.receipts => CampusDataHost(
        title: '票据与报销',
        builder: (_, data) =>
            FinanceFilterPage(controller: data.finance, receiptsOnly: true),
      ),
      profile => const PlatformProfilePage(),
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
          budgetController: data.budgetController,
          isPersistent: true,
          initialMonth: settings.arguments is DateTime
              ? settings.arguments as DateTime
              : null,
          onRecover: () async {
            if (await recoverCampusData(context, data)) {
              await data.finance.retry();
            }
          },
        ),
      ),
      dashboard => const DashboardPage(),
      todo => const LocalRecordsPage(),
      search => const LocalRecordsPage(search: true),
      backup => const FullBackupPage(),
      CloudPage.route => const CloudPage(),
      SocialPage.route => const SocialPage(),
      today => const TodayPlannerPage(),
      focus => FocusTimerPage(
        timer: AppData.focusTimer,
        task: settings.arguments is Task ? settings.arguments as Task : null,
      ),
      _ => UnknownRoutePage(routeName: settings.name),
    };
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (context) => PlatformNavigation.routes.contains(settings.name)
          ? PlatformNavigation(route: settings.name!, child: page)
          : settings.name == bedroom
          ? Stack(
              fit: StackFit.expand,
              children: [
                page,
                if (Navigator.of(context).canPop())
                  Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      child: Center(
                        child: FilledButton.tonalIcon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text('返回'),
                        ),
                      ),
                    ),
                  ),
              ],
            )
          : page,
    );
  }
}

class _AdaptiveHome extends StatelessWidget {
  const _AdaptiveHome();
  @override
  Widget build(BuildContext context) => GardenScope.isDesktop(context)
      ? const GardenLandingPage()
      : const PlatformHomePage();
}

/// Resizing an open desktop hub must not leave a phone-sized window without
/// navigation. Keep its route so expanding the window restores the same hub.
class _AdaptiveGardenHub extends StatelessWidget {
  const _AdaptiveGardenHub({required this.section});
  final int section;
  @override
  Widget build(BuildContext context) => GardenScope.isDesktop(context)
      ? GardenLandingPage(section: section)
      : const PlatformNavigation(
          route: AppRoutes.home,
          child: PlatformHomePage(),
        );
}
