import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:swift_shipping_label/logo_image_process.dart';
import 'package:swift_shipping_label/logo_restorer.dart';

void main() {
  test('finalizeRestoredPng scales height to 3000', () {
    final src = img.Image(width: 80, height: 80, numChannels: 4);
    img.fill(src, color: img.ColorRgba8(20, 120, 40, 255));
    final out = LogoRestorer.finalizeRestoredPng(
      Uint8List.fromList(img.encodePng(src)),
    );
    final decoded = img.decodeImage(out)!;
    expect(decoded.height, LogoRestorer.minDimension);
    expect(decoded.width, greaterThan(1000));
  });

  test('flattenSolidBrandFills collapses mottled interiors of any hues to solids',
      () {
    // Teal + magenta — not orange/green — so the pass is color-agnostic.
    const teal = (18, 168, 164);
    const magenta = (188, 28, 156);
    final src = img.Image(width: 120, height: 80, numChannels: 4);
    img.fill(src, color: img.ColorRgba8(0, 0, 0, 0));
    for (var y = 8; y < 36; y++) {
      for (var x = 8; x < 112; x++) {
        final n = ((x * 13 + y * 7) % 11) - 5;
        src.setPixelRgba(x, y, teal.$1 + n, teal.$2 + n, teal.$3 + n ~/ 2, 255);
      }
    }
    for (var y = 44; y < 72; y++) {
      for (var x = 8; x < 112; x++) {
        final n = ((x * 5 + y * 11) % 9) - 4;
        src.setPixelRgba(
          x,
          y,
          magenta.$1 + n,
          magenta.$2 + n,
          magenta.$3 + n ~/ 2,
          255,
        );
      }
    }

    final out = LogoImageProcessor.flattenSolidBrandFills(src);
    final a = out.getPixel(60, 20);
    final a2 = out.getPixel(40, 22);
    expect(a.r.toInt(), a2.r.toInt());
    expect(a.g.toInt(), a2.g.toInt());
    expect(a.b.toInt(), a2.b.toInt());

    final b = out.getPixel(60, 56);
    final b2 = out.getPixel(40, 58);
    expect(b.r.toInt(), b2.r.toInt());
    expect(b.g.toInt(), b2.g.toInt());
    expect(b.b.toInt(), b2.b.toInt());
    expect((a.r.toInt() - b.r.toInt()).abs(), greaterThan(40));
    expect((a.g.toInt() - b.g.toInt()).abs(), greaterThan(40));
  });

  test('rebuildPredictedEdges paints solid fills with smooth masks', () {
    final src = img.Image(width: 40, height: 40, numChannels: 4);
    img.fill(src, color: img.ColorRgba8(255, 255, 255, 255));
    img.fillRect(
      src,
      x1: 8,
      y1: 8,
      x2: 31,
      y2: 31,
      color: img.ColorRgba8(200, 30, 30, 255),
    );
    src.setPixelRgba(8, 12, 80, 80, 80, 255);
    src.setPixelRgba(31, 20, 40, 40, 40, 255);
    final out = LogoImageProcessor.rebuildPredictedEdges(src, targetHeight: 80);
    expect(out.height, 80);
    final mid = out.getPixel(out.width ~/ 2, out.height ~/ 2);
    expect(mid.r.toInt(), greaterThan(120));
    expect(mid.a.toInt(), greaterThan(200));
  });

  test('ensureLetterOutline restores a dropped black text stroke', () {
    final source = img.Image(width: 40, height: 40, numChannels: 4);
    img.fill(source, color: img.ColorRgba8(255, 255, 255, 255));
    img.fillRect(
      source,
      x1: 8,
      y1: 8,
      x2: 31,
      y2: 31,
      color: img.ColorRgba8(0, 0, 0, 255),
    );
    img.fillRect(
      source,
      x1: 12,
      y1: 12,
      x2: 27,
      y2: 27,
      color: img.ColorRgba8(200, 40, 40, 255),
    );

    final restored = img.Image(width: 40, height: 40, numChannels: 4);
    img.fill(restored, color: img.ColorRgba8(255, 255, 255, 255));
    img.fillRect(
      restored,
      x1: 12,
      y1: 12,
      x2: 27,
      y2: 27,
      color: img.ColorRgba8(200, 40, 40, 255),
    );

    expect(LogoImageProcessor.detectLetterOutline(source), isNotNull);
    expect(LogoImageProcessor.detectLetterOutline(source)!.r, 0);
    expect(LogoImageProcessor.detectLetterOutline(source)!.g, 0);
    expect(LogoImageProcessor.detectLetterOutline(source)!.b, 0);
    final out = LogoImageProcessor.ensureLetterOutline(source, restored);
    final border = out.getPixel(10, 20);
    expect(border.r.toInt() + border.g.toInt() + border.b.toInt(), lessThan(80));
    expect(border.a.toInt(), greaterThan(200));
  });
}
