import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/logo_finder.dart';

/// Live multi-company logo crawl used for iterative QA.
/// Run: flutter test test/logo_finder_live_hour_test.dart
void main() {
  test('live Receiving-label style Find logo for five customers', () async {
    final companies = <(String name, String domain)>[
      ('Mastec Purnell', 'mastec.com'),
      ('Shell', 'shell.com'),
      ('Flint Energy', ''),
      ('Strike Group', ''),
      ('5Blue Process Equipment', ''),
    ];

    final finder = LogoFinder();
    final report = <Map<String, Object?>>[];

    for (final (name, domain) in companies) {
      final sw = Stopwatch()..start();
      Object? err;
      var count = 0;
      final sources = <String>[];
      try {
        final results = await finder.findDownloadedCandidates(
          companyName: name,
          domain: domain,
          engine: LogoSearchEngine.all,
        );
        count = results.length;
        for (final r in results.take(8)) {
          sources.add('[${r.score}] ${r.source} (${r.bytes.length}b)');
        }
      } catch (e) {
        err = e;
      }
      sw.stop();
      final entry = {
        'company': name,
        'domain': domain,
        'ok': err == null && count > 0,
        'count': count,
        'ms': sw.elapsedMilliseconds,
        'error': err?.toString(),
        'top': sources,
      };
      report.add(entry);
      // ignore: avoid_print
      print(jsonEncode(entry));
    }

    final outDir = Directory('../qa_logs');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    final out = File('../qa_logs/logo_live_round.json');
    out.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    // ignore: avoid_print
    print('Wrote ${out.path}');

    // Soft: do not fail the suite hard — we iterate fixes from the JSON report.
    expect(report, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 8)));
}
