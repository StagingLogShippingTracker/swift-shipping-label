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

  // Dark-mode counterparts (Windows View → Dark mode).
  static const darkBg = Color(0xFF121417);
  static const darkSurface = Color(0xFF1C1F24);
  static const darkPanel = Color(0xFF16191E);
  static const darkInk = Color(0xFFF2F0EC);
  static const darkMuted = Color(0xFFA3A29C);
  static const darkBorder = Color(0xFF2E333A);
  static const darkAccentSoft = Color(0xFF3A221C);
  static const darkRailSelected = Color(0xFF4A2A22);
}

class SwiftTheme {
  static ThemeData light({double fontScale = 1.0}) =>
      _build(brightness: Brightness.light, fontScale: fontScale);

  static ThemeData dark({double fontScale = 1.0}) =>
      _build(brightness: Brightness.dark, fontScale: fontScale);

  static ThemeData _build({
    required Brightness brightness,
    required double fontScale,
  }) {
    final desktop = Platform.isWindows;
    final dark = brightness == Brightness.dark;
    final scale = fontScale.clamp(0.85, 1.35);

    final bg = dark ? SwiftColors.darkBg : SwiftColors.bg;
    final surface = dark ? SwiftColors.darkSurface : SwiftColors.surface;
    final ink = dark ? SwiftColors.darkInk : SwiftColors.ink;
    final muted = dark ? SwiftColors.darkMuted : SwiftColors.muted;
    final border = dark ? SwiftColors.darkBorder : SwiftColors.border;
    final accentSoft =
        dark ? SwiftColors.darkAccentSoft : SwiftColors.accentSoft;
    final railSelected =
        dark ? SwiftColors.darkRailSelected : SwiftColors.railSelected;
    final inputFill = dark ? const Color(0xFF15181C) : const Color(0xFFFAFAF8);
    final chromePanel = dark ? SwiftColors.darkPanel : SwiftColors.panel;

    final base = ColorScheme.fromSeed(
      seedColor: SwiftColors.accent,
      primary: SwiftColors.accent,
      surface: surface,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      visualDensity:
          desktop ? VisualDensity.compact : VisualDensity.standard,
      colorScheme: base.copyWith(
        primary: SwiftColors.accent,
        onPrimary: Colors.white,
        surface: surface,
        onSurface: ink,
      ),
      scaffoldBackgroundColor: bg,
      fontFamily: 'Calibri',
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
            fontFamily: 'Calibri',
            bodyColor: ink,
            displayColor: ink,
            fontSizeFactor: scale,
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: desktop
            ? surface
            : (dark ? SwiftColors.darkSurface : SwiftColors.accent),
        foregroundColor: desktop
            ? ink
            : (dark ? SwiftColors.darkInk : Colors.white),
        elevation: 0,
        scrolledUnderElevation: desktop ? 0.5 : 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Oswald',
          fontWeight: FontWeight.w600,
          fontSize: (desktop ? 16 : 20) * scale,
          color: desktop
              ? ink
              : (dark ? SwiftColors.darkInk : Colors.white),
          letterSpacing: 0.4,
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: chromePanel,
        indicatorColor: railSelected,
        selectedIconTheme: const IconThemeData(
          color: SwiftColors.accent,
          size: 22,
        ),
        unselectedIconTheme: IconThemeData(
          color: muted,
          size: 22,
        ),
        selectedLabelTextStyle: TextStyle(
          fontFamily: 'Oswald',
          fontWeight: FontWeight.w600,
          fontSize: 12 * scale,
          color: SwiftColors.accent,
          letterSpacing: 0.3,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontFamily: 'Calibri',
          fontWeight: FontWeight.w600,
          fontSize: 12 * scale,
          color: muted,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(desktop ? 8 : 14),
          side: BorderSide(color: border),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: desktop ? 8 : 10,
        ),
        labelStyle: TextStyle(
          fontFamily: 'Oswald',
          fontSize: 12 * scale,
          fontWeight: FontWeight.w500,
          color: muted,
          letterSpacing: 0.6,
        ),
        floatingLabelStyle: TextStyle(
          fontFamily: 'Oswald',
          fontSize: 12 * scale,
          fontWeight: FontWeight.w600,
          color: SwiftColors.accent,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(desktop ? 6 : 10),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(desktop ? 6 : 10),
          borderSide: BorderSide(color: border),
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
            fontSize: (desktop ? 14 : 15) * scale,
            letterSpacing: 0.4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(desktop ? 6 : 10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: border),
          padding: EdgeInsets.symmetric(
            horizontal: desktop ? 12 : 14,
            vertical: desktop ? 10 : 12,
          ),
          textStyle: TextStyle(
            fontFamily: 'Calibri',
            fontWeight: FontWeight.w600,
            fontSize: 13 * scale,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(desktop ? 6 : 10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: muted,
          textStyle: TextStyle(
            fontFamily: 'Calibri',
            fontWeight: FontWeight.w600,
            fontSize: 13 * scale,
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return accentSoft;
            }
            return surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return SwiftColors.accent;
            }
            return muted;
          }),
          side: WidgetStatePropertyAll(BorderSide(color: border)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? const Color(0xFF2A2E35) : SwiftColors.ink,
        contentTextStyle:
            const TextStyle(fontFamily: 'Calibri', color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(desktop ? 8 : 10),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(desktop ? 10 : 16),
        ),
      ),
      menuBarTheme: MenuBarThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(surface),
          elevation: const WidgetStatePropertyAll(0),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(ink),
          textStyle: WidgetStatePropertyAll(
            TextStyle(
              fontFamily: 'Calibri',
              fontSize: 13 * scale,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: border,
        space: 1,
        thickness: 1,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF2A2E35) : SwiftColors.ink,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Calibri',
          fontSize: 12,
          color: Colors.white,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return SwiftColors.accent;
          }
          return null;
        }),
      ),
      extensions: <ThemeExtension<dynamic>>[
        SwiftChromeColors(
          bg: bg,
          surface: surface,
          panel: chromePanel,
          ink: ink,
          muted: muted,
          border: border,
        ),
      ],
    );
  }
}

/// Runtime chrome colors that flip with light/dark (Windows scaffolds).
class SwiftChromeColors extends ThemeExtension<SwiftChromeColors> {
  const SwiftChromeColors({
    required this.bg,
    required this.surface,
    required this.panel,
    required this.ink,
    required this.muted,
    required this.border,
  });

  final Color bg;
  final Color surface;
  final Color panel;
  final Color ink;
  final Color muted;
  final Color border;

  static SwiftChromeColors of(BuildContext context) {
    return Theme.of(context).extension<SwiftChromeColors>() ??
        const SwiftChromeColors(
          bg: SwiftColors.bg,
          surface: SwiftColors.surface,
          panel: SwiftColors.panel,
          ink: SwiftColors.ink,
          muted: SwiftColors.muted,
          border: SwiftColors.border,
        );
  }

  @override
  SwiftChromeColors copyWith({
    Color? bg,
    Color? surface,
    Color? panel,
    Color? ink,
    Color? muted,
    Color? border,
  }) {
    return SwiftChromeColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      panel: panel ?? this.panel,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      border: border ?? this.border,
    );
  }

  @override
  SwiftChromeColors lerp(ThemeExtension<SwiftChromeColors>? other, double t) {
    if (other is! SwiftChromeColors) return this;
    return SwiftChromeColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
    );
  }
}
