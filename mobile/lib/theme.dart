import 'package:flutter/material.dart';

/// Shared brand tokens — keep in sync with Windows `fill_shipping_label.py`.
class SwiftColors {
  static const accent = Color(0xFFD94B2B);
  static const accentSoft = Color(0xFFF8EBE7);
  static const bg = Color(0xFFF4F2EF);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1A1A1A);
  static const muted = Color(0xFF6B6B6B);
  static const border = Color(0xFFE6E2DC);
}

class SwiftTheme {
  static ThemeData light() {
    final base = ColorScheme.fromSeed(
      seedColor: SwiftColors.accent,
      primary: SwiftColors.accent,
      surface: SwiftColors.surface,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: base.copyWith(
        primary: SwiftColors.accent,
        onPrimary: Colors.white,
        surface: SwiftColors.surface,
        onSurface: SwiftColors.ink,
      ),
      scaffoldBackgroundColor: SwiftColors.bg,
      fontFamily: 'Calibri',
      appBarTheme: const AppBarTheme(
        backgroundColor: SwiftColors.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Oswald',
          fontWeight: FontWeight.w600,
          fontSize: 20,
          color: Colors.white,
          letterSpacing: 0.4,
        ),
      ),
      cardTheme: CardThemeData(
        color: SwiftColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: SwiftColors.border),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFAFAF8),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        labelStyle: const TextStyle(
          fontFamily: 'Oswald',
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: SwiftColors.muted,
          letterSpacing: 0.6,
        ),
        floatingLabelStyle: const TextStyle(
          fontFamily: 'Oswald',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: SwiftColors.accent,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: SwiftColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: SwiftColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: SwiftColors.accent, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SwiftColors.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: 'Oswald',
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: 0.4,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SwiftColors.ink,
          side: const BorderSide(color: SwiftColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          textStyle: const TextStyle(
            fontFamily: 'Calibri',
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: SwiftColors.muted,
          textStyle: const TextStyle(
            fontFamily: 'Calibri',
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: SwiftColors.ink,
        contentTextStyle: const TextStyle(fontFamily: 'Calibri', color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
