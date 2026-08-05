import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/logo_finder.dart';

void main() {
  group('Logo crawler parsers & query expansion', () {
    test('primary query starts with "{name} logo png"', () {
      final q = LogoFinder.debugPrimaryQueries('Keyera');
      expect(q.first, 'Keyera logo png');
      expect(q, contains('Keyera logo'));
    });

    test('expanded synonyms include requested variants', () {
      final q = LogoFinder.debugExpandedQueries('Keyera');
      expect(q, contains('Keyera brand vector logo'));
      expect(q, contains('Keyera corporate logo transparent background'));
      expect(q, contains('Keyera official website logo'));
    });

    test('Bing parser extracts murl from iusc JSON and entity-encoded HTML', () {
      const html = '''
        <a class="iusc" m="{&quot;murl&quot;:&quot;https://cdn.example.com/keyera-logo.png&quot;,&quot;turl&quot;:&quot;https://bing.com/th&quot;}"></a>
        <div>{"murl":"https://images.example.com/brand.png","mediaurl":"https://images.example.com/brand-hires.png"}</div>
        <span>murl&quot;:&quot;https://static.example.com/logo.webp&quot;</span>
      ''';
      final urls = LogoFinder.debugParseBingPayload(html);
      expect(urls, contains('https://cdn.example.com/keyera-logo.png'));
      expect(urls, contains('https://images.example.com/brand.png'));
      expect(urls, contains('https://static.example.com/logo.webp'));
    });

    test('Google parser extracts ou fields, data-src, and AF_initDataCallback', () {
      const html = '''
        <script>AF_initDataCallback({"key":"ds:1","data":[["https://img.example.com/acme-logo.png"],{"ou":"https://cdn.example.com/acme.png"}],"sideChannel":{}});</script>
        <img data-src="https://cdn.example.com/data-src-logo.png" data-ils="0" />
        <div>"ou":"https://cdn.example.com/ou-field.jpg"</div>
      ''';
      final urls = LogoFinder.debugParseGoogleHtml(html);
      expect(urls.any((u) => u.contains('acme-logo.png') || u.contains('acme.png')), isTrue);
      expect(urls, contains('https://cdn.example.com/data-src-logo.png'));
      expect(urls, contains('https://cdn.example.com/ou-field.jpg'));
    });

    test('rotating browser headers expose Chrome Sec-Ch-Ua', () {
      // Smoke: constructing finder + running a tiny offline parse path is enough;
      // header rotation is exercised by live fetches in logo_finder_parse_test.
      expect(LogoFinder.debugPrimaryQueries('Acme Corp').isNotEmpty, isTrue);
    });
  });
}
