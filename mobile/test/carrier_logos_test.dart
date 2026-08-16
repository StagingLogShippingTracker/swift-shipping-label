import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/carrier_logos.dart';

void main() {
  group('CarrierLogos.matchId Murray\'s', () {
    const variants = [
      "Murray's",
      'murrays',
      'Murray',
      "murray's trucking",
      'Murrays Trucking',
      "Murray's Pre-Paid",
      'MURRAYS',
    ];
    for (final v in variants) {
      test('matches "$v"', () {
        expect(CarrierLogos.matchId(v), CarrierLogos.murrays);
      });
    }
  });

  group('CarrierLogos.matchId Dunrite', () {
    const variants = [
      'Dunrite',
      'dunrite',
      'dun-rite',
      'dunright',
      'Dun Rite',
      'DUNRITE TRUCKING',
      'Dun-Rite Trucking',
    ];
    for (final v in variants) {
      test('matches "$v"', () {
        expect(CarrierLogos.matchId(v), CarrierLogos.dunrite);
      });
    }
  });

  test('Purolator and empty do not match', () {
    expect(CarrierLogos.matchId('Purolator'), isNull);
    expect(CarrierLogos.matchId(''), isNull);
    expect(CarrierLogos.matchId('WILLYS'), isNull);
  });

  test('normalize strips punctuation', () {
    expect(CarrierLogos.normalize("Murray's Trucking"), 'murrays trucking');
    expect(CarrierLogos.normalize('dun-rite'), 'dun rite');
  });
}
