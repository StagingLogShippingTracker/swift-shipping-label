import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/bol_dimensions.dart';

void main() {
  test('parses 48x40x48 as inches', () {
    final d = BolDimensionsValue.parse('48x40x48');
    expect(d.length, '48');
    expect(d.width, '40');
    expect(d.height, '48');
    expect(d.unit, 'in');
    expect(d.format(), '48 × 40 × 48 in');
  });

  test('parses unit suffix and unicode times', () {
    final d = BolDimensionsValue.parse('12 × 8 × 10 cm');
    expect(d.unit, 'cm');
    expect(d.format(), '12 × 8 × 10 cm');
  });

  test('empty stays empty', () {
    expect(BolDimensionsValue.parse('').isEmpty, isTrue);
    expect(const BolDimensionsValue().format(), '');
  });
}
