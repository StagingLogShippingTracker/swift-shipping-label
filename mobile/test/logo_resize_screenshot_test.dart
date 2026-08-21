import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/label_data.dart';
import 'package:swift_shipping_label/pdf/shipping_label_pdf.dart';

/// Shipping + Receiving PDFs for two customers so header logo height can be verified.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('screenshot PDFs: two customers, shipping + receiving', () async {
    final shipping = await ShippingLabelPdf.load();
    final root = Directory.current.parent;
    final logosDir = Directory('${root.path}/customer_logos');
    final outDir = Directory('${root.path}/filled/logo_resize_examples');
    await outDir.create(recursive: true);

    Future<Uint8List> loadLogo(String name) async {
      final f = File('${logosDir.path}/$name');
      expect(f.existsSync(), isTrue, reason: f.path);
      return f.readAsBytes();
    }

    final bfl = await loadLogo('bfl fabricators.png');
    final arc = await loadLogo('Arc Resources LTD.png');

    final shipBfl = ShippingLabelData.sample.copy()
      ..set(LabelFields.customer, 'BFL Fabricators');
    final recvBfl = ShippingLabelData.receivingSample.copy()
      ..set(LabelFields.customer, 'BFL Fabricators');
    final shipArc = ShippingLabelData.sample.copy()
      ..set(LabelFields.customer, 'Arc Resources LTD');
    final recvArc = ShippingLabelData.receivingSample.copy()
      ..set(LabelFields.customer, 'Arc Resources LTD');

    final jobs = <(String, Future<Uint8List>)>[
      (
        'shipping_bfl.pdf',
        shipping.build(data: shipBfl, customerLogoBytes: [bfl]),
      ),
      (
        'receiving_bfl.pdf',
        shipping.buildReceiving(data: recvBfl, customerLogoBytes: [bfl]),
      ),
      (
        'shipping_arc.pdf',
        shipping.build(data: shipArc, customerLogoBytes: [arc]),
      ),
      (
        'receiving_arc.pdf',
        shipping.buildReceiving(data: recvArc, customerLogoBytes: [arc]),
      ),
    ];

    for (final job in jobs) {
      final bytes = await job.$2;
      await File('${outDir.path}/${job.$1}').writeAsBytes(bytes);
    }

    // ignore: avoid_print
    print('Wrote PDFs in ${outDir.path}');
  });

  test('screenshot PDFs: square vs rectangular logos', () async {
    final shipping = await ShippingLabelPdf.load();
    final root = Directory.current.parent;
    final logosDir = Directory('${root.path}/customer_logos');
    final outDir = Directory('${root.path}/filled/logo_resize_examples');
    await outDir.create(recursive: true);

    Future<Uint8List> loadLogo(String name) async {
      final f = File('${logosDir.path}/$name');
      expect(f.existsSync(), isTrue, reason: f.path);
      return f.readAsBytes();
    }

    // ARJAE is near-square (~1.16). Propak is a wide rectangle (~3.88).
    final square = await loadLogo('ARJAE.png');
    final rect = await loadLogo('Propak-Energy-Services-Logo.png');

    final shipSquare = ShippingLabelData.sample.copy()
      ..set(LabelFields.customer, 'ARJAE');
    final recvRect = ShippingLabelData.receivingSample.copy()
      ..set(LabelFields.customer, 'Propak Energy Services');

    final jobs = <(String, Future<Uint8List>)>[
      (
        'shipping_square_arjae.pdf',
        shipping.build(data: shipSquare, customerLogoBytes: [square]),
      ),
      (
        'receiving_rect_propak.pdf',
        shipping.buildReceiving(data: recvRect, customerLogoBytes: [rect]),
      ),
    ];

    for (final job in jobs) {
      final bytes = await job.$2;
      await File('${outDir.path}/${job.$1}').writeAsBytes(bytes);
    }

    // ignore: avoid_print
    print('Wrote square/rect PDFs in ${outDir.path}');
  });
}
