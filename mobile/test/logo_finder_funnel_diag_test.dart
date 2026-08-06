import "dart:convert";
import "package:flutter_test/flutter_test.dart";
import "package:swift_shipping_label/logo_finder.dart";

void main() {
  test("diagnose candidate funnel", () async {
    final finder = LogoFinder();
    // Use public debug hooks where available + full find
    for (final name in ["Shell", "ATCO", "Arc Resources LTD", "EPCOR"]) {
      final sw = Stopwatch()..start();
      final raw = await finder.findDownloadedCandidates(
        companyName: name,
        domain: "",
        engine: LogoSearchEngine.all,
      );
      final picked = LogoFinder.filterForPicker(raw);
      final bySource = <String, int>{};
      for (final c in picked) {
        final s = c.source.split(" · ").first.split(" (").first;
        bySource[s] = (bySource[s] ?? 0) + 1;
      }
      // ignore: avoid_print
      final hitTarget = picked.length >= LogoFinder.pickerMaxResults;
      // ignore: avoid_print
      print(jsonEncode({
        "company": name,
        "ms": sw.elapsedMilliseconds,
        "raw": raw.length,
        "picker": picked.length,
        "target": LogoFinder.pickerMaxResults,
        "hitTarget": hitTarget,
        "bySource": bySource,
        "topSources": picked.take(8).map((c) => c.source).toList(),
      }));
      // Soft assert: after Bing scoring fix we expect a much fuller picker.
      expect(picked.length, greaterThanOrEqualTo(12),
          reason: "$name picker too sparse (${picked.length})");
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
