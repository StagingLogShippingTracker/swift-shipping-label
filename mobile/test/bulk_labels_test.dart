import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/bulk/bulk_label_models.dart';
import 'package:swift_shipping_label/bulk/order_ack_parser.dart';
import 'package:swift_shipping_label/pdf/bulk_label_pdf.dart';

void main() {
  group('OrderAckParser', () {
    test('parses clean OA text fixture', () {
      final text =
          File('test/fixtures/propak_order_ack_sample.txt').readAsStringSync();
      final result = const OrderAckParser().parseText(text);
      expect(result.poNumber, 'P612207');
      expect(result.orderNumber, '1423442');
      expect(result.lines.length, greaterThanOrEqualTo(40));

      final line4 = result.lines.firstWhere((l) => l.cpo == '4');
      expect(line4.tagOrPart, '2"GL-A-03AR');
      expect(line4.idKind, BulkIdKind.tag);
      expect(line4.idKind.fieldLabel, 'TAG#');
      expect(line4.quantity, 2);
      expect(line4.labelCount, 2);

      final line8 = result.lines.firstWhere((l) => l.cpo == '8');
      expect(line8.quantity, 12);
      expect(line8.idKind, BulkIdKind.tag);

      final expanded = result.expand();
      expect(expanded.length, result.totalLabels);
      expect(
        expanded
            .where((e) => e.cpo == '4' && e.tagOrPart == '2"GL-A-03AR')
            .length,
        2,
      );
      expect(result.sheetCount, (result.totalLabels + 9) ~/ 10);
      // All stickers share the same PO.
      expect(expanded.every((e) => e.poNumber == 'P612207'), isTrue);
    });

    test('parses pdfrx-style qty-before-EA layout', () {
      const text = '''
ORDER ACKNOWLEDGEMENT
1423442
PO Number
P612207
2.00 EA 2" 300# RF WARREN
4
Order Line Notes: CPO #4
Order Line Notes: TAG# 2"GL-A-03AR
12.00 EA 1/2" BALL
8
Order Line Notes: CPO #8
Order Line Notes: TAG# 1/2"BA-A-20AT
''';
      final result = const OrderAckParser().parseText(text);
      expect(result.poNumber, 'P612207');
      expect(result.lines.firstWhere((l) => l.cpo == '4').quantity, 2);
      expect(result.lines.firstWhere((l) => l.cpo == '8').quantity, 12);
    });

    test('uses PART# when OA has no TAG#', () {
      const text = '''
ORDER ACKNOWLEDGEMENT
1423442
PO Number
P612207
1.00 EA STRAINER
12
Order Line Notes: CPO #12
Order Line Notes: PART# 4"Y-STRAINER-300
2.00 EA VALVE
13
Order Line Notes: CPO #13
Order Line Notes: TAG# 2"GL-A-03AR
''';
      final result = const OrderAckParser().parseText(text);
      final partLine = result.lines.firstWhere((l) => l.cpo == '12');
      expect(partLine.idKind, BulkIdKind.part);
      expect(partLine.idKind.fieldLabel, 'PART#');
      expect(partLine.tagOrPart, '4"Y-STRAINER-300');
      expect(partLine.quantity, 1);

      final tagLine = result.lines.firstWhere((l) => l.cpo == '13');
      expect(tagLine.idKind, BulkIdKind.tag);
      expect(tagLine.idKind.fieldLabel, 'TAG#');

      final expanded = result.expand();
      expect(expanded.where((e) => e.idKind == BulkIdKind.part).length, 1);
      expect(expanded.where((e) => e.idKind == BulkIdKind.tag).length, 2);
    });

    test('collects incomplete lines missing TAG#/PART# for dialog', () {
      final text =
          File('test/fixtures/propak_order_ack_sample.txt').readAsStringSync();
      final result = const OrderAckParser().parseText(text);
      expect(result.hasIncompleteLines, isTrue);
      expect(
        result.incompleteLines.any((l) => l.cpo == '28'),
        isTrue,
      );
      // Incomplete lines are not in the printable set until Proceed/Skip.
      expect(result.lines.any((l) => l.cpo == '28'), isFalse);

      final skipped = result.applyingMissingIdAction(BulkMissingIdAction.skip);
      expect(skipped.hasIncompleteLines, isFalse);
      expect(skipped.lines.any((l) => l.cpo == '28'), isFalse);
      expect(
        skipped.warnings.any((w) => w.contains('CPO #28') && w.contains('PM')),
        isTrue,
      );

      final proceeded =
          result.applyingMissingIdAction(BulkMissingIdAction.proceed);
      expect(proceeded.hasIncompleteLines, isFalse);
      final line28 = proceeded.lines.firstWhere((l) => l.cpo == '28');
      expect(line28.missingIdentity, isTrue);
      expect(line28.tagOrPart, isEmpty);
      expect(
        proceeded.warnings.any((w) => w.contains('CPO #28') && w.contains('PM')),
        isTrue,
      );
    });
  });

  group('Avery 5163 tiling', () {
    test('sheetCount math', () {
      expect(BulkLabelPdf.perSheet, 10);
      expect((1 + 9) ~/ 10, 1);
      expect((10 + 9) ~/ 10, 1);
      expect((11 + 9) ~/ 10, 2);
    });
  });
}
