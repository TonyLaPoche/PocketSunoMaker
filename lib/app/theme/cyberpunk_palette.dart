import 'package:flutter/material.dart';

@immutable
class CyberpunkPalette extends ThemeExtension<CyberpunkPalette> {
  const CyberpunkPalette({
    required this.bgPrimary,
    required this.bgSecondary,
    required this.bgElevated,
    required this.neonPink,
    required this.neonViolet,
    required this.neonBlue,
    required this.textPrimary,
    required this.textMuted,
    required this.border,
  });

  final Color bgPrimary;
  final Color bgSecondary;
  final Color bgElevated;
  final Color neonPink;
  final Color neonViolet;
  final Color neonBlue;
  final Color textPrimary;
  final Color textMuted;
  final Color border;

  static const CyberpunkPalette dark = CyberpunkPalette(
    bgPrimary: Color(0xFF09060F),
    bgSecondary: Color(0xFF130A1E),
    bgElevated: Color(0xFF1A1028),
    neonPink: Color(0xFFFF2BD6),
    neonViolet: Color(0xFF8A2BFF),
    neonBlue: Color(0xFF26C6FF),
    textPrimary: Color(0xFFF7ECFF),
    textMuted: Color(0xFFB9A9C7),
    border: Color(0xFF3A2653),
  );

  @override
  CyberpunkPalette copyWith({
    Color? bgPrimary,
    Color? bgSecondary,
    Color? bgElevated,
    Color? neonPink,
    Color? neonViolet,
    Color? neonBlue,
    Color? textPrimary,
    Color? textMuted,
    Color? border,
  }) {
    return CyberpunkPalette(
      bgPrimary: bgPrimary ?? this.bgPrimary,
      bgSecondary: bgSecondary ?? this.bgSecondary,
      bgElevated: bgElevated ?? this.bgElevated,
      neonPink: neonPink ?? this.neonPink,
      neonViolet: neonViolet ?? this.neonViolet,
      neonBlue: neonBlue ?? this.neonBlue,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
      border: border ?? this.border,
    );
  }

  @override
  CyberpunkPalette lerp(ThemeExtension<CyberpunkPalette>? other, double t) {
    if (other is! CyberpunkPalette) {
      return this;
    }
    return CyberpunkPalette(
      bgPrimary: Color.lerp(bgPrimary, other.bgPrimary, t) ?? bgPrimary,
      bgSecondary: Color.lerp(bgSecondary, other.bgSecondary, t) ?? bgSecondary,
      bgElevated: Color.lerp(bgElevated, other.bgElevated, t) ?? bgElevated,
      neonPink: Color.lerp(neonPink, other.neonPink, t) ?? neonPink,
      neonViolet: Color.lerp(neonViolet, other.neonViolet, t) ?? neonViolet,
      neonBlue: Color.lerp(neonBlue, other.neonBlue, t) ?? neonBlue,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textMuted: Color.lerp(textMuted, other.textMuted, t) ?? textMuted,
      border: Color.lerp(border, other.border, t) ?? border,
    );
  }
}

extension CyberpunkPaletteX on BuildContext {
  CyberpunkPalette get cyberpunk =>
      Theme.of(this).extension<CyberpunkPalette>() ?? CyberpunkPalette.dark;
}
