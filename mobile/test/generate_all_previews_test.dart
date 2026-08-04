import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/label_data.dart';
import 'package:swift_shipping_label/pdf/bol_label_pdf.dart';
import 'package:swift_shipping_label/pdf/shipping_label_pdf.dart';

Future<List<Uint8List>> _previewLogos(String root, String sep) async {
  final dual = [
    File('$root${sep}customer_logos${sep}EPCOR.png'),
    File('$root${sep}customer_logos${sep}Mastec.png'),
  ];
  if (dual.every((f) => f.existsSync())) {
    return [await dual[0].readAsBytes(), await dual[1].readAsBytes()];
  }
  try {
    final data =
        await rootBundle.load('assets/images/sample_customer_logo.png');
    return [data.buffer.asUint8List()];
  } catch (_) {
    return [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate Shipping, Receiving, and BOL sample PDFs', () async {
    final shipping = await ShippingLabelPdf.load();
    final root = Directory.current.parent.path;
    final sep = Platform.pathSeparator;
    final logos = await _previewLogos(root, sep);

    final shipBytes = await shipping.build(
      data: ShippingLabelData.sample,
      customerLogoBytes: logos,
      piecePlan: const PieceCountPlan(palletCrates: 2, boxes: 0),
    );
    final shipOut = File(
      '$root${sep}Swift Supply Shipping Label - Sample (app).pdf',
    );
    await shipOut.writeAsBytes(shipBytes);

    final recvBytes = await shipping.buildReceiving(
      data: ShippingLabelData.receivingSample,
      customerLogoBytes: logos,
    );
    final recvOut = File(
      '$root${sep}Swift Supply Receiving Label - Sample (app).pdf',
    );
    await recvOut.writeAsBytes(recvBytes);

    final bolBytes = await BolLabelPdf(shipping).build(
      data: ShippingLabelData.bolSample,
      customerLogoBytes: logos,
    );
    final bolOut = File(
      '$root${sep}Swift Supply Bill of Lading - Sample (app).pdf',
    );
    await bolOut.writeAsBytes(bolBytes);

    // ignore: avoid_print
    print('Wrote:\n  ${shipOut.path}\n  ${recvOut.path}\n  ${bolOut.path}');
    expect(shipBytes.length, greaterThan(1000));
    expect(recvBytes.length, greaterThan(1000));
    expect(bolBytes.length, greaterThan(1000));
  });
}
