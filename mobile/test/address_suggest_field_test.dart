import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/address_book_sync.dart';
import 'package:swift_shipping_label/address_suggest_field.dart';
import 'package:swift_shipping_label/osm_nominatim_client.dart';

void main() {
  group('addressSearchQuery', () {
    test('keeps the incomplete last word and does not require a trailing space',
        () {
      expect(addressSearchQuery('123 Harrison'), '123 Harrison');
      expect(addressSearchQuery('123 Harrison '), '123 Harrison');
      expect(addressSearchQuery('  123 Harrison Drive'), '123 Harrison Drive');
    });

    test('does not drop the last token', () {
      expect(addressSearchQuery('123 Harrison'), isNot('123'));
    });

    test('searches once the full text is at least 3 characters', () {
      expect(shouldSearchRemoteAddress('12'), isFalse);
      expect(shouldSearchRemoteAddress('123'), isTrue);
      expect(shouldSearchRemoteAddress('123 Harrison'), isTrue);
    });
  });

  group('mergeAddressSuggestions', () {
    final book = [
      DeliveryAddressEntry(
        addressKey: 'k',
        shipToName: 'Acme',
        address: '99 Local Ave\nNisku AB',
        carrier: '',
        accountNumbers: '',
        lastUsedAt: DateTime.utc(2020),
      ),
    ];
    const osm = [
      NominatimHit(
        streetLine: '123 Harrison Drive',
        localityLine: 'Nisku, AB',
        displayAddress: '123 Harrison Drive\nNisku, AB',
      ),
    ];

    test('address book matches as-you-type', () {
      final hits = mergeAddressSuggestions(
        raw: '99 Loc',
        entries: book,
        osmHits: const [],
      );
      expect(hits.single.fromBook, isTrue);
      expect(hits.single.address, contains('99 Local'));
      expect(hits.single.caption, 'Saved · Acme');
      expect(hits.single.placeName, 'Acme');
    });

    test('empty query still lists the book as saved addresses', () {
      final hits = mergeAddressSuggestions(
        raw: '',
        entries: book,
        osmHits: const [],
      );
      expect(hits.single.fromBook, isTrue);
      expect(hits.single.caption, startsWith('Saved'));
      final rows = addressSuggestOverlayItems(hits);
      expect(rows.first.header, 'Saved addresses');
      expect(rows[1].suggestion!.fromBook, isTrue);
    });

    test('keeps OSM hits that do not substring-match the typed token', () {
      final hits = mergeAddressSuggestions(
        raw: '123 Harrison',
        entries: book,
        osmHits: osm,
      );
      expect(
        hits.any((s) => s.address.contains('123 Harrison Drive')),
        isTrue,
      );
    });

    test('overlay headers split saved addresses then suggested addresses', () {
      final hits = mergeAddressSuggestions(
        raw: '99',
        entries: book,
        osmHits: osm,
      );
      final rows = addressSuggestOverlayItems(hits);
      expect(rows.map((r) => r.header).whereType<String>().toList(), [
        'Saved addresses',
        'Suggested addresses',
      ]);
      expect(
        rows.any((r) => r.suggestion?.caption == 'Suggested address'),
        isTrue,
      );
    });
  });

  group('savedAddressCaption', () {
    test('keeps ship-to name after Saved', () {
      expect(
        savedAddressCaption('5BLUE PROCESS EQUIPMENT INC - SHOP #3'),
        'Saved · 5BLUE PROCESS EQUIPMENT INC - SHOP #3',
      );
    });

    test('uses Saved alone when ship-to is blank', () {
      expect(savedAddressCaption(''), 'Saved');
    });
  });
}
