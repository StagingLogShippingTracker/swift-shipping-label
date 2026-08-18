import 'dart:math' as math;
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

  /// Drawn bitmap height (may exceed [targetH] when canvas pad remains).
  double drawHeight(double targetH) => canvasH * scaleForHeight(targetH);

  /// Lower [targetH] uniformly so draw width fits [maxW] (never upscale).
  static double fitHeightToWidth(
    LogoInkMetrics ink,
    double targetH,
    double maxW,
  ) {
    if (!ink.isValid || maxW <= 0 || targetH <= 0) return targetH;
    final w = ink.drawWidth(targetH);
    if (w <= maxW) return targetH;
    return targetH * maxW / w;
  }

  /// Shared ink height for dual-logo cells — same pt height, each fits its cell.
  static double sharedHeightForCells(
    Iterable<LogoInkMetrics> inks,
    double targetH,
    double cellW,
  ) {
    var h = targetH;
    for (final ink in inks) {
      h = math.min(h, fitHeightToWidth(ink, targetH, cellW));
    }
    return h;
  }

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
    final normalized = LogoImageProcessor.normalizeToVisibleContent(input);
    var ink = measure(normalized) ??
        LogoInkMetrics(
          canvasW: 1,
          canvasH: 1,
          left: 0,
          top: 0,
          width: 1,
          height: 1,
        );
    final cropped = _cropToInkBounds(normalized, ink);
    ink = measure(cropped) ?? ink;
    return (png: cropped, ink: ink);
  }

  /// Trim canvas to visible ink (+ tiny pad) so PDF scale uses artwork bounds.
  static Uint8List _cropToInkBounds(Uint8List png, LogoInkMetrics ink) {
    if (!ink.isValid || png.isEmpty) return png;
    final image = img.decodeImage(png);
    if (image == null) return png;
    const pad = 2;
    final x = math.max(0, ink.left - pad);
    final y = math.max(0, ink.top - pad);
    final w = math.min(
      image.width - x,
      ink.width + pad * 2,
    );
    final h = math.min(
      image.height - y,
      ink.height + pad * 2,
    );
    if (w <= 0 || h <= 0) return png;
    if (x == 0 &&
        y == 0 &&
        w == image.width &&
        h == image.height) {
      return png;
    }
    return Uint8List.fromList(
      img.encodePng(img.copyCrop(image, x: x, y: y, width: w, height: h)),
    );
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
