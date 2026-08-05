import 'package:flutter/material.dart';

import 'app_storage.dart';

/// App-level theme + UI settings (Windows dark mode persists here).
class AppThemeScope extends InheritedNotifier<ValueNotifier<AppUiSettings>> {
  const AppThemeScope({
    super.key,
    required ValueNotifier<AppUiSettings> notifier,
    required super.child,
  }) : super(notifier: notifier);

  static ValueNotifier<AppUiSettings> of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    assert(scope != null, 'AppThemeScope not found');
    return scope!.notifier!;
  }

  static AppUiSettings settingsOf(BuildContext context) => of(context).value;
}
