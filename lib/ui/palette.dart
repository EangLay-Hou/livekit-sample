import 'package:flutter/material.dart';

/// App color palette inspired by design reference.
class AppPalette {
  static const Color greenDeep = Color(0xFF3D8D7A);
  static const Color greenLight = Color(0xFFB3D8A8);
  static const Color cream = Color(0xFFFBFFE4);
  static const Color mint = Color(0xFFA3D1C6);
  static const Color neutral = Color(0xFF7A8B86);
  static const Color neutralDark = Color(0xFF5E6B67);
  static const Color error = Color(0xFFD95C5C);
  static const Color background = Color(0xFFF7F9F6);
  static const Color textPrimary = neutralDark;
  static const Color textMuted = neutral;

  /// Gradient for hero/header backgrounds.
  static const LinearGradient heroGradient = LinearGradient(
    colors: [cream, mint],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Background for cards and chips.
  static const Color cardBg = cream;
}
