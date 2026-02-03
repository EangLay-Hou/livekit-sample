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
        primary: AppPalette.darkPrimary,
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
        seedColor: AppPalette.darkPrimary,
        brightness: Brightness.dark,
      ).copyWith(
        primary: AppPalette.darkPrimary,
        surface: AppPalette.darkSurface,
        onSurface: AppPalette.darkTextPrimary,
        background: AppPalette.darkBackground,
        onBackground: AppPalette.darkTextPrimary,
        onPrimary: Colors.white,
        error: AppPalette.error,
      ),
      scaffoldBackgroundColor: AppPalette.darkBackground,
      textTheme: ThemeData.dark().textTheme.apply(
            bodyColor: AppPalette.darkTextPrimary,
            displayColor: AppPalette.darkTextPrimary,
          ),
      appBarTheme: const AppBarTheme(
        foregroundColor: AppPalette.darkTextPrimary,
        titleTextStyle: TextStyle(
          color: AppPalette.darkTextPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
