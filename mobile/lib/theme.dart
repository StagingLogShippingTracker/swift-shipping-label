import 'dart:io';

import 'package:flutter/material.dart';

/// Shared brand tokens — keep in sync with Windows `fill_shipping_label.py`.
class SwiftColors {
  static const accent = Color(0xFFCE4E30);
  static const accentSoft = Color(0xFFF8EBE7);
  static const bg = Color(0xFFF4F2EF);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1A1A1A);
  static const muted = Color(0xFF6B6B6B);
  static const border = Color(0xFFE6E2DC);
  /// Slightly cooler panel wash for desktop chrome (rails / sidebars).
  static const panel = Color(0xFFF7F5F2);
  static const railSelected = Color(0xFFF3E4DF);
}

class SwiftTheme {
  static ThemeData light() {
    final desktop = Platform.isWindows;
    final base = ColorScheme.fromSeed(
      seedColor: SwiftColors.accent,
      primary: SwiftColors.accent,
      surface: SwiftColors.surface,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      visualDensity:
          desktop ? VisualDensity.compact : VisualDensity.standard,
      colorScheme: base.copyWith(
        primary: SwiftColors.accent,
        onPrimary: Colors.white,
        surface: SwiftColors.surface,
        onSurface: SwiftColors.ink,
      ),
      scaffoldBackgroundColor: SwiftColors.bg,
      fontFamily: 'Calibri',
      appBarTheme: AppBarTheme(
        backgroundColor: desktop ? SwiftColors.surface : SwiftColors.accent,
        foregroundColor: desktop ? SwiftColors.ink : Colors.white,
        elevation: 0,
        scrolledUnderElevation: desktop ? 0.5 : 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Oswald',
          fontWeight: FontWeight.w600,
          fontSize: desktop ? 16 : 20,
          color: desktop ? SwiftColors.ink : Colors.white,
          letterSpacing: 0.4,
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: SwiftColors.panel,
        indicatorColor: SwiftColors.railSelected,
        selectedIconTheme: const IconThemeData(
          color: SwiftColors.accent,
          size: 22,
        ),
        unselectedIconTheme: const IconThemeData(
          color: SwiftColors.muted,
          size: 22,
        ),
        selectedLabelTextStyle: const TextStyle(
          fontFamily: 'Oswald',
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: SwiftColors.accent,
          letterSpacing: 0.3,
        ),
        unselectedLabelTextStyle: const TextStyle(
          fontFamily: 'Calibri',
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: SwiftColors.muted,
        ),
      ),
      cardTheme: CardThemeData(
        color: SwiftColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(desktop ? 8 : 14),
          side: const BorderSide(color: SwiftColors.border),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFAFAF8),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: desktop ? 8 : 10,
        ),
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
          borderRadius: BorderRadius.circular(desktop ? 6 : 10),
          borderSide: const BorderSide(color: SwiftColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(desktop ? 6 : 10),
          borderSide: const BorderSide(color: SwiftColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(desktop ? 6 : 10),
          borderSide: const BorderSide(color: SwiftColors.accent, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SwiftColors.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: desktop ? 18 : 22,
            vertical: desktop ? 12 : 14,
          ),
          textStyle: TextStyle(
            fontFamily: 'Oswald',
            fontWeight: FontWeight.w600,
            fontSize: desktop ? 14 : 15,
            letterSpacing: 0.4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(desktop ? 6 : 10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SwiftColors.ink,
          side: const BorderSide(color: SwiftColors.border),
          padding: EdgeInsets.symmetric(
            horizontal: desktop ? 12 : 14,
            vertical: desktop ? 10 : 12,
          ),
          textStyle: const TextStyle(
            fontFamily: 'Calibri',
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(desktop ? 6 : 10),
          ),
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
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return SwiftColors.accentSoft;
            }
            return SwiftColors.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return SwiftColors.accent;
            }
            return SwiftColors.muted;
          }),
          side: const WidgetStatePropertyAll(
            BorderSide(color: SwiftColors.border),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: SwiftColors.ink,
        contentTextStyle:
            const TextStyle(fontFamily: 'Calibri', color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(desktop ? 8 : 10),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(desktop ? 10 : 16),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: SwiftColors.border,
        space: 1,
        thickness: 1,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: SwiftColors.ink,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Calibri',
          fontSize: 12,
          color: Colors.white,
        ),
      ),
    );
  }
}
