import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'app_update.dart';

/// Sibling Swift Operations apps advertised from the navigation rail.
class SiblingApp {
  const SiblingApp({
    required this.id,
    required this.name,
    required this.blurb,
    required this.iconAsset,
    required this.githubLatestApi,
    required this.windowsSetupAssets,
    required this.androidApkAssets,
    required this.androidPackageName,
    required this.windowsExeNames,
    required this.windowsInstallFolderNames,
    required this.windowsProductNameHints,
    required this.windowsUninstallAppId,
  });

  final String id;
  final String name;
  final String blurb;
  final String iconAsset;
  final String githubLatestApi;
  final List<String> windowsSetupAssets;
  final List<String> androidApkAssets;
  final String androidPackageName;
  final List<String> windowsExeNames;
  final List<String> windowsInstallFolderNames;
  final List<String> windowsProductNameHints;
  final String windowsUninstallAppId;
}

const siblingStagingTracker = SiblingApp(
  id: 'staging-tracker',
  name: 'Staging & Shipping Log',
  blurb: 'Warehouse staging, shipping log, and tracker.',
  iconAsset: 'assets/images/slst_app_icon.png',
  githubLatestApi: AppConfig.stagingTrackerLatestReleaseApi,
  windowsSetupAssets: [
    AppConfig.stagingTrackerWindowsSetupAsset,
    AppConfig.stagingTrackerWindowsSetupAssetLegacy,
  ],
  androidApkAssets: [
    AppConfig.stagingTrackerAndroidApkAsset,
    'SwiftStagingLog-Android.apk',
  ],
  androidPackageName: AppConfig.stagingTrackerAndroidPackage,
  windowsExeNames: [
    AppConfig.stagingTrackerWindowsExe,
    'slst.exe',
  ],
  windowsInstallFolderNames: [
    'Swift Staging Shipping Log',
    'SLST',
    'SwiftStagingLog',
  ],
  windowsProductNameHints: [
    'Swift Staging',
    'Shipping Log',
    'SwiftStagingLog',
  ],
  windowsUninstallAppId: '{A7C3E9B2-4F11-4D88-9C2A-51A7B6E41D20}_is1',
);

class SiblingAppLaunch {
  const SiblingAppLaunch._({
    required this.launched,
    required this.installed,
    this.status,
  });

  final bool launched;
  final bool installed;
  final String? status;

  factory SiblingAppLaunch.opened() =>
      const SiblingAppLaunch._(launched: true, installed: true);

  factory SiblingAppLaunch.installing(String status) => SiblingAppLaunch._(
        launched: false,
        installed: false,
        status: status,
      );
}

/// Candidate install locations for a Windows sibling exe (no I/O).
List<String> windowsSiblingCandidatePaths({
  required SiblingApp app,
  required Map<String, String> env,
}) {
  final sep = Platform.pathSeparator;
  final exeNames = app.windowsExeNames;
  final folders = app.windowsInstallFolderNames;
  final roots = <String>[
    env['LOCALAPPDATA'] ?? '',
    env['PROGRAMFILES'] ?? '',
    env['ProgramFiles'] ?? '',
    env['PROGRAMFILES(X86)'] ?? '',
    env['ProgramFiles(x86)'] ?? '',
    env['PROGRAMDATA'] ?? '',
  ].where((e) => e.isNotEmpty).toSet();

  final out = <String>[];
  void add(String path) {
    if (path.isNotEmpty && !out.contains(path)) out.add(path);
  }

  for (final root in roots) {
    for (final folder in folders) {
      for (final exe in exeNames) {
        add('$root${sep}Programs$sep$folder$sep$exe');
        add('$root$sep$folder$sep$exe');
      }
    }
  }
  return out;
}

/// Detect, launch, or download/install a sibling operations app.
class SiblingAppsService {
  SiblingAppsService({AppUpdateService? updates})
      : _updates = updates ?? const AppUpdateService();

  static const _androidChannel = MethodChannel(
    'com.swiftoilfield.swift_shipping_label/sibling_apps',
  );
  final AppUpdateService _updates;
  String? _cachedWindowsExe;

  Future<bool> isInstalled(SiblingApp app) async {
    if (kIsWeb) return false;
    if (Platform.isWindows) return (await _windowsExePath(app)) != null;
    if (Platform.isAndroid) {
      try {
        final result = await _androidChannel.invokeMethod<bool>(
          'isInstalled',
          {'packageName': app.androidPackageName},
        );
        return result == true;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  Future<SiblingAppLaunch> openOrInstall(
    SiblingApp app, {
    void Function(double progress)? onProgress,
    void Function(String status)? onStatus,
  }) async {
    if (await isInstalled(app)) {
      final ok = await _launch(app);
      if (ok) return SiblingAppLaunch.opened();
      throw Exception('Could not open ${app.name}.');
    }

    onStatus?.call('Downloading ${app.name}…');
    final asset = await _latestInstallAsset(app);
    if (asset == null) {
      throw Exception(
        'No ${Platform.isWindows ? 'Windows' : 'Android'} installer is attached '
        'to the latest ${app.name} release.\n'
        '${AppConfig.stagingTrackerReleasesPage}',
      );
    }

    final file = Platform.isWindows
        ? await _updates.downloadToAppStorage(
            url: asset.url,
            fileName: asset.fileName,
            onProgress: onProgress,
          )
        : await _updates.downloadToTemp(
            url: asset.url,
            fileName: asset.fileName,
            onProgress: onProgress,
          );

    onStatus?.call('Starting installer…');
    await _updates.installDownloadedFile(
      platform: Platform.isWindows
          ? AppUpdatePlatform.windows
          : AppUpdatePlatform.android,
      file: file,
    );
    return SiblingAppLaunch.installing(
      Platform.isWindows
          ? 'Installer launched — finish Setup, then tap again to open.'
          : 'Install prompt opened — after install, tap again to open.',
    );
  }

  Future<bool> _launch(SiblingApp app) async {
    if (Platform.isWindows) {
      final path = await _windowsExePath(app);
      if (path == null) return false;
      await Process.start(
        path,
        const <String>[],
        workingDirectory: File(path).parent.path,
        mode: ProcessStartMode.detached,
      );
      return true;
    }
    if (Platform.isAndroid) {
      try {
        final result = await _androidChannel.invokeMethod<bool>(
          'launch',
          {'packageName': app.androidPackageName},
        );
        return result == true;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  Future<String?> _windowsExePath(SiblingApp app) async {
    if (_cachedWindowsExe != null && File(_cachedWindowsExe!).existsSync()) {
      return _cachedWindowsExe;
    }

    for (final path in windowsSiblingCandidatePaths(
      app: app,
      env: Platform.environment,
    )) {
      if (File(path).existsSync()) {
        _cachedWindowsExe = path;
        return path;
      }
    }

    final fromWhere = await _whereExe(app);
    if (fromWhere != null) {
      _cachedWindowsExe = fromWhere;
      return fromWhere;
    }

    final fromReg = await _registryInstallExe(app);
    if (fromReg != null) {
      _cachedWindowsExe = fromReg;
      return fromReg;
    }

    final fromShortcut = await _startMenuShortcutTarget(app);
    if (fromShortcut != null) {
      _cachedWindowsExe = fromShortcut;
      return fromShortcut;
    }

    return null;
  }

  Future<String?> _whereExe(SiblingApp app) async {
    for (final exe in app.windowsExeNames) {
      try {
        final result = await Process.run('where.exe', [exe]);
        if (result.exitCode != 0) continue;
        final line = '${result.stdout}'.split(RegExp(r'\r?\n')).first.trim();
        if (line.isNotEmpty && File(line).existsSync()) return line;
      } catch (_) {}
    }
    return null;
  }

  Future<String?> _registryInstallExe(SiblingApp app) async {
    final id = app.windowsUninstallAppId;
    final keys = <String>[
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\' + id,
      r'HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\' + id,
      r'HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\' +
          id,
    ];
    for (final key in keys) {
      final location = await _regValue(key, 'InstallLocation');
      if (location == null) continue;
      for (final exe in app.windowsExeNames) {
        final path = File(
          location.endsWith(Platform.pathSeparator)
              ? '$location$exe'
              : '$location${Platform.pathSeparator}$exe',
        );
        if (path.existsSync()) return path.path;
      }
    }

    // Fallback: scan current-user uninstall names.
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall',
      ]);
      if (result.exitCode != 0) return null;
      final lines = '${result.stdout}'.split(RegExp(r'\r?\n'));
      for (final line in lines) {
        final key = line.trim();
        if (!key.toUpperCase().startsWith('HKEY_')) continue;
        final display = await _regValue(key, 'DisplayName');
        if (display == null) continue;
        final lower = display.toLowerCase();
        final hit = app.windowsProductNameHints.any(
          (h) => lower.contains(h.toLowerCase()),
        );
        if (!hit) continue;
        final location = await _regValue(key, 'InstallLocation');
        if (location == null) continue;
        for (final exe in app.windowsExeNames) {
          final path = File(
            location.endsWith(Platform.pathSeparator)
                ? '$location$exe'
                : '$location${Platform.pathSeparator}$exe',
          );
          if (path.existsSync()) return path.path;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _regValue(String key, String name) async {
    try {
      final result = await Process.run('reg', ['query', key, '/v', name]);
      if (result.exitCode != 0) return null;
      final match = RegExp(
        '${RegExp.escape(name)}\\s+REG_\\w+\\s+(.+)\$',
        multiLine: true,
      ).firstMatch('${result.stdout}');
      final value = match?.group(1)?.trim();
      if (value == null || value.isEmpty) return null;
      return value.replaceAll('"', '');
    } catch (_) {
      return null;
    }
  }

  Future<String?> _startMenuShortcutTarget(SiblingApp app) async {
    final env = Platform.environment;
    final roots = <String>[
      if ((env['APPDATA'] ?? '').isNotEmpty)
        '${env['APPDATA']}\\Microsoft\\Windows\\Start Menu\\Programs',
      if ((env['PROGRAMDATA'] ?? '').isNotEmpty)
        '${env['PROGRAMDATA']}\\Microsoft\\Windows\\Start Menu\\Programs',
    ];
    for (final root in roots) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final name = entity.path.toLowerCase();
          if (!name.endsWith('.lnk')) continue;
          final hit = app.windowsProductNameHints.any(
            (h) => name.contains(h.toLowerCase()),
          );
          if (!hit) continue;
          final target = await _resolveShortcut(entity.path);
          if (target != null && File(target).existsSync()) return target;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<String?> _resolveShortcut(String lnkPath) async {
    try {
      final script =
          r'(New-Object -ComObject WScript.Shell).CreateShortcut($env:LNK).TargetPath';
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-Command', script],
        environment: {...Platform.environment, 'LNK': lnkPath},
      );
      if (result.exitCode != 0) return null;
      final target = '${result.stdout}'.trim();
      if (target.toLowerCase().endsWith('.exe') && File(target).existsSync()) {
        return target;
      }
    } catch (_) {}
    return null;
  }

  Future<({String url, String fileName})?> _latestInstallAsset(
    SiblingApp app,
  ) async {
    final client = http.Client();
    try {
      final res = await client.get(
        Uri.parse(app.githubLatestApi),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'SwiftDocumentGenerator',
        },
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(
          'Could not reach ${app.name} releases (${res.statusCode}).',
        );
      }
      final body = jsonDecode(res.body);
      if (body is! Map) return null;
      final assets = body['assets'];
      if (assets is! List) return null;

      final preferred = Platform.isWindows
          ? app.windowsSetupAssets.map((e) => e.toLowerCase()).toSet()
          : app.androidApkAssets.map((e) => e.toLowerCase()).toSet();

      ({String url, String fileName})? fallback;
      for (final raw in assets) {
        if (raw is! Map) continue;
        final name = '${raw['name'] ?? ''}'.trim();
        final url = '${raw['browser_download_url'] ?? ''}'.trim();
        if (name.isEmpty || url.isEmpty) continue;
        final lower = name.toLowerCase();
        if (preferred.contains(lower)) {
          return (url: url, fileName: name);
        }
        if (Platform.isWindows &&
            lower.endsWith('.exe') &&
            lower.contains('setup') &&
            !lower.contains('wear')) {
          fallback ??= (url: url, fileName: name);
        }
        if (Platform.isAndroid &&
            lower.endsWith('.apk') &&
            !lower.contains('wear') &&
            (lower.contains('android') || lower.contains('slst'))) {
          fallback ??= (url: url, fileName: name);
        }
      }
      return fallback;
    } finally {
      client.close();
    }
  }
}
