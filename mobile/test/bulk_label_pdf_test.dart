import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/bulk/bulk_label_models.dart';
import 'package:swift_shipping_label/bulk/order_ack_parser.dart';
import 'package:swift_shipping_label/pdf/bulk_label_docx.dart';
import 'package:swift_shipping_label/pdf/bulk_label_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('BulkLabelPdf builds multi-page Avery sheet', () async {
    final text =
        File('test/fixtures/propak_order_ack_sample.txt').readAsStringSync();
    final parsed = const OrderAckParser().parseText(text);
    final labels = parsed.expand();
    expect(labels, isNotEmpty);

    final pdf = await BulkLabelPdf.load();
    final bytes = await pdf.build(labels.take(12).toList());
    expect(bytes.length, greaterThan(1000));
    // PDF header
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');

    // Write smoke artifact for manual print check when desired.
    final out = File('test/fixtures/_bulk_labels_smoke.pdf');
    await out.writeAsBytes(Uint8List.fromList(bytes), flush: true);
    expect(await out.exists(), isTrue);
  });

  test('BulkLabelDocx clones Propak template with TAG# and PART#', () async {
    final labels = [
      const BulkLabelInstance(
        poNumber: 'P612207',
        cpo: '4',
        tagOrPart: '2"GL-A-03AR',
        idKind: BulkIdKind.tag,
        sourceLineNo: 4,
      ),
      const BulkLabelInstance(
        poNumber: 'P612207',
        cpo: '12',
        tagOrPart: '4"Y-STRAINER',
        idKind: BulkIdKind.part,
        sourceLineNo: 12,
      ),
      for (var i = 0; i < 10; i++)
        BulkLabelInstance(
          poNumber: 'P612207',
          cpo: '${20 + i}',
          tagOrPart: 'T$i',
          idKind: BulkIdKind.tag,
          sourceLineNo: 20 + i,
        ),
    ];

    final bytes = await BulkLabelDocx.build(labels);
    expect(bytes.length, greaterThan(1000));
    // ZIP / DOCX header
    expect(bytes[0], 0x50); // P
    expect(bytes[1], 0x4b); // K

    final archive = ZipDecoder().decodeBytes(bytes);
    final doc = archive.findFile('word/document.xml');
    expect(doc, isNotNull);
    final xml = utf8.decode(doc!.content);
    expect(xml.contains('TAG#'), isTrue);
    expect(xml.contains('PART#'), isTrue);
    expect(xml.contains('TAG/'), isFalse);
    expect(xml.contains('P612207'), isTrue);
    expect(xml.contains('2"GL-A-03AR') || xml.contains('2&quot;GL-A-03AR'), isTrue);
    expect(xml.contains('4"Y-STRAINER') || xml.contains('4&quot;Y-STRAINER'), isTrue);
    // Two sheets for 12 labels.
    expect('w:type="page"'.allMatches(xml).length, 1);

    final out = File('test/fixtures/_bulk_labels_smoke.docx');
    await out.writeAsBytes(bytes, flush: true);
    expect(await out.exists(), isTrue);
  });
}
