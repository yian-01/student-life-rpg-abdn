import 'package:flutter/material.dart';

import 'app_routes.dart';

/// Route replacement keeps each tab fresh without retaining account data.
class PlatformNavigation extends StatelessWidget {
  const PlatformNavigation({
    super.key,
    required this.route,
    required this.child,
  });
  final String route;
  final Widget child;

  static const routes = [
    AppRoutes.home,
    AppRoutes.schedule,
    AppRoutes.finance,
    AppRoutes.profile,
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: child,
    bottomNavigationBar: DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE3EAED))),
      ),
      child: NavigationBar(
        height: MediaQuery.sizeOf(context).height < 500 ? 64 : null,
        labelBehavior: MediaQuery.sizeOf(context).height < 500
            ? NavigationDestinationLabelBehavior.alwaysHide
            : NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: routes.indexOf(route),
        onDestinationSelected: (index) {
          if (routes[index] != route) {
            Navigator.of(context).pushReplacementNamed(routes[index]);
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: '课表',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet_rounded),
            label: '记账',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
    ),
  );
}
