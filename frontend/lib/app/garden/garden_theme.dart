import 'package:flutter/material.dart';

abstract final class GardenTheme {
  static const paper = Color(0xFFF3F3F5);
  static const night = Color(0xFF202426);
  static const flower = Color(0xFFB37387);
  static ThemeData forBrightness(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? night : paper;
    final ink = dark ? const Color(0xFFE1E4DB) : const Color(0xFF3C4540);
    final muted = dark ? const Color(0xFFA0AAA0) : const Color(0xFF788179);
    final accent = dark ? const Color(0xFFD9A6B6) : flower;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      primary: accent,
      surface: background,
      onSurface: ink,
      onSurfaceVariant: muted,
      outlineVariant: muted.withValues(alpha: .16),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'GardenSerif',
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: background,
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w300,
          color: ink,
          letterSpacing: 5,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w400,
          color: ink,
          letterSpacing: 2,
        ),
        titleMedium: TextStyle(fontSize: 15, color: ink),
        bodyLarge: TextStyle(fontSize: 14, height: 1.7, color: ink),
        bodyMedium: TextStyle(fontSize: 13, height: 1.7, color: ink),
        bodySmall: TextStyle(fontSize: 11, height: 1.7, color: muted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 52,
        titleTextStyle: TextStyle(
          fontFamily: 'GardenSerif',
          fontSize: 19,
          color: ink,
          letterSpacing: 2,
        ),
      ),
      cardTheme: const CardThemeData(
        color: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(),
      ),
      dividerTheme: DividerThemeData(color: muted.withValues(alpha: .15)),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        border: UnderlineInputBorder(
          borderSide: BorderSide(color: muted.withValues(alpha: .25)),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: muted.withValues(alpha: .25)),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: accent),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          textStyle: const TextStyle(fontFamily: 'GardenSerif', fontSize: 12),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accent : Colors.transparent,
        ),
      ),
    );
  }
}
