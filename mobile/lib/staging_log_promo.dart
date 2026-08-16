import 'package:flutter/material.dart';

import 'app_snack.dart';
import 'app_storage.dart';
import 'changelog.dart';
import 'sibling_apps.dart';
import 'theme.dart';

const slstPromoIconAsset = 'assets/images/slst_app_icon.png';

const slstPromoStills = <String>[
  'assets/images/slst_still_dashboard.png',
  'assets/images/slst_still_staging.png',
  'assets/images/slst_still_warehouse.png',
  'assets/images/slst_still_shipped.png',
];

/// Warehouse-floor promo for Staging & Shipping Log (same 3-launch window
/// as What's New). Shown before the changelog dialog.
Future<void> showStagingLogPromoDialog(BuildContext context) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => const _StagingLogPromoDialog(),
  );
}

class _StagingLogPromoDialog extends StatefulWidget {
  const _StagingLogPromoDialog();

  @override
  State<_StagingLogPromoDialog> createState() => _StagingLogPromoDialogState();
}

class _StagingLogPromoDialogState extends State<_StagingLogPromoDialog> {
  final _svc = SiblingAppsService();
  bool _busy = false;
  double? _progress;
  String? _status;

  Future<void> _tryToday() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = null;
      _status = null;
    });
    final app = siblingStagingTracker;
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
      if (result.launched && context.mounted) {
        Navigator.of(context).pop();
      } else {
        setState(() => _status = result.launched ? null : result.status);
      }
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
    final size = MediaQuery.sizeOf(context);
    final maxW = size.width < 720 ? size.width - 28 : 560.0;
    final maxH = size.height * 0.88;

    return Dialog(
      backgroundColor: SwiftColors.darkSurface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: SwiftColors.darkBorder),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset(
                            slstPromoIconAsset,
                            width: 88,
                            height: 88,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'NEW FOR STAFF',
                                style: TextStyle(
                                  fontFamily: 'Oswald',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  letterSpacing: 1.4,
                                  color: SwiftColors.accent,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Swift Staging & Shipping Log',
                                style: TextStyle(
                                  fontFamily: 'Oswald',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 22,
                                  height: 1.15,
                                  color: SwiftColors.darkInk,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'The warehouse floor book for Swift operations — released '
                      'to staff today. It tracks what is sitting in staging, '
                      'when it should ship, and what already left, then keeps '
                      'live warehouse ops in one place.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: SwiftColors.darkInk,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const _PromoBullet(
                      title: 'Dashboard',
                      body:
                          'KPI cards and the staging board: rush, today, tomorrow, '
                          'partial, pickups, awaiting — plus a live warehouse floor map.',
                    ),
                    const _PromoBullet(
                      title: 'Active staging',
                      body:
                          'Add floor entries, set aisle/bin location, scan documents, '
                          'consolidate or split lines, then ship when freight leaves.',
                    ),
                    const _PromoBullet(
                      title: 'Shipping log',
                      body:
                          'Completed outbound rows with carrier, photos, and PM '
                          'notification — the book matches what left the dock.',
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: size.height < 700 ? 132 : 168,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: slstPromoStills.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, i) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: AspectRatio(
                              aspectRatio: 16 / 10,
                              child: Image.asset(
                                slstPromoStills[i],
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (_busy || _status != null) ...[
                      const SizedBox(height: 12),
                      if (_busy)
                        LinearProgressIndicator(
                          value: _progress,
                          minHeight: 3,
                          color: SwiftColors.accent,
                          backgroundColor: SwiftColors.darkBorder,
                        ),
                      if (_status != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _status!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: SwiftColors.darkMuted,
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      'Dismiss closes this until the next launch. It can appear '
                      'up to three times for this update — same window as What’s new.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: SwiftColors.darkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text(
                      'Dismiss',
                      style: TextStyle(color: SwiftColors.darkMuted),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _busy ? null : _tryToday,
                    child: Text(_busy ? 'Working…' : 'Try it today'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromoBullet extends StatelessWidget {
  const _PromoBullet({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: SwiftColors.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: SwiftColors.darkInk,
                ),
                children: [
                  TextSpan(
                    text: '$title. ',
                    style: const TextStyle(
                      fontFamily: 'Oswald',
                      fontWeight: FontWeight.w600,
                      color: SwiftColors.accentOn,
                    ),
                  ),
                  TextSpan(text: body),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Changelog + Staging Log promo for the first [AppChangelog.maxShows] launches
/// of this campaign. Promo is shown first; dismiss does not skip later launches.
Future<void> maybeShowLaunchPrompts(
  BuildContext context,
  AppStorage storage,
) async {
  if (!context.mounted) return;

  var state = await storage.loadChangelogPromptState();
  if (state.campaignId != AppChangelog.campaignId) {
    state = const ChangelogPromptState(
      campaignId: AppChangelog.campaignId,
      timesShown: 0,
    );
  }
  if (state.timesShown >= AppChangelog.maxShows) return;

  final next = ChangelogPromptState(
    campaignId: AppChangelog.campaignId,
    timesShown: state.timesShown + 1,
  );
  await storage.saveChangelogPromptState(next);

  if (!context.mounted) return;
  await showStagingLogPromoDialog(context);
  if (!context.mounted) return;
  await showChangelogDialog(context, timesShown: next.timesShown);
}
