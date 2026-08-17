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

    test('parses CPO LINE + loose part # and under-CPO fallback (1425965)', () {
      final text =
          File('test/fixtures/propak_oa_1425965.txt').readAsStringSync();
      final result = const OrderAckParser().parseText(text);
      expect(result.poNumber, 'P613120');
      expect(result.orderNumber, '1425965');
      expect(result.lines, isNotEmpty);

      // CPO LINE 1 has no part # — use the "Used by …" line under CPO.
      final line1 = result.lines.firstWhere((l) => l.cpo == '1');
      expect(line1.idKind, BulkIdKind.part);
      expect(line1.tagOrPart.toLowerCase(), contains('used by'));
      expect(line1.quantity, 1);

      // Explicit loose part # under CPO LINE.
      final line5 = result.lines.firstWhere((l) => l.cpo == '5');
      expect(line5.tagOrPart, '050211');
      expect(line5.idKind, BulkIdKind.part);

      // Multi CPO on one note expands to separate stickers.
      expect(result.lines.any((l) => l.cpo == '8'), isTrue);
      expect(result.lines.any((l) => l.cpo == '9'), isTrue);
      final line8 = result.lines.firstWhere((l) => l.cpo == '8');
      final line9 = result.lines.firstWhere((l) => l.cpo == '9');
      expect(line8.tagOrPart, '055329');
      expect(line9.tagOrPart, '055329');
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

    test('header: Bill To customer + Delivery Instructions ship-to (1425965)', () {
      final text =
          File('test/fixtures/propak_oa_1425965.txt').readAsStringSync();
      final result = const OrderAckParser().parseText(text);
      expect(result.customerName, 'PROPAK SYSTEMS LTD.');
      expect(result.orderNumber, '1425965');
      expect(result.projectNumber, 'P613120');
      expect(result.poNumber, 'P613120');
      expect(result.hasDeliveryShipTo, isTrue);
      expect(result.deliveryShipToName.toLowerCase(), contains('propak'));
      expect(result.deliveryShipToAddress.toLowerCase(), contains('veterans'));
      expect(result.deliveryCarrier.toUpperCase(), contains('ROSENAU'));
      expect(result.headerShipToName, 'PROPAK SYSTEMS LTD.');
    });

    test('header: Delivery Instructions name when freight is on the last line', () {
      final text =
          File('test/fixtures/propak_order_ack_sample.txt').readAsStringSync();
      final result = const OrderAckParser().parseText(text);
      expect(result.customerName, 'PROPAK SYSTEMS LTD.');
      expect(result.hasDeliveryShipTo, isTrue);
      expect(result.deliveryShipToName.toLowerCase(), contains('propak'));
      expect(result.deliveryShipToAddress.toLowerCase(), contains('east lake'));
      expect(result.deliveryCarrier.toLowerCase(), contains('rosenau'));
    });

    test('header: missing Delivery Instructions is flagged', () {
      const text = '''
ORDER ACKNOWLEDGEMENT
1420001
Bill To: 11693 Ship To:
ACME LTD.
1 MAIN ST
NISKU, AB T9E 1C6
CA
780-000-0000
ACME LTD.
1 MAIN ST
NISKU, AB T9E 1C6
CA
Ordered By: JANE
ProjectLocationPO Number
P111111
AFE # GL Code
Item DescriptionQuantityNo. UOM Unit Price Extended Price
1.00EA1.00 1.00WIDGET
1
Order Line Notes: CPO LINE 1
part # 1
''';
      final result = const OrderAckParser().parseText(text);
      expect(result.hasDeliveryShipTo, isFalse);
      expect(result.customerName, 'ACME LTD.');
      expect(result.headerShipToName, 'ACME LTD.');
      expect(result.headerShipToAddress.toLowerCase(), contains('main'));
    });

    test('packing list fills Swift packing slip number', () {
      const text = '''
PACKING LIST
PS-88991
Order Date
Order Number
Swift Oilfield Supply Inc.
1425965
Bill To: 11693 Ship To:
PROPAK SYSTEMS LTD.
440 EAST. LAKE ROAD
AIRDRIE, AB T4A 2J8
CA
403-912-7000
PROPAK SYSTEMS LTD.
440 EAST. LAKE ROAD
AIRDRIE, AB T4A 2J8
CA
Ordered By: RONDA MOORE
ProjectLocationPO Number
P613120
Packing Slip No. PS-88991
''';
      final result = const OrderAckParser().parseText(text);
      expect(result.documentKind, 'packing_list');
      expect(result.packingSlipNumber, 'PS-88991');
      expect(result.orderNumber, '1425965');
      expect(result.customerName, 'PROPAK SYSTEMS LTD.');
    });

    test('Spartan-style PO Location Project keeps full dotted refs', () {
      const text = '''
ORDER ACKNOWLEDGEMENT
1423246
Order Date
Order Number
Swift Oilfield Supply Inc.
08/04/2026
Sales Rep CHRIS.ACORN
Bill To: 11797 Ship To:
SPARTAN DELTA CORP.
350 - 7 AVENUE SW
CALGARY, AB T2P 3N9
CA
403-265-8011
SPARTAN DELTA CORP.
350 - 7 AVENUE SW
CALGARY, AB T2P 3N9
CA
Ordered By: Kyle Johnson
PO Number Location Project
4460.168-016	01-19-043-03W5M Riser Site	4460.168
Requisitioner Approver AFE # Cost Center # Work Order # GL Code
Kyle Johnson		26GAT609-O	351.04
Item DescriptionQuantityNo. UOM Unit Price Extended Price
9.00EA42.02 PRESSURE INDICATOR
1
''';
      final result = const OrderAckParser().parseText(text);
      expect(result.orderNumber, '1423246');
      expect(result.customerName, 'SPARTAN DELTA CORP.');
      expect(result.poNumber, '4460.168-016');
      expect(result.projectNumber, '4460.168');
      expect(result.jobLocation, contains('01-19-043-03W5M'));
      expect(result.jobLocation.toLowerCase(), contains('riser'));
      expect(result.requisitioner, 'Kyle Johnson');
      expect(result.afeNumber, '26GAT609-O');
      expect(result.specialInstructionsHint, contains('Riser'));
      expect(result.specialInstructionsHint, contains('AFE'));
      expect(result.headerShipToName, 'SPARTAN DELTA CORP.');
    });

    test('spaced PO Location Project row still splits dotted tokens', () {
      const text = '''
ORDER ACKNOWLEDGEMENT
1423246
PO Number Location Project
4460.168-016 01-19-043-03W5M Riser Site 4460.168
Bill To: 11797 Ship To:
SPARTAN DELTA CORP.
1 MAIN ST
CALGARY, AB T2P 3N9
CA
403-265-8011
SPARTAN DELTA CORP.
1 MAIN ST
CALGARY, AB T2P 3N9
CA
''';
      final result = const OrderAckParser().parseText(text);
      expect(result.poNumber, '4460.168-016');
      expect(result.projectNumber, '4460.168');
      expect(result.jobLocation, contains('Riser'));
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
