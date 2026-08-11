import 'dart:io';

import 'package:flutter/material.dart';

import 'theme.dart';

/// High-contrast floating pill toast — top of screen (Windows right / Android
/// centered) so it does not stretch across the full width.
void showAppSnack(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 4),
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    appSnackBar(
      context,
      message,
      duration: duration,
      action: action,
    ),
  );
}

SnackBar appSnackBar(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 4),
  SnackBarAction? action,
}) {
  final size = MediaQuery.sizeOf(context);
  final pad = MediaQuery.paddingOf(context);
  // Below Windows menu + toolbar; under status bar on Android.
  final top = pad.top + (Platform.isWindows ? 52.0 : 10.0);
  const pillH = 58.0;
  final bottom = (size.height - top - pillH).clamp(0.0, double.infinity);
  final isWin = Platform.isWindows;
  final dark = Theme.of(context).brightness == Brightness.dark;

  // Solid ink (light) / elevated dark panel — never washed-out grey-on-white.
  final bg = dark ? const Color(0xFF323842) : SwiftColors.ink;
  const fg = Color(0xFFF7F5F2);
  final font = Theme.of(context).textTheme.bodyMedium?.fontFamily;

  return SnackBar(
    behavior: SnackBarBehavior.floating,
    duration: duration,
    dismissDirection: DismissDirection.up,
    elevation: 10,
    backgroundColor: bg,
    action: action == null
        ? null
        : SnackBarAction(
            label: action.label,
            onPressed: action.onPressed,
            textColor: SwiftColors.accentOn,
          ),
    margin: isWin
        ? EdgeInsets.only(
            left: (size.width * 0.48).clamp(180.0, size.width - 320),
            right: 16,
            top: top,
            bottom: bottom,
          )
        : EdgeInsets.only(
            left: 32,
            right: 32,
            top: top,
            bottom: bottom,
          ),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(28),
      side: BorderSide(
        color: dark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.25),
      ),
    ),
    content: Text(
      message,
      textAlign: isWin ? TextAlign.start : TextAlign.center,
      style: TextStyle(
        fontFamily: font,
        color: fg,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: 0.1,
      ),
    ),
  );
}
