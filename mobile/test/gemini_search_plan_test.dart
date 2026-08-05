import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/gemini_client.dart';

void main() {
  test('GeminiLogoSearchPlan parses enrichment JSON', () {
    final plan = GeminiLogoSearchPlan.fromJson({
      'alternate_names': ['Keyera Corp', 'Keyera Energy'],
      'search_queries': ['Keyera logo png transparent', 'Keyera official brand mark'],
      'official_domains': ['keyera.com', 'https://www.keyera.com/about'],
      'logo_url_hints': [
        'https://www.keyera.com/images/logo.png',
        'not-a-url',
      ],
      'notes': 'midstream energy',
    });
    expect(plan.alternateNames, contains('Keyera Corp'));
    expect(plan.searchQueries.first, contains('Keyera'));
    expect(plan.officialDomains, isNotEmpty);
    expect(plan.logoUrlHints, ['https://www.keyera.com/images/logo.png']);
    expect(plan.isEmpty, isFalse);
  });

  test('empty plan when lists missing', () {
    final plan = GeminiLogoSearchPlan.fromJson({});
    expect(plan.isEmpty, isTrue);
  });
}
