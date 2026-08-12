/// Web-safe brand tokens (mirrors production `theme.dart` without dart:io).
import 'package:flutter/material.dart';

class SwiftColors {
  static const accent = Color(0xFFCE4E30);
  static const accentSoft = Color(0xFFF8EBE7);
  static const bg = Color(0xFFF4F2EF);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1A1A1A);
  static const muted = Color(0xFF6B6B6B);
  static const border = Color(0xFFE6E2DC);
  static const panel = Color(0xFFF7F5F2);
  static const railSelected = Color(0xFFF3E4DF);
  static const inputFill = Color(0xFFFAFAF8);

  static const darkBg = Color(0xFF121417);
  static const darkSurface = Color(0xFF1C1F24);
  static const darkPanel = Color(0xFF16191E);
  static const darkInk = Color(0xFFF2F0EC);
  static const darkMuted = Color(0xFFA3A29C);
  static const darkBorder = Color(0xFF2E333A);
  static const darkAccentSoft = Color(0xFF3A221C);
  static const darkRailSelected = Color(0xFF4A2A22);
  static const darkInputFill = Color(0xFF15181C);
}

class SwiftChrome {
  const SwiftChrome({
    required this.bg,
    required this.surface,
    required this.panel,
    required this.ink,
    required this.muted,
    required this.border,
    required this.accentSoft,
    required this.railSelected,
    required this.inputFill,
  });

  final Color bg;
  final Color surface;
  final Color panel;
  final Color ink;
  final Color muted;
  final Color border;
  final Color accentSoft;
  final Color railSelected;
  final Color inputFill;

  factory SwiftChrome.of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SwiftChrome(
      bg: dark ? SwiftColors.darkBg : SwiftColors.bg,
      surface: dark ? SwiftColors.darkSurface : SwiftColors.surface,
      panel: dark ? SwiftColors.darkPanel : SwiftColors.panel,
      ink: dark ? SwiftColors.darkInk : SwiftColors.ink,
      muted: dark ? SwiftColors.darkMuted : SwiftColors.muted,
      border: dark ? SwiftColors.darkBorder : SwiftColors.border,
      accentSoft: dark ? SwiftColors.darkAccentSoft : SwiftColors.accentSoft,
      railSelected:
          dark ? SwiftColors.darkRailSelected : SwiftColors.railSelected,
      inputFill: dark ? SwiftColors.darkInputFill : SwiftColors.inputFill,
    );
  }
}

ThemeData buildSwiftTheme({required bool dark}) {
  final bg = dark ? SwiftColors.darkBg : SwiftColors.bg;
  final surface = dark ? SwiftColors.darkSurface : SwiftColors.surface;
  final ink = dark ? SwiftColors.darkInk : SwiftColors.ink;
  final muted = dark ? SwiftColors.darkMuted : SwiftColors.muted;
  final border = dark ? SwiftColors.darkBorder : SwiftColors.border;
  final panel = dark ? SwiftColors.darkPanel : SwiftColors.panel;
  final inputFill = dark ? SwiftColors.darkInputFill : SwiftColors.inputFill;
  final railSelected =
      dark ? SwiftColors.darkRailSelected : SwiftColors.railSelected;

  final scheme = ColorScheme(
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: SwiftColors.accent,
    onPrimary: Colors.white,
    secondary: SwiftColors.accent,
    onSecondary: Colors.white,
    error: const Color(0xFFB3261E),
    onError: Colors.white,
    surface: surface,
    onSurface: ink,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    fontFamily: 'Helvetica',
    dividerColor: border,
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: inputFill,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: SwiftColors.accent, width: 1.4),
      ),
      labelStyle: TextStyle(color: muted, fontSize: 13),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: SwiftColors.accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: panel,
      selectedIconTheme: const IconThemeData(color: SwiftColors.accent),
      selectedLabelTextStyle: const TextStyle(
        color: SwiftColors.accent,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      unselectedIconTheme: IconThemeData(color: muted),
      unselectedLabelTextStyle: TextStyle(color: muted, fontSize: 12),
      indicatorColor: railSelected,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return SwiftColors.accent;
        return null;
      }),
    ),
  );
}
