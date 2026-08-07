import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/employee_directory.dart';

void main() {
  test('EmployeeDirectory.filter prefers prefix matches', () {
    const names = [
      'Avry Yorgason',
      'Brice Johnson',
      'Keith Blackman',
      'Chris Acorn',
    ];
    expect(
      EmployeeDirectory.filter(names, 'br').toList(),
      ['Brice Johnson'],
    );
    expect(
      EmployeeDirectory.filter(names, 'ack').toList(),
      ['Keith Blackman'],
    );
    expect(EmployeeDirectory.filter(names, '').length, lessThanOrEqualTo(24));
    // Free-text: empty filter when no roster — caller still keeps typed value.
    expect(EmployeeDirectory.filter(const [], 'Custom Name'), isEmpty);
  });
}
