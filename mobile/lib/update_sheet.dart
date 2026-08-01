import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_config.dart';
import 'app_update.dart';
import 'theme.dart';

/// Header / menu Update flow: check GitHub Releases and install APK.
Future<void> showUpdateFlow(BuildContext context) async {
  if (kIsWeb || !Platform.isAndroid) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Update is available on Android builds.')),
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SwiftColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => const _UpdateSheet(),
  );
}

class _UpdateSheet extends StatefulWidget {
  const _UpdateSheet();

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  static const _svc = AppUpdateService();

  PackageInfo? _info;
  AppReleaseInfo? _latest;
  bool _checking = false;
  bool _installing = false;
  double? _progress;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _loadInstalled();
  }

  Future<void> _loadInstalled() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _info = info);
    } catch (_) {}
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
      _status = null;
    });
    try {
      final info = _info ?? await PackageInfo.fromPlatform();
      final result = await _svc.checkForUpdate(
        installedVersion: info.version,
        installedBuild: info.buildNumber,
        platform: AppUpdatePlatform.android,
      );
      if (!mounted) return;
      setState(() {
        _info = info;
        _latest = result.latest;
      });

      if (result.missingPlatformAsset) {
        setState(() {
          _status =
              'Latest ${result.latest.tagName} has no Android APK yet.';
        });
        return;
      }

      if (!result.updateAvailable) {
        setState(() {
          _status =
              'You are up to date (${info.version}+${info.buildNumber}). '
              'Latest is ${result.latest.tagName}.';
        });
        return;
      }

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Update available'),
          content: Text(
            'A newer Android build is available:\n'
            '${result.latest.name.isEmpty ? result.latest.tagName : result.latest.name}\n\n'
            'Package: ${result.latest.assetLabelFor(AppUpdatePlatform.android)}\n'
            'Installed: ${info.version}+${info.buildNumber}\n\n'
            'Download and open the installer?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Yes, update'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      await _downloadAndInstall(result.latest);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _downloadAndInstall(AppReleaseInfo release) async {
    setState(() {
      _installing = true;
      _progress = 0;
      _error = null;
      _status = 'Downloading…';
    });
    try {
      await _svc.downloadAndInstallAndroid(
        release: release,
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            _progress = p;
            _status = p >= 1.0
                ? 'Opening package installer…'
                : 'Downloading… ${(p * 100).round()}%';
          });
        },
      );
      if (!mounted) return;
      setState(() => _status = 'Installer opened — follow on-screen prompts.');
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message ?? e.toString();
        _status = 'Could not open installer. Try View releases.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _installing = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _openReleases() async {
    final uri = Uri.parse(
      (_latest?.htmlUrl.isNotEmpty ?? false)
          ? _latest!.htmlUrl
          : AppConfig.githubReleasesPage,
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final installed = _info == null
        ? '…'
        : '${_info!.version}+${_info!.buildNumber}';
    final busy = _checking || _installing;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: SwiftColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Update',
              style: TextStyle(
                fontFamily: 'Oswald',
                fontWeight: FontWeight.w600,
                fontSize: 18,
                color: SwiftColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Installed: $installed',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Checks GitHub Releases for a newer Android APK and downloads '
              'it into app-private storage.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SwiftColors.muted,
                  ),
            ),
            if (_latest != null) ...[
              const SizedBox(height: 12),
              Text(
                'Latest: ${_latest!.name.isEmpty ? _latest!.tagName : _latest!.name}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (_latest!.tagName.isNotEmpty)
                Text(
                  'Tag ${_latest!.tagName}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
            if (_status != null) ...[
              const SizedBox(height: 10),
              Text(
                _status!,
                style: const TextStyle(
                  color: SwiftColors.accent,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
            if (_progress != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _progress,
                color: SwiftColors.accent,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy ? null : _check,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.system_update_alt, size: 18),
              label: Text(
                _installing
                    ? 'Installing…'
                    : _checking
                        ? 'Checking…'
                        : 'Check for updates',
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _openReleases,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('View releases'),
            ),
          ],
        ),
      ),
    );
  }
}
