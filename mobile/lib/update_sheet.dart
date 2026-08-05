import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_config.dart';
import 'app_update.dart';
import 'platform_io.dart';
import 'theme.dart';

AppUpdatePlatform get updatePlatform {
  if (Platform.isAndroid) return AppUpdatePlatform.android;
  return AppUpdatePlatform.windows;
}

/// Download and install the given release (used by manual and auto prompts).
Future<void> installReleaseUpdate(
  BuildContext context,
  AppReleaseInfo release, {
  AppUpdatePlatform? platform,
}) async {
  final plat = platform ?? updatePlatform;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _InstallProgressDialog(release: release, platform: plat),
  );
}

class _InstallProgressDialog extends StatefulWidget {
  const _InstallProgressDialog({
    required this.release,
    required this.platform,
  });

  final AppReleaseInfo release;
  final AppUpdatePlatform platform;

  @override
  State<_InstallProgressDialog> createState() => _InstallProgressDialogState();
}

class _InstallProgressDialogState extends State<_InstallProgressDialog> {
  static const _svc = AppUpdateService();

  double? _progress;
  String _status = 'Downloading…';
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      if (widget.platform == AppUpdatePlatform.android) {
        await _svc.downloadAndInstallAndroid(
          release: widget.release,
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
      } else {
        final dir = await _svc.downloadAndExtractWindows(
          release: widget.release,
          onProgress: (p) {
            if (!mounted) return;
            setState(() {
              _progress = p;
              _status = p >= 1.0
                  ? 'Extracting…'
                  : 'Downloading… ${(p * 100).round()}%';
            });
          },
        );
        if (!mounted) return;
        setState(() => _status = 'Update ready — opening folder.');
        await openFolder(dir.path);
      }
      if (mounted) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (mounted) Navigator.of(context).pop();
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message ?? e.toString();
        _status = 'Could not finish update.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Updating…'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_status),
          if (_progress != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _progress,
              color: SwiftColors.accent,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        if (_error != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
      ],
    );
  }
}

/// Header Update control — dialog on Windows, bottom sheet on mobile.
Future<void> showUpdateFlow(BuildContext context) async {
  if (kIsWeb) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Updates are not supported on web.')),
    );
    return;
  }

  if (Platform.isWindows) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: const _UpdateSheet(asDialog: true),
        ),
      ),
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
  const _UpdateSheet({this.asDialog = false});

  final bool asDialog;

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  static const _svc = AppUpdateService();

  PackageInfo? _info;
  AppReleaseInfo? _latest;
  bool _checking = false;
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
      final platform = updatePlatform;
      final result = await _svc.checkForUpdate(
        installedVersion: info.version,
        installedBuild: info.buildNumber,
        platform: platform,
      );
      if (!mounted) return;
      setState(() {
        _info = info;
        _latest = result.latest;
      });

      final assetLabel = result.latest.assetLabelFor(platform) ?? 'release asset';

      if (result.missingPlatformAsset) {
        setState(() {
          _status =
              'Latest ${result.latest.tagName} has no $assetLabel yet.';
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
            'A newer build is available:\n'
            '${result.latest.name.isEmpty ? result.latest.tagName : result.latest.name}\n\n'
            'Package: $assetLabel\n'
            'Installed: ${info.version}+${info.buildNumber}\n\n'
            '${platform == AppUpdatePlatform.android ? 'Download and open the installer?' : 'Download and open the updates folder?'}',
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
      await installReleaseUpdate(context, result.latest, platform: platform);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _checking = false);
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
    final busy = _checking;
    final isAndroid = Platform.isAndroid;
    final asDialog = widget.asDialog;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          asDialog ? 20 : 12,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!asDialog) ...[
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
            ],
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Update',
                    style: TextStyle(
                      fontFamily: 'Oswald',
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                      color: SwiftColors.ink,
                    ),
                  ),
                ),
                if (asDialog)
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                  ),
              ],
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
              isAndroid
                  ? 'Checks GitHub Releases for a newer APK and installs it.'
                  : 'Checks GitHub Releases for a newer Windows build and opens the download folder.',
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
              label: Text(_checking ? 'Checking…' : 'Check for updates'),
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
