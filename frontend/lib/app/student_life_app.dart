import 'package:flutter/material.dart';

import 'app_routes.dart';
import 'app_theme.dart';

class StudentLifeApp extends StatelessWidget {
  const StudentLifeApp({super.key, this.initialRoute = AppRoutes.bedroom});

  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Student Life RPG',
      theme: AppTheme.light,
      initialRoute: initialRoute,
      // Start with one root page, without an implicit '/' underneath.
      onGenerateInitialRoutes: (name) => [
        AppRoutes.generateRoute(RouteSettings(name: name)),
      ],
      onGenerateRoute: AppRoutes.generateRoute,
    );
  }
}
