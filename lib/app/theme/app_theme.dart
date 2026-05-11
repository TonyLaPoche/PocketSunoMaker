import 'package:flutter/material.dart';

import 'cyberpunk_palette.dart';

final class AppTheme {
  static ThemeData dark() {
    const CyberpunkPalette palette = CyberpunkPalette.dark;
    final ColorScheme colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: palette.neonViolet,
      onPrimary: palette.textPrimary,
      secondary: palette.neonPink,
      onSecondary: palette.textPrimary,
      error: const Color(0xFFFF5D7A),
      onError: palette.textPrimary,
      surface: palette.bgElevated,
      onSurface: palette.textPrimary,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: palette.bgPrimary,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: palette.bgSecondary,
        foregroundColor: palette.textPrimary,
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        color: palette.bgElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: palette.border),
        ),
      ),
      textTheme: const TextTheme().apply(
        bodyColor: palette.textPrimary,
        displayColor: palette.textPrimary,
      ),
      dividerColor: palette.border,
      extensions: const <ThemeExtension<dynamic>>[palette],
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.neonViolet,
          foregroundColor: palette.textPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.neonPink,
          side: BorderSide(color: palette.neonPink.withValues(alpha: 0.55)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
