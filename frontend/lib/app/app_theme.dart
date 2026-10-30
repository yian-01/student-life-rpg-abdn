import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const background = Color(0xFF151C19);
  static const panel = Color(0xFF222D27);
  static const gold = Color(0xFFD8BA77);

  static final ThemeData light = ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: gold,
      brightness: Brightness.dark,
      primary: gold,
      surface: panel,
    ),
    scaffoldBackgroundColor: background,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      foregroundColor: Color(0xFFF4EBDC),
      centerTitle: false,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: panel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF485143)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: background,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
