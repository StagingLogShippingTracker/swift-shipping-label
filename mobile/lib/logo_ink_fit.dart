import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'logo_image_process.dart';

/// Visible-ink box inside a logo bitmap.
///
/// PDF drawing uses [height] (not the full canvas) as the Swift-matching
/// top-to-bottom size so transparent / white / black padding cannot shrink
/// the mark.
class LogoInkMetrics {
  const LogoInkMetrics({
    required this.canvasW,
    required this.canvasH,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final int canvasW;
  final int canvasH;
  final int left;
  final int top;
  final int width;
  final int height;

  bool get isValid => width > 0 && height > 0 && canvasW > 0 && canvasH > 0;

  double scaleForHeight(double targetH) =>
      (!isValid || height <= 0) ? 1 : targetH / height;

  /// Drawn bitmap width so the ink box is [targetH] points tall.
  double drawWidth(double targetH) => canvasW * scaleForHeight(targetH);

  /// Drawn bitmap height (may be taller than [targetH] if residual pad remains).
  double drawHeight(double targetH) => canvasH * scaleForHeight(targetH);

  /// PDF y (bitmap bottom-left) so the ink bottom sits on [inkBottomY].
  double bitmapBottomY(double inkBottomY, double targetH) {
    final scale = scaleForHeight(targetH);
    final belowInk = canvasH - top - height;
    return inkBottomY - belowInk * scale;
  }
}

/// Crops every customer logo to real ink, then sizes that ink to Swift height.
class LogoInkFit {
  LogoInkFit._();

  static ({Uint8List png, LogoInkMetrics ink}) prepare(Uint8List input) {
    final png = LogoImageProcessor.normalizeToVisibleContent(input);
    final ink = measure(png) ??
        LogoInkMetrics(
          canvasW: 1,
          canvasH: 1,
          left: 0,
          top: 0,
          width: 1,
          height: 1,
        );
    return (png: png, ink: ink);
  }

  /// Bounding box of opaque, non-white pixels (full artwork AABB — not a
  /// “tallest row-run” slice, which would destroy wide wordmarks).
  static LogoInkMetrics? measure(Uint8List png) {
    if (png.isEmpty) return null;
    final image = img.decodeImage(png);
    if (image == null) return null;
    return measureImage(image);
  }

  static LogoInkMetrics? measureImage(img.Image image) {
    var minX = image.width;
    var minY = image.height;
    var maxX = -1;
    var maxY = -1;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        if (p.a.toInt() < 96) continue;
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        if (r >= 240 && g >= 240 && b >= 240) continue;
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
    if (maxX < minX || maxY < minY) {
      return LogoInkMetrics(
        canvasW: image.width,
        canvasH: image.height,
        left: 0,
        top: 0,
        width: image.width,
        height: image.height,
      );
    }
    return LogoInkMetrics(
      canvasW: image.width,
      canvasH: image.height,
      left: minX,
      top: minY,
      width: maxX - minX + 1,
      height: maxY - minY + 1,
    );
  }
}
