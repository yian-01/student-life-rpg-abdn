import 'package:flutter/material.dart';

import 'app_routes.dart';
import 'app_theme.dart';
import 'app_viewport.dart';

class StudentLifeApp extends StatelessWidget {
  const StudentLifeApp({super.key, this.initialRoute = AppRoutes.bedroom});

  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Student Life RPG',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: (context, child) =>
          AppViewport(child: child ?? const SizedBox.shrink()),
      initialRoute: initialRoute,
      // Start with one root page, without an implicit '/' underneath.
      onGenerateInitialRoutes: (name) => [
        AppRoutes.generateRoute(RouteSettings(name: name)),
      ],
      onGenerateRoute: AppRoutes.generateRoute,
    );
  }
}
