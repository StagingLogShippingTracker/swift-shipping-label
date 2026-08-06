import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/logo_finder.dart';

void main() {
  test('save top logos for visual QA', () async {
    final companies = <(String name, String domain)>[
      ('Mastec Purnell', 'mastec.com'),
      ('Shell', 'shell.com'),
      ('Flint Energy', ''),
      ('Strike Group', ''),
      ('5Blue Process Equipment', ''),
    ];
    final outRoot = Directory('../qa_logs/logo_hour_images');
    if (outRoot.existsSync()) {
      outRoot.deleteSync(recursive: true);
    }
    outRoot.createSync(recursive: true);

    final finder = LogoFinder();
    for (final (name, domain) in companies) {
      final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
      final dir = Directory('${outRoot.path}/$safe')..createSync();
      final results = await finder.findDownloadedCandidates(
        companyName: name,
        domain: domain,
        engine: LogoSearchEngine.all,
      );
      // ignore: avoid_print
      print('$name -> ${results.length} results');
      for (var i = 0; i < results.length && i < 4; i++) {
        final r = results[i];
        final ext = LogoFinder.extensionForBytes(r.bytes);
        final f = File('${dir.path}/$i${ext.isEmpty ? '.bin' : ext}');
        await f.writeAsBytes(r.bytes);
        // ignore: avoid_print
        print('  saved ${f.path} [${r.score}] ${r.source}');
      }
    }
    expect(outRoot.listSync(), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
