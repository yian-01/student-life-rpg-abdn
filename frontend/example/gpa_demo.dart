import 'package:flutter/widgets.dart';
import 'package:student_life_rpg/app/app_routes.dart';
import 'package:student_life_rpg/app/student_life_app.dart';

/// Runs the same app-scoped GPA assembly and page directly for native review.
void main() => runApp(const StudentLifeApp(initialRoute: AppRoutes.gpa));
