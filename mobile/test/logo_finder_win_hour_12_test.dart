import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/logo_finder.dart';

/// Mirrors Windows Receiving-label "Find logo on the web" (All sources).
/// Secondary to GUI automation; used to dump tops while the exe is exercised.
void main() {
  test('live Find logo — 12 customers (Windows hour QA companion)', () async {
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

    final root = Directory.current.path.contains('${Platform.pathSeparator}mobile')
        ? Directory.current.parent.path
        : Directory.current.path;
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '');
    final outDir = Directory('$root${Platform.pathSeparator}qa_logs'
        '${Platform.pathSeparator}win_logo_hour'
        '${Platform.pathSeparator}images_$stamp');
    outDir.createSync(recursive: true);

    final finder = LogoFinder();
    final summary = <Map<String, dynamic>>[];

    for (final name in companies) {
      final sw = Stopwatch()..start();
      Object? err;
      var count = 0;
      final tops = <Map<String, dynamic>>[];
      try {
        final raw = await finder.findDownloadedCandidates(
          companyName: name,
          domain: '',
          engine: LogoSearchEngine.all,
        );
        final candidates = LogoFinder.filterForPicker(raw);
        count = candidates.length;
        final folder = Directory(
          '${outDir.path}${Platform.pathSeparator}'
          '${name.replaceAll(RegExp(r"[^A-Za-z0-9]+"), "_")}',
        );
        folder.createSync(recursive: true);
        for (var i = 0; i < candidates.length && i < 6; i++) {
          final c = candidates[i];
          final ext = LogoFinder.extensionForBytes(c.bytes);
          final file = File('${folder.path}${Platform.pathSeparator}$i$ext');
          await file.writeAsBytes(c.bytes);
          tops.add({
            'i': i,
            'source': c.source,
            'score': c.score,
            'url': c.url,
            'bytes': c.bytes.length,
            'file': file.path,
          });
        }
      } catch (e) {
        err = e;
      }
      sw.stop();
      final row = {
        'company': name,
        'ms': sw.elapsedMilliseconds,
        'count': count,
        'error': err?.toString(),
        'tops': tops,
      };
      summary.add(row);
      // ignore: avoid_print
      print(jsonEncode(row));
    }

    final jsonPath =
        '${outDir.parent.path}${Platform.pathSeparator}companion_$stamp.json';
    File(jsonPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'started': DateTime.now().toIso8601String(),
        'companies': summary,
      }),
    );
    // ignore: avoid_print
    print('Wrote $jsonPath');
    expect(summary.every((r) => (r['count'] as int) > 0), isTrue);
  }, timeout: const Timeout(Duration(minutes: 25)));
}
