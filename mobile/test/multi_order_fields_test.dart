import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/multi_order_fields.dart';

void main() {
  group('formatSalesOrders', () {
    test('comma list', () {
      expect(
        formatSalesOrders('1422989, 1423363'),
        '1422989 / 1423363',
      );
    });
    test('slash without spaces', () {
      expect(
        formatSalesOrders('1422989/1423363'),
        '1422989 / 1423363',
      );
    });
    test('three orders mixed separators', () {
      expect(
        formatSalesOrders('1422989 / 1423363, 1423168'),
        '1422989 / 1423363 / 1423168',
      );
    });
    test('keeps dotted and hyphenated values like PO', () {
      expect(
        formatSalesOrders('4460.168 / SO-88421'),
        '4460.168 / SO-88421',
      );
      expect(
        parseSalesOrders('4460.168, SO-88421'),
        ['4460.168', 'SO-88421'],
      );
    });
    test('named tokens split on slash the same as PO', () {
      expect(parseSalesOrders('abc / def'), ['abc', 'def']);
      expect(formatSalesOrders('no numbers here'), 'no numbers here');
    });
  });

  group('formatNamedSegments', () {
    test('does not split PO on spaces', () {
      expect(
        formatNamedSegments('123 Water Disposal', finalize: true),
        '123 Water Disposal',
      );
      expect(
        parseNamedSegments('123 Water Disposal', finalize: true),
        ['123 Water Disposal'],
      );
    });
    test('comma while typing becomes slash join with trailing sep', () {
      expect(
        formatNamedSegments('123 Water Disposal,', finalize: false),
        '123 Water Disposal / ',
      );
    });
    test('blur accepts slash separators', () {
      expect(
        formatNamedSegments('123 Water Disposal / NEXT PO', finalize: true),
        '123 Water Disposal / NEXT PO',
      );
      expect(
        parseNamedSegments('123 Water Disposal / NEXT PO', finalize: true),
        ['123 Water Disposal', 'NEXT PO'],
      );
    });
    test('comma on blur', () {
      expect(
        formatNamedSegments('123 Water Disposal, ABC Site', finalize: true),
        '123 Water Disposal / ABC Site',
      );
    });
  });

  group('mapping deduction', () {
    test('2 SO 2 PO: ask first then deduce', () {
      const sos = ['1422989', '1423363'];
      const pos = ['PO A', 'PO B'];
      var step = nextMappingStep(extras: pos, salesOrders: sos);
      expect(step.done, isFalse);
      expect(step.askValue, 'PO A');
      expect(step.choices, sos);
      step = nextMappingStep(
        extras: pos,
        salesOrders: sos,
        assigned: {step.askIndex!: '1422989'},
      );
      expect(step.done, isTrue);
      expect(step.assigned[1], '1423363');
    });

    test('7 PO 4 SO: pair 4, ignore leftover extras', () {
      final sos = List.generate(4, (i) => 'SO$i');
      final pos = List.generate(7, (i) => 'PO$i');
      expect(pairableCount(7, 4), 4);
      var assigned = <int, String>{};
      for (var n = 0; n < 10; n++) {
        final step = nextMappingStep(
          extras: pos,
          salesOrders: sos,
          assigned: assigned,
        );
        if (step.done) {
          expect(step.assigned.length, 4);
          expect(step.assigned.keys, isNot(contains(4)));
          return;
        }
        assigned = {...step.assigned, step.askIndex!: step.choices.first};
      }
      fail('did not complete');
    });

    test('1 PO 2 SO: no pairing', () {
      final step = nextMappingStep(
        extras: ['only po'],
        salesOrders: ['111', '222'],
      );
      expect(step.done, isTrue);
      expect(step.assigned, isEmpty);
    });

    test('2 PO 1 SO: no pairing', () {
      final step = nextMappingStep(
        extras: ['a', 'b'],
        salesOrders: ['111'],
      );
      expect(step.done, isTrue);
      expect(step.assigned, isEmpty);
    });
  });
}
