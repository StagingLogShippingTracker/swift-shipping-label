import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/label_data.dart';
import 'package:swift_shipping_label/pdf/shipping_label_pdf.dart';
import 'package:swift_shipping_label/pdf_render_options.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate Shipping + Receiving samples with Montserrat entry fields',
      () async {
    // Clear cached singleton so newly added Montserrat fonts load.
    // ignore: invalid_use_of_visible_for_testing_member
    // (no public reset — force via fresh isolate in flutter test)

    final shipping = await ShippingLabelPdf.load();
    final root = Directory.current.parent.path;
    final sep = Platform.pathSeparator;
    const options = PdfRenderOptions(bodyFont: PdfBodyFont.montserrat);

    Uint8List? logo;
    try {
      final data =
          await rootBundle.load('assets/images/sample_customer_logo.png');
      logo = data.buffer.asUint8List();
    } catch (_) {}
    final logos = logo == null ? <Uint8List>[] : [logo];

    final shipBytes = await shipping.build(
      data: ShippingLabelData.sample,
      customerLogoBytes: logos,
      piecePlan: const PieceCountPlan(palletCrates: 2, boxes: 0),
      options: options,
    );
    final shipOut = File(
      '$root${sep}Swift Supply Shipping Label - Sample (Montserrat).pdf',
    );
    await shipOut.writeAsBytes(shipBytes);

    final recvBytes = await shipping.buildReceiving(
      data: ShippingLabelData.receivingSample,
      customerLogoBytes: logos,
      options: options,
    );
    final recvOut = File(
      '$root${sep}Swift Supply Receiving Label - Sample (Montserrat).pdf',
    );
    await recvOut.writeAsBytes(recvBytes);

    // ignore: avoid_print
    print('Wrote:\n  ${shipOut.path}\n  ${recvOut.path}');
    expect(shipBytes.length, greaterThan(1000));
    expect(recvBytes.length, greaterThan(1000));
  });
}
