import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/logo_finder.dart';

void main() {
  test('Shell logo quality after og:image filter', () async {
    final finder = LogoFinder();
    final results = await finder.findDownloadedCandidates(
      companyName: 'Shell',
      domain: 'shell.com',
      engine: LogoSearchEngine.all,
    );
    final dir = Directory('../qa_logs/logo_hour_images/Shell_recheck')
      ..createSync(recursive: true);
    final summary = <Map<String, Object?>>[];
    for (var i = 0; i < results.length && i < 6; i++) {
      final r = results[i];
      final ext = LogoFinder.extensionForBytes(r.bytes);
      final f = File('${dir.path}/$i$ext');
      await f.writeAsBytes(r.bytes);
      summary.add({
        'i': i,
        'score': r.score,
        'source': r.source,
        'bytes': r.bytes.length,
        'file': f.path,
      });
      // ignore: avoid_print
      print(jsonEncode(summary.last));
    }
    File('../qa_logs/logo_shell_recheck.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
    expect(results, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
