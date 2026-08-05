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

    test('Google-only and Bing-only each isolate failures', () async {
      final finder = LogoFinder();
      final google = await finder.findDownloadedCandidates(
        companyName: 'Keyera',
        engine: LogoSearchEngine.google,
      );
      final bing = await finder.findDownloadedCandidates(
        companyName: 'Keyera',
        engine: LogoSearchEngine.bing,
      );
      expect(google, isA<List<LogoDownloadedCandidate>>());
      expect(bing, isA<List<LogoDownloadedCandidate>>());
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
