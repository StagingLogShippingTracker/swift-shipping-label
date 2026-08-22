import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/label_data.dart';
import 'package:swift_shipping_label/logo_ink_fit.dart';
import 'package:swift_shipping_label/pdf/shipping_label_pdf.dart';

/// Dual customer logos must each hit their red/green cell height (not shared height).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Arc + square dual: independent red/green cell heights', () async {
    final root = Directory.current.parent;
    final arcFile = File('${root.path}/customer_logos/Arc Resources LTD.png');
    final squareFile = File('${root.path}/customer_logos/bfl fabricators.png');
    expect(arcFile.existsSync(), isTrue);
    expect(squareFile.existsSync(), isTrue);

    const squareH = ShippingLabelPdf.squareLogoTargetH;
    const rectH = ShippingLabelPdf.rectLogoTargetH;

    final arcInk = LogoInkFit.prepare(arcFile.readAsBytesSync()).ink;
    final squareInk = LogoInkFit.prepare(squareFile.readAsBytesSync()).ink;

    expect(arcInk.isSquareIsh, isFalse);
    expect(squareInk.isSquareIsh, isTrue);

    final arcTarget = arcInk.targetHeight(squareH: squareH, rectH: rectH);
    final squareTarget = squareInk.targetHeight(squareH: squareH, rectH: rectH);
    expect(arcTarget, rectH);
    expect(squareTarget, squareH);

    // Pink-limit scale uses ink width, not padded canvas width.
    final scale = LogoInkMetrics.uniformWidthFitScale(
      [arcInk, squareInk],
      [arcTarget, squareTarget],
      ShippingLabelPdf.customerLogoGap,
      500,
    );
    expect(scale, greaterThan(0.85), reason: 'typical frame should not crush both');

    final arcH = arcTarget * scale;
    final squareCellH = squareTarget * scale;
    expect(
      arcInk.height * arcInk.scaleForHeight(arcH),
      closeTo(arcH, 0.5),
      reason: 'Arc ink must fill green cell',
    );
    expect(
      squareInk.height * squareInk.scaleForHeight(squareCellH),
      closeTo(squareCellH, 0.5),
      reason: 'Square ink must fill red cell',
    );
    expect(
      squareCellH / arcH,
      closeTo(squareH / rectH, 0.08),
      reason: 'red/green ratio preserved (not shared tiny height)',
    );

    final shipping = await ShippingLabelPdf.load();
    final bytes = await shipping.build(
      data: ShippingLabelData.sample.copy()
        ..set(LabelFields.customer, 'ARC C/O BFL'),
      customerLogoBytes: [
        arcFile.readAsBytesSync(),
        squareFile.readAsBytesSync(),
      ],
    );
    expect(bytes.length, greaterThan(2000));
  });
}
