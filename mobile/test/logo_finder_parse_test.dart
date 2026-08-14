import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/logo_finder.dart';

void main() {
  group('Logo crawler parse helpers (via public search APIs)', () {
    test('All Sources completes without throwing when engines fail independently',
        () async {
      final finder = LogoFinder();
      final results = await finder.findDownloadedCandidates(
        companyName: 'Swift Oilfield Supply',
        engine: LogoSearchEngine.all,
      );
      expect(results, isA<List<LogoDownloadedCandidate>>());
      // Soft: domain APIs / favicons usually yield at least one candidate.
      // Network blocks must not throw or fail-closed the whole All Sources call.
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('Serper-only isolates failures (including missing API key)', () async {
      final finder = LogoFinder();
      final serper = await finder.findDownloadedCandidates(
        companyName: 'Keyera',
        engine: LogoSearchEngine.serper,
      );
      expect(serper, isA<List<LogoDownloadedCandidate>>());
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
