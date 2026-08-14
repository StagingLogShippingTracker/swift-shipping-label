import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/address_book_sync.dart';
import 'package:swift_shipping_label/address_match.dart';

void main() {
  group('AddressMatch.addressKey', () {
    test('ignores case', () {
      expect(
        AddressMatch.addressKey('1017 8 Street'),
        AddressMatch.addressKey('1017 8 STREET'),
      );
    });

    test('hyphens, spaces, ordinals, and St/Street collapse', () {
      const variants = [
        '1017-8 Street',
        '1017 8 Street',
        '1017 8th Street',
        '1017 8th St.',
        '1017 8th St',
        '1017-8th Street',
        '1017  8   Street',
      ];
      final keys = {for (final v in variants) AddressMatch.addressKey(v)};
      expect(keys.length, 1);
    });

    test('rearranged same tokens match', () {
      expect(
        AddressMatch.addressKey('1017 8 St SW, Calgary AB'),
        AddressMatch.addressKey('Calgary AB, 1017 8 Street SW'),
      );
    });

    test('different civic numbers stay distinct', () {
      expect(
        AddressMatch.addressKey('1017 8 Street'),
        isNot(AddressMatch.addressKey('1018 8 Street')),
      );
    });
  });

  group('AddressMatch.samePlace', () {
    test('same ship-to name despite hyphen/case', () {
      expect(
        AddressMatch.samePlace(
          shipToA: 'Mastec Purnell',
          addressA: '1017-8 Street',
          shipToB: 'MASTEC-PURNELL',
          addressB: '1017 8th St.',
        ),
        isTrue,
      );
    });

    test('different ship-to names do not merge', () {
      expect(
        AddressMatch.samePlace(
          shipToA: 'Mastec Purnell',
          addressA: '1017 8 Street',
          shipToB: 'Arc Resources',
          addressB: '1017 8 Street',
        ),
        isFalse,
      );
    });
  });

  test('address book lists Ship To Name Z–A', () {
    DeliveryAddressEntry e(String name, int minutesAgo) => DeliveryAddressEntry(
          addressKey: name,
          shipToName: name,
          address: '1 Main St',
          carrier: '',
          accountNumbers: '',
          lastUsedAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: minutesAgo)),
        );
    final sorted = AddressBookSync.sortByShipToName([
      e('Arc Resources', 3),
      e('Worley Cord', 1),
      e('mastec purnell', 2),
    ]);
    expect(sorted.map((x) => x.shipToName).toList(), [
      'Worley Cord',
      'mastec purnell',
      'Arc Resources',
    ]);
  });
}
