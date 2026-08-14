import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/logo_finder.dart';

void main() {
  group('Logo search query expansion', () {
    test('primary query starts with bare name then logo variants', () {
      final q = LogoFinder.debugPrimaryQueries('Keyera');
      expect(q.first, 'Keyera');
      expect(q, contains('Keyera logo png'));
      expect(q, contains('Keyera logo'));
    });

    test('expanded synonyms include requested variants', () {
      final q = LogoFinder.debugExpandedQueries('Keyera');
      expect(q, contains('Keyera brand vector logo'));
      expect(q, contains('Keyera corporate logo transparent background'));
      expect(q, contains('Keyera official website logo'));
    });

    test('Serper query expansion uses high-res then vector then png', () {
      final q = LogoFinder.debugSerperQueries('Keyera');
      expect(q, [
        'Keyera logo high resolution transparent',
        'Keyera official brand logo vector',
        'Keyera company logo png',
      ]);
    });

    test('primary queries stay non-empty for multi-word names', () {
      expect(LogoFinder.debugPrimaryQueries('Acme Corp').isNotEmpty, isTrue);
    });
  });
}
