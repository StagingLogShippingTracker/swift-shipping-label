import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import 'app_storage.dart';
import 'theme.dart';

/// In-app "What's new" prompt for the first [maxShows] launches of a campaign.
///
/// Campaign [campaignId] covers changes from v1.1.68 through v1.1.74.
class AppChangelog {
  AppChangelog._();

  /// Bump this when starting a new What's New wave.
  static const campaignId = 'whats_new_1_1_74';
  static const maxShows = 3;
  static const title = "What's new (v1.1.68 – v1.1.74)";

  /// Ordered newest-first sections shown in the dialog.
  static const sections = <ChangelogSection>[
    ChangelogSection(
      version: 'v1.1.74',
      bullets: [
        'Delivery Address book lists Z–A by Ship To Name; duplicate places merge in the cloud',
        'History opens the PDF (and logo) for that version, not the first generate for the same SO',
      ],
    ),
    ChangelogSection(
      version: 'v1.1.73',
      bullets: [
        'Logo search uses Serper.dev (plus Clearbit/Brandfetch) instead of scraping Google/Bing',
        'Checkbox: convert a low-resolution customer photo to high-resolution',
        'Shipping/Receiving: template prompt only after entering the customer name, not on Generate',
        'Generated document history auto-deletes after 90 days (app + Supabase)',
      ],
    ),
    ChangelogSection(
      version: 'v1.1.72',
      bullets: [
        'Customer logos: optional “Convert low-resolution photo to high-resolution” (RealESRGAN)',
        'Removed Recreate / vectorizer (no SVG tracing). Check the box to upscale low-res logos',
        'Logo restore spinner while Fly.io processes the image',
      ],
    ),
    ChangelogSection(
      version: 'v1.1.71',
      bullets: [
        'Bulk OA: detect “CPO LINE …” notes and loose “part # …” identities',
        'Bulk OA: if PART#/TAG# missing, use the note line under CPO',
        'Shipping/Receiving: template prompt when leaving the Customer field',
        'Looser customer-name matching for templates (Arc / Rite-Way variants)',
        'Android: denser landscape layout; Edit logo crop options no longer wrap vertically',
      ],
    ),
    ChangelogSection(
      version: 'v1.1.70',
      bullets: [
        'Android portrait: smoother Chrome-like header hide/show while scrolling',
        'Android: header auto-hide disabled on Bulk (short page)',
        'Android landscape: Windows-style rail + form + workspace layout',
        'Portrait Android layout unchanged aside from the smoother chrome transition',
      ],
    ),
    ChangelogSection(
      version: 'v1.1.69',
      bullets: [
        'Customer templates: prompt to apply Full, Core only, or Logos only',
        'Shared Delivery Address book for Shipping and BOL',
        'BOL → optional Shipping Labels in the same PDF',
        'Shipping freight / 3rd-party billing + Carrier ↔ ATTN PDF layout',
        'Blank piece counts treated as 0',
        'Per-kind History with cloud PDF storage and local cache',
        'Shared contact memory (Document Generator only — not SLST roster)',
        'Solid orange chrome logo in the app UI',
        'Android dark mode: Update sheet contrast fix',
      ],
    ),
    ChangelogSection(
      version: 'v1.1.68',
      bullets: [
        'Receiving Label: centered values, Sales Order pill at 60 pt (centered)',
        'Receiving Label: no break line under PM',
        'Shipping Label drawing path unchanged',
      ],
    ),
  ];
}

class ChangelogSection {
  const ChangelogSection({required this.version, required this.bullets});

  final String version;
  final List<String> bullets;
}

class ChangelogPromptState {
  const ChangelogPromptState({
    required this.campaignId,
    required this.timesShown,
  });

  final String campaignId;
  final int timesShown;

  factory ChangelogPromptState.fromJson(Map<String, dynamic> json) {
    return ChangelogPromptState(
      campaignId: '${json['campaignId'] ?? ''}'.trim(),
      timesShown: (json['timesShown'] is num)
          ? (json['timesShown'] as num).toInt()
          : int.tryParse('${json['timesShown']}') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'campaignId': campaignId,
        'timesShown': timesShown,
      };
}

extension ChangelogPromptStorage on AppStorage {
  File get changelogPromptFile =>
      File(p.join(root.path, 'changelog_prompt.json'));

  Future<ChangelogPromptState> loadChangelogPromptState() async {
    try {
      final f = changelogPromptFile;
      if (!await f.exists()) {
        return const ChangelogPromptState(campaignId: '', timesShown: 0);
      }
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map) {
        return const ChangelogPromptState(campaignId: '', timesShown: 0);
      }
      return ChangelogPromptState.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return const ChangelogPromptState(campaignId: '', timesShown: 0);
    }
  }

  Future<void> saveChangelogPromptState(ChangelogPromptState state) async {
    await root.create(recursive: true);
    await changelogPromptFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
      flush: true,
    );
  }
}

/// Shows the What's New dialog when this device still has shows remaining.
Future<void> maybeShowChangelogPrompt(BuildContext context, AppStorage storage) async {
  if (!context.mounted) return;

  var state = await storage.loadChangelogPromptState();
  if (state.campaignId != AppChangelog.campaignId) {
    state = const ChangelogPromptState(
      campaignId: AppChangelog.campaignId,
      timesShown: 0,
    );
  }
  if (state.timesShown >= AppChangelog.maxShows) return;

  String versionLabel = '';
  try {
    final info = await PackageInfo.fromPlatform();
    versionLabel = '${info.version}+${info.buildNumber}';
  } catch (_) {}

  if (!context.mounted) return;

  final next = ChangelogPromptState(
    campaignId: AppChangelog.campaignId,
    timesShown: state.timesShown + 1,
  );
  await storage.saveChangelogPromptState(next);

  final remaining = AppChangelog.maxShows - next.timesShown;
  final footer = remaining <= 0
      ? 'This is the last time this summary will appear on this device.'
      : remaining == 1
          ? 'This summary will appear 1 more time on this device.'
          : 'This summary will appear $remaining more times on this device.';

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final chrome = SwiftChromeColors.of(ctx);
      return AlertDialog(
        title: Text(AppChangelog.title),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (versionLabel.isNotEmpty) ...[
                  Text(
                    'Installed: $versionLabel',
                    style: TextStyle(
                      fontSize: 12,
                      color: chrome.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                for (final section in AppChangelog.sections) ...[
                  Text(
                    section.version,
                    style: TextStyle(
                      fontFamily: 'Oswald',
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: SwiftColors.accent,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final bullet in section.bullets)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '•  ',
                            style: TextStyle(color: chrome.ink, height: 1.35),
                          ),
                          Expanded(
                            child: Text(
                              bullet,
                              style: TextStyle(
                                color: chrome.ink,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                Text(
                  footer,
                  style: TextStyle(
                    fontSize: 12,
                    color: chrome.muted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      );
    },
  );
}
