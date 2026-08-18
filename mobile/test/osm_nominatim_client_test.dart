import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/osm_nominatim_client.dart';

void main() {
  group('OsmNominatimClient.parseSearchBody', () {
    test('maps Nominatim jsonv2 addressdetails into label lines', () {
      const body = '''
[
  {
    "place_id": 123,
    "display_name": "3360, 10 Street, Nisku, Alberta, T9E 1E7, Canada",
    "address": {
      "house_number": "3360",
      "road": "10 Street",
      "town": "Nisku",
      "state": "Alberta",
      "ISO3166-2-lvl4": "CA-AB",
      "postcode": "T9E 1E7",
      "country": "Canada",
      "country_code": "ca"
    }
  }
]
''';
      final hits = OsmNominatimClient.parseSearchBody(body);
      expect(hits, hasLength(1));
      expect(hits.first.streetLine, '3360 10 Street');
      expect(hits.first.houseNumber, '3360');
      expect(hits.first.localityLine, 'Nisku, AB, T9E 1E7');
      expect(
        hits.first.displayAddress,
        '3360 10 Street, Nisku, AB, T9E 1E7',
      );
    });

    test('falls back to display_name when address parts are missing', () {
      const body = '''
[
  {
    "display_name": "Wellsite 12-34-56-7 W5, Alberta, Canada"
  }
]
''';
      final hits = OsmNominatimClient.parseSearchBody(body);
      expect(hits.single.displayAddress, 'Wellsite 12-34-56-7 W5, Alberta, Canada');
    });

    test('returns empty on invalid JSON', () {
      expect(OsmNominatimClient.parseSearchBody('{'), isEmpty);
      expect(OsmNominatimClient.parseSearchBody('{}'), isEmpty);
    });

    test('street-only OSM hits omit a civic number', () {
      const body = '''
[
  {
    "display_name": "130 Avenue, Maple Ridge, British Columbia, Canada",
    "address": {
      "road": "130 Avenue",
      "city": "Maple Ridge",
      "ISO3166-2-lvl4": "CA-BC",
      "postcode": "V4R 1X9",
      "country_code": "ca"
    }
  }
]
''';
      final hits = OsmNominatimClient.parseSearchBody(body);
      expect(hits.single.houseNumber, isEmpty);
      expect(hits.single.streetLine, '130 Avenue');
    });

    test('attaches a business name from amenity / name', () {
      const body = '''
[
  {
    "name": "Whitecap Resources Inc",
    "class": "office",
    "type": "company",
    "display_name": "Whitecap Resources Inc, 500 4 Avenue SW, Calgary, Alberta, Canada",
    "address": {
      "office": "Whitecap Resources Inc",
      "house_number": "500",
      "road": "4 Avenue SW",
      "city": "Calgary",
      "ISO3166-2-lvl4": "CA-AB",
      "postcode": "T2P 2V6",
      "country_code": "ca"
    }
  }
]
''';
      final hits = OsmNominatimClient.parseSearchBody(body);
      expect(hits.single.placeName, 'Whitecap Resources Inc');
      expect(hits.single.streetLine, '500 4 Avenue SW');
    });
  });

  group('OsmNominatimClient.biasCanada', () {
    test('defaults to Canada', () {
      expect(OsmNominatimClient.biasCanada('3360 10 Street Nisku'), isTrue);
    });

    test('drops countrycodes when query looks like the US', () {
      expect(OsmNominatimClient.biasCanada('500 5th Avenue New York USA'), isFalse);
      expect(OsmNominatimClient.biasCanada('Seattle 98101'), isFalse);
    });
  });

  group('parseCivicStreetQuery', () {
    test('splits 2971 130 avenue into house + street', () {
      final p = OsmNominatimClient.parseCivicStreetQuery('2971 130 avenue');
      expect(p.houseNumber, '2971');
      expect(p.streetName.toLowerCase(), '130 avenue');
      expect(p.structuredStreet, '2971 130 avenue');
      expect(p.hasStructuredStreet, isTrue);
    });

    test('keeps a comma locality hint off the street param', () {
      final p = OsmNominatimClient.parseCivicStreetQuery(
        '2971 130 avenue, maple ridge',
      );
      expect(p.houseNumber, '2971');
      expect(p.streetName.toLowerCase(), '130 avenue');
      expect(p.localityHint.toLowerCase(), 'maple ridge');
    });
  });

  group('formatDisplayAddress', () {
    test('includes house number when OSM has it', () {
      expect(
        OsmNominatimClient.formatDisplayAddress(
          streetLine: OsmNominatimClient.formatStreetLine(
            houseNumber: '2971',
            road: '130 Avenue',
          ),
          localityLine: 'Maple Ridge, BC, V4R 1X9',
        ),
        '2971 130 Avenue, Maple Ridge, BC, V4R 1X9',
      );
    });
  });

  group('mergeAndRankHits', () {
    test('prefers house_number match over street-only 130 Avenue', () {
      const streetOnly = NominatimHit(
        streetLine: '130 Avenue',
        localityLine: 'Maple Ridge, BC, V4R 1X9',
        displayAddress: '130 Avenue, Maple Ridge, BC, V4R 1X9',
      );
      const houseHit = NominatimHit(
        streetLine: '2971 130 Avenue',
        localityLine: 'Maple Ridge, BC, V2X 0A1',
        displayAddress: '2971 130 Avenue, Maple Ridge, BC, V2X 0A1',
        houseNumber: '2971',
      );
      const otherStreet = NominatimHit(
        streetLine: '130 Avenue',
        localityLine: 'Grande Prairie, AB, T8V 5C1',
        displayAddress: '130 Avenue, Grande Prairie, AB, T8V 5C1',
      );
      final parsed = OsmNominatimClient.parseCivicStreetQuery('2971 130 avenue');
      final ranked = OsmNominatimClient.mergeAndRankHits(
        [streetOnly, otherStreet, houseHit],
        parsed,
      );
      expect(ranked, isNotEmpty);
      expect(ranked.first.houseNumber, '2971');
      expect(ranked.first.displayAddress, startsWith('2971 130 Avenue'));
      expect(
        ranked.any((h) => h.displayAddress.startsWith('130 Avenue,')),
        isFalse,
      );
    });
  });
}
