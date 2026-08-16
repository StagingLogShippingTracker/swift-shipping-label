import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'app_snack.dart';
import 'sibling_apps.dart';
import 'theme.dart';

/// Navigation-rail footer that advertises sibling Swift Operations apps.
class OperationsAppsRail extends StatefulWidget {
  const OperationsAppsRail({super.key, this.compact = false});

  final bool compact;

  @override
  State<OperationsAppsRail> createState() => _OperationsAppsRailState();
}

class _OperationsAppsRailState extends State<OperationsAppsRail> {
  final _svc = SiblingAppsService();
  bool _busy = false;
  double? _progress;
  String? _status;

  bool get _supported {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isAndroid;
  }

  Future<void> _open(SiblingApp app) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = null;
      _status = null;
    });
    try {
      final result = await _svc.openOrInstall(
        app,
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            _progress = p;
            _status = p >= 1.0
                ? 'Starting installer…'
                : 'Downloading… ${(p * 100).round()}%';
          });
        },
        onStatus: (s) {
          if (!mounted) return;
          setState(() => _status = s);
        },
      );
      if (!mounted) return;
      final message = result.launched
          ? 'Opened ${app.name}.'
          : (result.status ?? 'Installer started.');
      showAppSnack(context, message);
      setState(() => _status = result.launched ? null : result.status);
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const SizedBox.shrink();
    final chrome = SwiftChromeColors.of(context);
    final app = siblingStagingTracker;
    if (widget.compact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Tooltip(
          message: '${app.name}\n${app.blurb}',
          child: InkWell(
            onTap: _busy ? null : () => _open(app),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: _busy
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.asset(
                        app.iconAsset,
                        width: 28,
                        height: 28,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'OPERATIONS APPS',
            style: TextStyle(
              fontFamily: 'Oswald',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              color: SwiftColors.accent,
            ),
          ),
          const SizedBox(height: 8),
          Material(
            color: chrome.surface,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _busy ? null : () => _open(app),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.asset(
                            app.iconAsset,
                            width: 32,
                            height: 32,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                app.name,
                                style: TextStyle(
                                  fontFamily: 'Oswald',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: chrome.ink,
                                  height: 1.15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                app.blurb,
                                style: TextStyle(
                                  fontSize: 10,
                                  height: 1.25,
                                  color: chrome.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_busy) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _progress,
                        minHeight: 3,
                        color: SwiftColors.accent,
                      ),
                      if (_status != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _status!,
                          style: TextStyle(fontSize: 10, color: chrome.muted),
                        ),
                      ],
                    ] else if (_status != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _status!,
                        style: TextStyle(fontSize: 10, color: chrome.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
