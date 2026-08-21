import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/bol_dimensions.dart';

void main() {
  test('parses bare 48x40x48 as inches on each axis', () {
    final d = BolDimensionsValue.parse('48x40x48');
    expect(d.length, '48');
    expect(d.width, '40');
    expect(d.height, '48');
    expect(d.lengthUnit, 'in');
    expect(d.widthUnit, 'in');
    expect(d.heightUnit, 'in');
    expect(d.format(), '48 in × 40 in × 48 in');
  });

  test('parses legacy shared unit suffix', () {
    final d = BolDimensionsValue.parse('12 × 8 × 10 cm');
    expect(d.lengthUnit, 'cm');
    expect(d.widthUnit, 'cm');
    expect(d.heightUnit, 'cm');
    expect(d.format(), '12 cm × 8 cm × 10 cm');
  });

  test('parses mixed per-axis units (pipe)', () {
    final d = BolDimensionsValue.parse('6 in × 6 in × 21 ft');
    expect(d.length, '6');
    expect(d.width, '6');
    expect(d.height, '21');
    expect(d.lengthUnit, 'in');
    expect(d.widthUnit, 'in');
    expect(d.heightUnit, 'ft');
    expect(d.format(), '6 in × 6 in × 21 ft');
  });

  test('empty stays empty', () {
    expect(BolDimensionsValue.parse('').isEmpty, isTrue);
    expect(const BolDimensionsValue().format(), '');
  });
}
