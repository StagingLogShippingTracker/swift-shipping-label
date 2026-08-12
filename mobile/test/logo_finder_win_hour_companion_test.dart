import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/logo_finder.dart';

/// Companion live crawl for Windows Find-logo hour QA (all 12 companies).
/// Run from mobile/: flutter test test/logo_finder_win_hour_companion_test.dart
void main() {
  test('companion Find logo for Windows hour QA companies', () async {
    final companies = <String>[
      'Mastec Purnell',
      'Shell',
      'Flint Energy',
      'Strike Group',
      '5Blue Process Equipment',
      'ATCO',
      'Arc Resources LTD',
      'CDE Engineering LTD',
      'EPCOR',
      'DNOW',
      'Comco',
      'Apex Valves',
    ];

    final finder = LogoFinder();
    final outRoot = Directory('../qa_logs/win_logo_hour');
    final imgDir = Directory('${outRoot.path}/images');
    if (!imgDir.existsSync()) imgDir.createSync(recursive: true);

    final report = <Map<String, Object?>>[];
    final roundTag = Platform.environment['QA_ROUND'] ?? 'companion';

    for (final name in companies) {
      final sw = Stopwatch()..start();
      Object? err;
      var count = 0;
      final tops = <Map<String, Object?>>[];
      try {
        final results = await finder.findDownloadedCandidates(
          companyName: name,
          domain: '',
          engine: LogoSearchEngine.all,
        );
        count = results.length;
        final safe = name
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
            .replaceAll(RegExp(r'^_|_$'), '');
        for (var i = 0; i < results.length && i < 4; i++) {
          final r = results[i];
          final ext = LogoFinder.extensionForBytes(r.bytes);
          final path =
              '${imgDir.path}/${roundTag}_${safe}_$i$ext';
          File(path).writeAsBytesSync(r.bytes);
          tops.add({
            'score': r.score,
            'source': r.source,
            'url': r.url,
            'bytes': r.bytes.length,
            'path': path,
            'hint': r.hint,
          });
        }
      } catch (e) {
        err = e;
      }
      sw.stop();
      final entry = {
        'company': name,
        'ok': err == null && count > 0,
        'count': count,
        'ms': sw.elapsedMilliseconds,
        'error': err?.toString(),
        'top': tops,
      };
      report.add(entry);
      // ignore: avoid_print
      print(jsonEncode(entry));
    }

    final out = File('${outRoot.path}/companion_$roundTag.json');
    out.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    // ignore: avoid_print
    print('Wrote ${out.path}');
    expect(report, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
