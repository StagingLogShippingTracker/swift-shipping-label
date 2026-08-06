// Live smoke for Find-logo: MasTec Purnell source mix + wall-clock.
// Run from mobile/: flutter test test/logo_finder_mastec_purnell_live_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/logo_finder.dart';

void main() {
  test('MasTec Purnell live find reports Google/Bing/site mix', () async {
    final sw = Stopwatch()..start();
    final finder = LogoFinder();
    final raw = await finder.findDownloadedCandidates(
      companyName: 'MasTec Purnell',
      engine: LogoSearchEngine.all,
    );
    final picked = LogoFinder.filterForPicker(raw);
    sw.stop();

    final bySource = <String, int>{};
    for (final c in picked) {
      final src = c.source.split(' · ').first.trim();
      // Collapse "Site scrape (domain)" / "Google Favicon (domain)"
      final key = src.contains('Google')
          ? (src.startsWith('Google Favicon') ? 'Google Favicon' : 'Google Images')
          : src.startsWith('Bing')
              ? 'Bing Images'
              : src.startsWith('Site scrape')
                  ? 'Site scrape'
                  : src.startsWith('Known')
                      ? 'Known brand logo'
                      : src;
      bySource[key] = (bySource[key] ?? 0) + 1;
    }

    // ignore: avoid_print
    print('elapsed_ms=${sw.elapsedMilliseconds}');
    // ignore: avoid_print
    print('picked=${picked.length}');
    // ignore: avoid_print
    print('bySource=$bySource');
    for (final c in picked.take(8)) {
      // ignore: avoid_print
      print('  score=${c.score} src=${c.source} url=${c.url}');
    }

    expect(picked, isNotEmpty);
    expect(sw.elapsedMilliseconds, lessThan(45000),
        reason: 'Find-logo should finish well under the old 40–60s path');

    final google = bySource['Google Images'] ?? 0;
    final bing = bySource['Bing Images'] ?? 0;
    final known = bySource['Known brand logo'] ?? 0;
    final site = bySource['Site scrape'] ?? 0;
    // ignore: avoid_print
    print('google=$google bing=$bing known=$known site=$site');

    // Official MasTec Purnell assets must appear somehow.
    final hasPurnellAsset = picked.any((c) =>
        c.url.toLowerCase().contains('mastecpurnell') ||
        c.url.toLowerCase().contains('logo_mastec_purnell') ||
        c.source.toLowerCase().contains('known'));
    expect(hasPurnellAsset, isTrue,
        reason: 'Expected mastecpurnell / known brand logo among results');
  }, timeout: const Timeout(Duration(seconds: 90)));
}
