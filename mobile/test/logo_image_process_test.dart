import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:swift_shipping_label/logo_image_process.dart';
import 'package:swift_shipping_label/logo_import_options.dart';

void main() {
  test('removes white background and trims padding', () {
    final src = img.Image(width: 120, height: 80, numChannels: 4);
    img.fill(src, color: img.ColorRgba8(255, 255, 255, 255));
    img.fillRect(
      src,
      x1: 40,
      y1: 20,
      x2: 79,
      y2: 59,
      color: img.ColorRgba8(20, 80, 200, 255),
    );

    final input = Uint8List.fromList(img.encodePng(src));
    final out = LogoImageProcessor.process(input);
    final decoded = img.decodePng(out);
    expect(decoded, isNotNull);

    // Tight crop — much smaller than the padded source canvas.
    expect(decoded!.width, lessThan(60));
    expect(decoded.height, lessThan(50));

    // Logo color survives near center.
    final cx = decoded.width ~/ 2;
    final cy = decoded.height ~/ 2;
    final center = decoded.getPixel(cx, cy);
    expect(center.b.toInt(), greaterThan(150));
    expect(center.a.toInt(), greaterThan(200));
  });

  test('trims empty alpha padding on already-transparent PNG', () {
    final src = img.Image(width: 100, height: 60, numChannels: 4);
    img.fill(src, color: img.ColorRgba8(0, 0, 0, 0));
    img.fillRect(
      src,
      x1: 30,
      y1: 10,
      x2: 69,
      y2: 49,
      color: img.ColorRgba8(200, 40, 40, 255),
    );

    final input = Uint8List.fromList(img.encodePng(src));
    final out = LogoImageProcessor.process(input);
    final decoded = img.decodePng(out)!;

    expect(decoded.width, lessThan(50));
    expect(decoded.height, lessThan(50));
    expect(decoded.width, greaterThan(35));
    expect(decoded.height, greaterThan(35));
  });

  test('manual crop extracts normalized region', () {
    final src = img.Image(width: 200, height: 100, numChannels: 4);
    img.fill(src, color: img.ColorRgba8(255, 0, 0, 255));
    img.fillRect(
      src,
      x1: 80,
      y1: 30,
      x2: 119,
      y2: 69,
      color: img.ColorRgba8(0, 255, 0, 255),
    );

    final input = Uint8List.fromList(img.encodePng(src));
    final out = LogoImageProcessor.processWithOptions(
      input,
      LogoImportOptions.standard(
        removeBackground: false,
        cropMode: LogoCropMode.manual,
        manualCropRect: const Rect.fromLTWH(0.4, 0.3, 0.2, 0.4),
      ),
    );
    final decoded = img.decodePng(out)!;
    expect(decoded.width, 40);
    expect(decoded.height, 40);
    expect(decoded.getPixel(20, 20).g.toInt(), greaterThan(200));
  });

  /// Speckled mid-gray photo plate (Inked Energy style): clear outer plate,
  /// keep chromatic graphic + dark wordmark. Guards against over-strip AND
  /// under-strip regressions.
  test('speckled gray photo plate clears while brand ink survives', () {
    final src = img.Image(width: 240, height: 120, numChannels: 4);
    // Textured desk/photo plate — not a flat studio white.
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        final n = ((x * 17 + y * 31) % 28) - 14;
        final lum = (178 + n).clamp(150, 210);
        src.setPixelRgba(x, y, lum, lum - 2, lum - 4, 255);
      }
    }
    // Blue/black mark (Inked-like).
    img.fillCircle(
      src,
      x: 55,
      y: 55,
      radius: 28,
      color: img.ColorRgba8(20, 70, 170, 255),
    );
    img.fillRect(
      src,
      x1: 95,
      y1: 38,
      x2: 210,
      y2: 72,
      color: img.ColorRgba8(18, 18, 18, 255),
    );

    final out = LogoImageProcessor.processWithOptions(
      Uint8List.fromList(img.encodePng(src)),
      LogoImportOptions.standard(
        removeBackground: true,
        cropMode: LogoCropMode.auto,
      ),
    );
    final decoded = img.decodePng(out)!;

    var blue = 0, black = 0, plate = 0, opaque = 0;
    for (var y = 0; y < decoded.height; y++) {
      for (var x = 0; x < decoded.width; x++) {
        final p = decoded.getPixel(x, y);
        if (p.a.toInt() < 40) continue;
        opaque++;
        final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
        final sat = [r, g, b].reduce((a, c) => a > c ? a : c) -
            [r, g, b].reduce((a, c) => a < c ? a : c);
        final lum = (r + g + b) / 3.0;
        if (b > r + 30 && b > g + 20) {
          blue++;
        } else if (lum <= 55 && sat <= 30) {
          black++;
        } else if (sat <= 28 && lum >= 140 && lum <= 220) {
          plate++;
        }
      }
    }

    expect(decoded.getPixel(0, 0).a.toInt(), lessThan(40),
        reason: 'outer plate corner should be transparent');
    expect(blue, greaterThan(80), reason: 'blue graphic must survive');
    expect(black, greaterThan(80), reason: 'dark wordmark must survive');
    expect(plate / opaque, lessThan(0.18),
        reason: 'speckled plate leftovers must be mostly gone');
  });
}
