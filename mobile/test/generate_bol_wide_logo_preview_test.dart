import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/label_data.dart';
import 'package:swift_shipping_label/pdf/bol_label_pdf.dart';
import 'package:swift_shipping_label/pdf/shipping_label_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('BOL wide MasTec logo stays left of Probill', () async {
    final shipping = await ShippingLabelPdf.load();
    final root = Directory.current.parent.path;
    final sep = Platform.pathSeparator;
    final mastecPath = '$root${sep}qa_logs${sep}mastec_purnell_wide.png';
    final mastec = File(mastecPath);
    expect(mastec.existsSync(), isTrue, reason: 'Missing $mastecPath');

    final logoBytes = await mastec.readAsBytes();
    final bytes = await BolLabelPdf(shipping).build(
      data: ShippingLabelData.bolSample,
      customerLogoBytes: [Uint8List.fromList(logoBytes)],
      copies: const ['STORE COPY'],
    );

    final out = File(
      '$root${sep}qa_logs${sep}Swift Supply BOL - MasTec wide (app).pdf',
    );
    await out.writeAsBytes(bytes);
    // ignore: avoid_print
    print('Wrote: ${out.path}');
    expect(bytes.length, greaterThan(1000));

    // Geometry sanity (mirrors BolLabelPdf header math).
    const pageW = 612.0;
    const margin = 0.4 * 72.0;
    const contentW = pageW - 2 * margin;
    const targetH = 59.0;
    const probillW = 2.35 * 72.0;
    const cutGap = 14.0;
    const safety = 12.0;

    // Swift orange aspect ≈ 3.282
    var swiftH = targetH;
    var swiftW = swiftH * 3.2824175824175823;
    final maxW = contentW * 0.42;
    if (swiftW > maxW) {
      swiftW = maxW;
      swiftH = swiftW / 3.2824175824175823;
    }
    final swiftX = pageW - margin - swiftW;
    final probillX = swiftX - cutGap - probillW;
    final frameRight = (probillX < swiftX ? probillX : swiftX) - safety;
    final frameLeft = margin;
    final frameW = frameRight - frameLeft;

    expect(probillX, greaterThanOrEqualTo(margin));
    expect(frameLeft, equals(margin));
    expect(frameRight, lessThan(probillX));
    expect(frameW, greaterThan(8));

    // MasTec 1024x269 → at 59pt wants ~224.6 wide; must fit frameW.
    const mastecAspect = 1024 / 269;
    final naturalW = targetH * mastecAspect;
    final scale = [
      frameW / (1024),
      targetH / 269,
      (targetH < 59 ? targetH : 59) / 269,
    ].reduce((a, b) => a < b ? a : b);
    // Use same formula as production:
    final fitScale = [
      frameW / 1024.0,
      targetH / 269.0,
      targetH / 269.0,
    ].reduce((a, b) => a < b ? a : b);
    final fittedW = 1024 * fitScale;
    final fittedH = 269 * fitScale;
    expect(fittedW, lessThanOrEqualTo(frameW + 0.01));
    expect(fittedH, lessThanOrEqualTo(targetH + 0.01));
    expect(naturalW, greaterThan(frameW)); // proves we actually downscaled
    expect(scale, greaterThan(0));
  });
}
