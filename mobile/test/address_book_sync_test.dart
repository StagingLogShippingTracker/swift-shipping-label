import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/address_book_sync.dart';
import 'package:swift_shipping_label/address_osm_enrich.dart';
import 'package:swift_shipping_label/osm_nominatim_client.dart';

DeliveryAddressEntry _e({
  required String name,
  required String address,
  String carrier = '',
  String accounts = '',
  String key = '',
  int minutes = 0,
}) {
  return DeliveryAddressEntry(
    addressKey: key.isEmpty ? address : key,
    shipToName: name,
    address: address,
    carrier: carrier,
    accountNumbers: accounts,
    lastUsedAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: minutes)),
  );
}

void main() {
  group('AddressBookSync.collapseDuplicates', () {
    test('same name+address+same courier merges', () {
      final a = _e(
        name: 'GCM Valve',
        address: '3360 10 Street',
        carrier: 'Murrays',
        minutes: 1,
      );
      final b = _e(
        name: 'GCM Valve',
        address: '3360 10th St, Nisku AB T9E 1E7',
        carrier: 'murrays',
        accounts: '12345',
        minutes: 5,
      );
      final out = AddressBookSync.collapseDuplicates([a, b]);
      expect(out, hasLength(1));
      expect(out.single.carrier.toLowerCase(), 'murrays');
      expect(out.single.accountNumbers, contains('12345'));
      expect(out.single.address, contains('Nisku'));
      expect(out.single.lastUsedAt, b.lastUsedAt);
    });

    test('same name+address+different courier keeps both', () {
      final a = _e(
        name: 'Arc Resources',
        address: '1200 8 Street SW, Calgary AB',
        carrier: 'Murrays',
        minutes: 2,
      );
      final b = _e(
        name: 'Arc Resources',
        address: '1200 8 St SW Calgary',
        carrier: 'Dunrite',
        minutes: 3,
      );
      final out = AddressBookSync.collapseDuplicates([a, b]);
      expect(out, hasLength(2));
      expect(
        out.map((e) => e.carrier.toLowerCase()).toSet(),
        {'murrays', 'dunrite'},
      );
    });

    test('same courier but different accounts keeps both', () {
      final a = _e(
        name: 'Propak',
        address: '1 Industrial Rd',
        carrier: 'Murrays',
        accounts: 'AAA',
      );
      final b = _e(
        name: 'Propak',
        address: '1 Industrial Road',
        carrier: 'Murrays',
        accounts: 'BBB',
      );
      expect(AddressBookSync.collapseDuplicates([a, b]), hasLength(2));
    });
  });

  group('AddressOsmEnrich', () {
    test('OSM miss leaves the entry unchanged', () {
      const current = 'Wellsite 12-34-56-7 W5';
      expect(AddressOsmEnrich.fillFromHits(current, const []), current);
      expect(
        AddressOsmEnrich.fillFromHits(current, const [
          NominatimHit(
            streetLine: '10 Street',
            localityLine: 'Nisku, AB',
            displayAddress: '10 Street, Nisku, AB',
            city: 'Nisku',
            province: 'AB',
          ),
        ]),
        current,
      );
    });

    test('fills missing city/province/postal without changing civic', () {
      const current = '3360 10 Street';
      const hit = NominatimHit(
        streetLine: '3360 10 Street',
        localityLine: 'Nisku, AB, T9E 1E7',
        displayAddress: '3360 10 Street, Nisku, AB, T9E 1E7',
        houseNumber: '3360',
        city: 'Nisku',
        province: 'AB',
        postal: 'T9E 1E7',
      );
      expect(
        AddressOsmEnrich.fillFromHits(current, const [hit]),
        '3360 10 Street, Nisku, AB, T9E 1E7',
      );
    });

    test('rejects a street-only OSM hit when a civic number was typed', () {
      const current = '2971 130 Avenue';
      const streetOnly = NominatimHit(
        streetLine: '130 Avenue',
        localityLine: 'Maple Ridge, BC',
        displayAddress: '130 Avenue, Maple Ridge, BC',
        city: 'Maple Ridge',
        province: 'BC',
      );
      expect(AddressOsmEnrich.fillFromHits(current, const [streetOnly]), current);
    });
  });
}
