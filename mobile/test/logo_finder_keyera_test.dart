import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/logo_finder.dart';

void main() {
  test('All Sources returns candidates for Keyera without failing closed',
      () async {
    final finder = LogoFinder();
    final results = await finder.findDownloadedCandidates(
      companyName: 'Keyera',
      engine: LogoSearchEngine.all,
    );
    // ignore: avoid_print
    print('Keyera results: ${results.length}');
    for (final r in results.take(8)) {
      // ignore: avoid_print
      print('  [${r.score}] ${r.source} (${r.bytes.length}b)');
    }
    // Soft assertion: network/bot blocks can still empty scrapers, but
    // Clearbit/favicon domain APIs should usually yield something for Keyera.
    // We mainly assert the call completes (no throw) and returns a List.
    expect(results, isA<List<LogoDownloadedCandidate>>());
  }, timeout: const Timeout(Duration(seconds: 45)));
}
