import "dart:convert";
import "package:flutter_test/flutter_test.dart";
import "package:swift_shipping_label/logo_finder.dart";

void main() {
  test("picker returns up to 30", () async {
    expect(LogoFinder.pickerMaxResults, 30);
    final finder = LogoFinder();
    for (final name in ["Shell", "ATCO", "EPCOR"]) {
      final raw = await finder.findDownloadedCandidates(
        companyName: name,
        domain: "",
        engine: LogoSearchEngine.all,
      );
      final picked = LogoFinder.filterForPicker(raw);
      // ignore: avoid_print
      print(jsonEncode({
        "company": name,
        "raw": raw.length,
        "picker": picked.length,
        "cap": LogoFinder.pickerMaxResults,
      }));
      expect(picked.length, lessThanOrEqualTo(LogoFinder.pickerMaxResults));
      expect(picked.isNotEmpty, isTrue);
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
