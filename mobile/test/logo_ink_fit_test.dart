import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:swift_shipping_label/logo_ink_fit.dart';

Uint8List _png(img.Image image) => Uint8List.fromList(img.encodePng(image));

void main() {
  test('padded square and padded wide mark get the same ink draw height', () {
    const targetH = 62.24;

    final squareCanvas = img.Image(width: 200, height: 200, numChannels: 4);
    img.fill(squareCanvas, color: img.ColorRgba8(255, 255, 255, 255));
    img.fillRect(
      squareCanvas,
      x1: 70,
      y1: 70,
      x2: 129,
      y2: 129,
      color: img.ColorRgba8(30, 140, 70, 255),
    );

    final wideCanvas = img.Image(width: 400, height: 180, numChannels: 4);
    img.fill(wideCanvas, color: img.ColorRgba8(0, 0, 0, 0));
    img.fillRect(
      wideCanvas,
      x1: 20,
      y1: 60,
      x2: 379,
      y2: 119,
      color: img.ColorRgba8(180, 40, 40, 255),
    );

    final square = LogoInkFit.prepare(_png(squareCanvas));
    final wide = LogoInkFit.prepare(_png(wideCanvas));

    expect(square.ink.height, closeTo(60, 4));
    expect(wide.ink.height, closeTo(60, 4));
    expect(wide.ink.width / wide.ink.height, greaterThan(4));

    // Safe-pad makes the bitmap slightly taller than the ink box; ink height
    // itself still maps exactly to Swift's target.
    expect(square.ink.drawHeight(targetH), greaterThanOrEqualTo(targetH));
    expect(wide.ink.drawHeight(targetH), greaterThanOrEqualTo(targetH));
    expect(square.ink.drawHeight(targetH), lessThan(targetH * 1.15));
    expect(wide.ink.drawHeight(targetH), lessThan(targetH * 1.15));
    expect(square.ink.height * square.ink.scaleForHeight(targetH), closeTo(targetH, 0.001));
    expect(wide.ink.height * wide.ink.scaleForHeight(targetH), closeTo(targetH, 0.001));
  });

  test('black-canvas square is sized by the colored mark, not the plate', () {
    final canvas = img.Image(width: 160, height: 160, numChannels: 4);
    img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 255));
    img.fillRect(
      canvas,
      x1: 50,
      y1: 50,
      x2: 109,
      y2: 109,
      color: img.ColorRgba8(220, 90, 30, 255),
    );

    final prepared = LogoInkFit.prepare(_png(canvas));
    expect(prepared.ink.height, lessThan(80));
    expect(prepared.ink.width, lessThan(80));
    expect(prepared.ink.height, greaterThan(50));
    const targetH = 62.24;
    expect(
      prepared.ink.height * prepared.ink.scaleForHeight(targetH),
      closeTo(targetH, 0.001),
    );
  });

  test('wide wordmark shrinks uniformly to fit a BOL left frame', () {
    final canvas = img.Image(width: 500, height: 120, numChannels: 4);
    img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
    img.fillRect(
      canvas,
      x1: 10,
      y1: 20,
      x2: 489,
      y2: 99,
      color: img.ColorRgba8(160, 30, 30, 255),
    );
    final ink = LogoInkFit.prepare(_png(canvas)).ink;
    const targetH = 59.0;
    const frameW = 220.0;
    expect(ink.drawWidth(targetH), greaterThan(frameW));

    final fittedH = LogoInkMetrics.fitHeightToWidth(ink, targetH, frameW);
    expect(fittedH, lessThan(targetH));
    expect(ink.drawWidth(fittedH), lessThanOrEqualTo(frameW + 0.01));
  });

  test('wide wordmark is not sliced into a thin strip', () {
    final canvas = img.Image(width: 500, height: 120, numChannels: 4);
    img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
    img.fillRect(
      canvas,
      x1: 10,
      y1: 20,
      x2: 489,
      y2: 99,
      color: img.ColorRgba8(160, 30, 30, 255),
    );
    final prepared = LogoInkFit.prepare(_png(canvas));
    expect(prepared.ink.height, greaterThan(70));
    expect(prepared.ink.width, greaterThan(400));
  });

  test('real customer logos: square vs wide share Swift ink height', () {
    final root = Directory.current.parent;
    final bfl = File('${root.path}/customer_logos/bfl fabricators.png');
    final arc = File('${root.path}/customer_logos/Arc Resources LTD.png');
    if (!bfl.existsSync() || !arc.existsSync()) {
      return;
    }

    const targetH = 62.24;
    final square = LogoInkFit.prepare(bfl.readAsBytesSync());
    final wide = LogoInkFit.prepare(arc.readAsBytesSync());

    expect(wide.ink.width / wide.ink.height, greaterThan(2.5));
    expect(
      square.ink.height * square.ink.scaleForHeight(targetH),
      closeTo(targetH, 0.001),
    );
    expect(
      wide.ink.height * wide.ink.scaleForHeight(targetH),
      closeTo(targetH, 0.001),
    );
  });

  test('bird wordmark on black keeps green+orange and Swift ink height', () {
    final root = Directory.current.parent;
    final bird = File('${root.path}/customer_logos/bird_source.png');
    if (!bird.existsSync()) return;

    const targetH = 62.24;
    final prepared = LogoInkFit.prepare(bird.readAsBytesSync());
    expect(prepared.ink.width / prepared.ink.height, greaterThan(2));
    expect(
      prepared.ink.height * prepared.ink.scaleForHeight(targetH),
      closeTo(targetH, 0.001),
    );
    // Must not collapse to the orange accent alone (that drew huge/cut-off).
    expect(prepared.ink.width / prepared.ink.height, lessThan(4.5));

    final im = img.decodeImage(prepared.png)!;
    var green = 0, orange = 0;
    for (var y = 0; y < im.height; y += 2) {
      for (var x = 0; x < im.width; x += 2) {
        final p = im.getPixel(x, y);
        if (p.a.toInt() < 96) continue;
        final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
        if (g > r + 20 && g > b + 20) green++;
        if (r > 180 && g < 140 && b < 90) orange++;
      }
    }
    expect(green, greaterThan(orange));
    expect(orange, greaterThan(0));
  });
}
