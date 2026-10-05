import 'package:flutter/material.dart';

import '../../../app/app_routes.dart';

class MenuPage extends StatelessWidget {
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    const destinations = {
      'Schedule': AppRoutes.schedule,
      'GPA': AppRoutes.gpa,
      'Finance': AppRoutes.finance,
      'Dashboard': AppRoutes.dashboard,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Menu')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            for (final destination in destinations.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pushNamed(destination.value),
                  child: Text(destination.key),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
