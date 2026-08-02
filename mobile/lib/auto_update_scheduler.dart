import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'app_storage.dart';
import 'app_update.dart';
import 'update_sheet.dart';

/// Daily auto-update check at 3:00 PM America/Denver (MST/MDT).
const _checkHour = 15;
const _checkMinute = 0;
const _denverLocation = 'America/Denver';
const _snoozeDays = 3;

bool _timezonesReady = false;

Future<void> ensureAutoUpdateTimezones() async {
  if (_timezonesReady) return;
  tz_data.initializeTimeZones();
  _timezonesReady = true;
}

tz.Location get _denver => tz.getLocation(_denverLocation);

tz.TZDateTime _nowDenver() => tz.TZDateTime.now(_denver);

String _denverDateKey(tz.TZDateTime dt) {
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '${dt.year}-$m-$d';
}

bool _isPastCheckTimeToday(tz.TZDateTime now) {
  final checkAt = tz.TZDateTime(
    _denver,
    now.year,
    now.month,
    now.day,
    _checkHour,
    _checkMinute,
  );
  return !now.isBefore(checkAt);
}

/// Three calendar days later at 3:00 PM Denver.
tz.TZDateTime _snoozeUntilFromNow() {
  final now = _nowDenver();
  final base = tz.TZDateTime(
    _denver,
    now.year,
    now.month,
    now.day,
    _checkHour,
    _checkMinute,
  );
  return base.add(const Duration(days: _snoozeDays));
}

AppUpdatePlatform get _platform {
  if (Platform.isAndroid) return AppUpdatePlatform.android;
  return AppUpdatePlatform.windows;
}

/// Persists only scheduling/snooze state — never a cached release version.
class AutoUpdateScheduleStore {
  AutoUpdateScheduleStore(this._file);

  final File _file;

  String? lastAutoUpdateCheckDate;
  String? updateSnoozeUntil;

  bool get isSnoozed {
    final raw = updateSnoozeUntil;
    if (raw == null || raw.isEmpty) return false;
    final until = DateTime.tryParse(raw)?.toUtc();
    if (until == null) return false;
    return DateTime.now().toUtc().isBefore(until);
  }

  bool get shouldRunAutoCheck {
    if (kIsWeb) return false;
    if (!Platform.isWindows && !Platform.isAndroid) return false;
    if (isSnoozed) return false;

    final now = _nowDenver();
    if (!_isPastCheckTimeToday(now)) return false;

    final today = _denverDateKey(now);
    return lastAutoUpdateCheckDate != today;
  }

  Future<void> load() async {
    lastAutoUpdateCheckDate = null;
    updateSnoozeUntil = null;
    if (!await _file.exists()) return;
    try {
      final data = jsonDecode(await _file.readAsString());
      if (data is! Map<String, dynamic>) return;
      lastAutoUpdateCheckDate =
          '${data['lastAutoUpdateCheckDate'] ?? ''}'.trim();
      if (lastAutoUpdateCheckDate!.isEmpty) lastAutoUpdateCheckDate = null;
      updateSnoozeUntil = '${data['updateSnoozeUntil'] ?? ''}'.trim();
      if (updateSnoozeUntil!.isEmpty) updateSnoozeUntil = null;
    } catch (_) {
      lastAutoUpdateCheckDate = null;
      updateSnoozeUntil = null;
    }
  }

  Future<void> _save() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        if (lastAutoUpdateCheckDate != null)
          'lastAutoUpdateCheckDate': lastAutoUpdateCheckDate,
        if (updateSnoozeUntil != null) 'updateSnoozeUntil': updateSnoozeUntil,
      }),
    );
  }

  Future<void> markCheckDoneForToday() async {
    lastAutoUpdateCheckDate = _denverDateKey(_nowDenver());
    await _save();
  }

  Future<void> snoozeForThreeDays() async {
    updateSnoozeUntil = _snoozeUntilFromNow().toUtc().toIso8601String();
    await _save();
  }
}

/// Host widget: periodic timer + lifecycle resume → fresh GitHub latest check.
class AutoUpdateHost extends StatefulWidget {
  const AutoUpdateHost({
    super.key,
    required this.storage,
    required this.child,
  });

  final AppStorage storage;
  final Widget child;

  @override
  State<AutoUpdateHost> createState() => _AutoUpdateHostState();
}

class _AutoUpdateHostState extends State<AutoUpdateHost>
    with WidgetsBindingObserver {
  static const _svc = AppUpdateService();

  late final AutoUpdateScheduleStore _store;
  Timer? _timer;
  bool _checking = false;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store = AutoUpdateScheduleStore(widget.storage.updateScheduleFile);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await ensureAutoUpdateTimezones();
    await _store.load();
    if (!mounted) return;
    unawaited(_maybeRunAutoCheck());
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_maybeRunAutoCheck()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reloadAndMaybeCheck());
    }
  }

  Future<void> _reloadAndMaybeCheck() async {
    await _store.load();
    await _maybeRunAutoCheck();
  }

  Future<void> _maybeRunAutoCheck() async {
    if (!mounted || _checking || _dialogOpen) return;
    if (!_store.shouldRunAutoCheck) return;

    _checking = true;
    try {
      final info = await PackageInfo.fromPlatform();
      // Always fetch releases/latest — never reuse a prior offered version.
      final result = await _svc.checkForUpdate(
        installedVersion: info.version,
        installedBuild: info.buildNumber,
        platform: _platform,
      );

      if (!mounted) return;

      await _store.markCheckDoneForToday();

      if (!result.updateAvailable) return;

      await _showUpdateDialog(result.latest, info);
    } catch (_) {
      // Silent on auto-check failures; retry on next resume or 3pm window.
    } finally {
      _checking = false;
    }
  }

  Future<void> _showUpdateDialog(
    AppReleaseInfo release,
    PackageInfo installed,
  ) async {
    if (!mounted || _dialogOpen) return;
    _dialogOpen = true;

    final versionLabel =
        release.name.isEmpty ? release.tagName : release.name;
    final platform = _platform;

    final action = await showDialog<_AutoPromptAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Update available'),
        content: Text(
          'A newer version is available: $versionLabel\n\n'
          'Installed: ${installed.version}+${installed.buildNumber}\n'
          'Latest: ${release.tagName}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_AutoPromptAction.later),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_AutoPromptAction.update),
            child: const Text('Update'),
          ),
        ],
      ),
    );

    _dialogOpen = false;
    if (!mounted) return;

    switch (action) {
      case _AutoPromptAction.update:
        await installReleaseUpdate(context, release, platform: platform);
      case _AutoPromptAction.later:
        await _store.snoozeForThreeDays();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum _AutoPromptAction { update, later }
