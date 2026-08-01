import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/label_data.dart';
import 'package:swift_shipping_label/pdf/bol_label_pdf.dart';
import 'package:swift_shipping_label/pdf/shipping_label_pdf.dart';

/// Writes a sample BOL PDF (same data as app "Load sample") for preview.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate BOL sample PDF', () async {
    final shipping = await ShippingLabelPdf.load();
    final bol = BolLabelPdf(shipping);

    Uint8List? logo;
    try {
      final data =
          await rootBundle.load('assets/images/sample_customer_logo.png');
      logo = data.buffer.asUint8List();
    } catch (_) {}

    final bytes = await bol.build(
      data: ShippingLabelData.bolSample,
      customerLogoBytes: logo == null ? const [] : [logo],
    );

    final out = File(
      '${Directory.current.parent.path}${Platform.pathSeparator}'
      'Swift Supply Bill of Lading - Sample (app).pdf',
    );
    await out.writeAsBytes(bytes);
    // ignore: avoid_print
    print('Wrote ${out.path} (${bytes.length} bytes)');
    expect(bytes.length, greaterThan(1000));
  });
}
