import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/label_data.dart';
import 'package:swift_shipping_label/pdf/shipping_label_pdf.dart';

/// Generates side-by-side preview PDFs so we can verify square vs wide logos
/// share the same top-to-bottom height as Swift.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('logo height match previews (square + wide)', () async {
    final shipping = await ShippingLabelPdf.load();
    final root = Directory.current.parent; // mobile/ -> repo
    final logosDir = Directory('${root.path}/customer_logos');
    final outDir = Directory('${root.path}/filled');
    await outDir.create(recursive: true);

    Future<Uint8List> loadLogo(String name) async {
      final f = File('${logosDir.path}/$name');
      expect(f.existsSync(), isTrue, reason: f.path);
      return f.readAsBytes();
    }

    final square = await loadLogo('ARJAE.png');
    final wide = await loadLogo('Propak-Energy-Services-Logo.png');
    final sample = ShippingLabelData.sample;

    final squarePdf = await shipping.build(
      data: sample,
      customerLogoBytes: [square],
    );
    final widePdf = await shipping.build(
      data: sample,
      customerLogoBytes: [wide],
    );
    final bothPdf = await shipping.build(
      data: sample,
      customerLogoBytes: [square, wide],
    );

    final squareOut = File('${outDir.path}/_logo_height_square_ARJAE.pdf');
    final wideOut = File('${outDir.path}/_logo_height_wide_Propak.pdf');
    final bothOut = File('${outDir.path}/_logo_height_both.pdf');
    await squareOut.writeAsBytes(squarePdf);
    await wideOut.writeAsBytes(widePdf);
    await bothOut.writeAsBytes(bothPdf);

    // ignore: avoid_print
    print('Wrote:\n  ${squareOut.path}\n  ${wideOut.path}\n  ${bothOut.path}');
  });
}
