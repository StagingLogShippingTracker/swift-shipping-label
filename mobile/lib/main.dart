import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_storage.dart';
import 'app_theme_scope.dart';
import 'auto_update_scheduler.dart';
import 'home_screen.dart';
import 'pdf/shipping_label_pdf.dart';
import 'pdf_render_options.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );
  }
  final storage = await AppStorage.open();
  final pdf = await ShippingLabelPdf.load();
  final settings = await storage.loadUiSettings();
  runApp(
    SwiftShippingLabelApp(
      storage: storage,
      pdf: pdf,
      initialSettings: settings,
    ),
  );
}

/// App-level theme + UI settings (Windows dark mode persists via [AppThemeScope]).
class SwiftShippingLabelApp extends StatefulWidget {
  const SwiftShippingLabelApp({
    super.key,
    required this.storage,
    required this.pdf,
    required this.initialSettings,
  });

  final AppStorage storage;
  final ShippingLabelPdf pdf;
  final AppUiSettings initialSettings;

  @override
  State<SwiftShippingLabelApp> createState() => _SwiftShippingLabelAppState();
}

class _SwiftShippingLabelAppState extends State<SwiftShippingLabelApp> {
  late final ValueNotifier<AppUiSettings> _settings =
      ValueNotifier(widget.initialSettings);

  @override
  void dispose() {
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppThemeScope(
      notifier: _settings,
      child: ValueListenableBuilder<AppUiSettings>(
        valueListenable: _settings,
        builder: (context, settings, _) {
          final dark = Platform.isWindows &&
              settings.themePreference == UiThemePreference.dark;
          final scale = Platform.isWindows ? settings.uiFontScale : 1.0;
          return MaterialApp(
            title: 'Swift Document Generator',
            debugShowCheckedModeBanner: false,
            theme: SwiftTheme.light(fontScale: scale),
            darkTheme: SwiftTheme.dark(fontScale: scale),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: AutoUpdateHost(
              storage: widget.storage,
              child: HomeScreen(storage: widget.storage, pdf: widget.pdf),
            ),
          );
        },
      ),
    );
  }
}
