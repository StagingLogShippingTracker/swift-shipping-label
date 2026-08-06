import "package:flutter_test/flutter_test.dart";
import "package:swift_shipping_label/logo_finder.dart";

void main() {
  test("third-party Bing logo PNGs clear the candidate floor", () {
    const urls = [
      "https://www.pngmart.com/files/23/Shell-Logo-PNG-HD.png",
      "https://logos-world.net/wp-content/uploads/2020/11/Shell-Logo.png",
      "https://cdn.worldvectorlogo.com/logos/shell-2.png",
    ];
    for (final url in urls) {
      final score = LogoFinder.debugScoreUrl(url, "Bing Images", "Shell");
      expect(
        score,
        greaterThanOrEqualTo(16),
        reason: "$url scored $score — would be filtered from Bing set",
      );
    }
  });

  test("picker cap is 30", () {
    expect(LogoFinder.pickerMaxResults, 30);
  });
}
