import 'package:flutter/material.dart';

import 'palette.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppPalette.greenDeep,
        surface: AppPalette.cream,
      ).copyWith(
        onSurface: AppPalette.textPrimary,
        onPrimary: Colors.white,
        error: AppPalette.error,
      ),
      scaffoldBackgroundColor: AppPalette.background,
      textTheme: ThemeData.light().textTheme.apply(
            bodyColor: AppPalette.textPrimary,
            displayColor: AppPalette.textPrimary,
          ),
      appBarTheme: const AppBarTheme(
        foregroundColor: AppPalette.textPrimary,
        titleTextStyle: TextStyle(
          color: AppPalette.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppPalette.greenDeep,
        brightness: Brightness.dark,
      ).copyWith(
        surface: const Color(0xFF1A2A27),
        onSurface: AppPalette.cream,
        onPrimary: Colors.white,
        error: AppPalette.error,
      ),
      scaffoldBackgroundColor: const Color(0xFF0F1F1C),
      textTheme: ThemeData.dark().textTheme.apply(
            bodyColor: AppPalette.cream,
            displayColor: AppPalette.cream,
          ),
      appBarTheme: const AppBarTheme(
        foregroundColor: AppPalette.cream,
        titleTextStyle: TextStyle(
          color: AppPalette.cream,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
