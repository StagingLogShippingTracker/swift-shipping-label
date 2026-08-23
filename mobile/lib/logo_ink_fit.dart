import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'logo_image_process.dart';
import 'logo_import_options.dart';

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

  /// Ink width / height. Circles and squares are near 1.0.
  double get aspectRatio =>
      (!isValid || height <= 0) ? 1.0 : width / height;

  /// Near 1:1 (square, square-ish, or circular) vs clearly wider-than-tall.
  ///
  /// Legacy BOL / wide-lockup threshold. Shipping uses [isSquareOrCircle].
  static const squareIshAspectMax = 1.4;

  /// True for circles / squares / near-square lockups (red height target).
  bool get isSquareIsh => aspectRatio <= squareIshAspectMax;

  /// Shipping / Receiving shape slot: square or circular (red box height).
  ///
  /// Aspect ratio in [0.8, 1.3] → tall red slot; outside → green rectangular slot.
  bool get isSquareOrCircle {
    if (!isValid || height <= 0) return true;
    final ar = width / height;
    return ar >= 0.8 && ar <= 1.3;
  }

  /// Red vs green shipping header height from [isSquareOrCircle].
  double targetHeight({
    required double squareH,
    required double rectH,
  }) =>
      isSquareOrCircle ? squareH : rectH;

  double scaleForHeight(double targetH) =>
      (!isValid || height <= 0) ? 1 : targetH / height;

  /// Drawn bitmap width so the ink box is [targetH] points tall.
  double drawWidth(double targetH) => canvasW * scaleForHeight(targetH);

  /// Ink-box width at [targetH] (layout / pink-limit budget; excludes canvas pad).
  double inkDrawWidth(double targetH) => width * scaleForHeight(targetH);

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

  /// Uniform scale ≤ 1 so [drawWidth]s + fixed [gap]s fit [maxTotalW] (pink limit).
  ///
  /// Gaps are not scaled — only logo heights shrink.
  static double uniformWidthFitScale(
    List<LogoInkMetrics> inks,
    List<double> heights,
    double gap,
    double maxTotalW,
  ) {
    if (inks.isEmpty || maxTotalW <= 0 || inks.length != heights.length) {
      return 1;
    }
    var inkW = 0.0;
    for (var i = 0; i < inks.length; i++) {
      inkW += inks[i].inkDrawWidth(heights[i]);
    }
    final gaps = inks.length > 1 ? gap * (inks.length - 1) : 0.0;
    final budget = maxTotalW - gaps;
    if (inkW <= 0) return 1;
    if (budget <= 0) return 0.01;
    if (inkW <= budget) return 1;
    return budget / inkW;
  }

  /// Per-logo ink scale factors for Shipping / Receiving header rows.
  ///
  /// Each logo starts at 100% of its red/green slot height; uniformly shrinks
  /// only when total ink width + gaps exceeds [maxTotalW] (pink line limit).
  /// Inter-logo gaps are fixed — only logo scales shrink.
  static List<double> rowScalesForPinkLimit(
    List<LogoInkMetrics> inks,
    double squareH,
    double rectH,
    double gap,
    double maxTotalW,
  ) {
    if (inks.isEmpty || maxTotalW <= 0) return [];
    final scales = <double>[
      for (final ink in inks)
        ink.scaleForHeight(
          ink.isSquareOrCircle ? squareH : rectH,
        ),
    ];
    var inkW = 0.0;
    for (var i = 0; i < inks.length; i++) {
      inkW += inks[i].width * scales[i];
    }
    final gaps = inks.length > 1 ? gap * (inks.length - 1) : 0.0;
    final totalW = inkW + gaps;
    if (totalW <= maxTotalW || inkW <= 0) return scales;
    final budget = maxTotalW - gaps;
    if (budget <= 0) return [for (var _ in inks) 0.01];
    final shrink = budget / inkW;
    return [for (final s in scales) s * shrink];
  }

  /// PDF y (bitmap bottom-left) so the ink bottom sits on [inkBottomY].
  double bitmapBottomY(double inkBottomY, double targetH) {
    final scale = scaleForHeight(targetH);
    final belowInk = canvasH - top - height;
    return inkBottomY - belowInk * scale;
  }
}

/// Crops every customer logo to real ink for aspect-based PDF sizing.
class LogoInkFit {
  LogoInkFit._();

  static ({Uint8List png, LogoInkMetrics ink}) prepare(Uint8List input) {
    // Avoid a second normalizeToVisibleContent pass on logos that were already
    // knocked out at import — re-halo-strip / re-crop clipped white-outline
    // wordmarks (e.g. GCM "Modification").
    var working = input;
    final decoded = img.decodeImage(input);
    if (decoded != null &&
        !LogoImageProcessor.hasMeaningfulTransparency(input)) {
      working = LogoImageProcessor.processWithOptions(
        input,
        LogoImportOptions.standard(
          removeBackground: true,
          cropMode: LogoCropMode.auto,
        ),
      );
    }
    var ink = measure(working) ??
        LogoInkMetrics(
          canvasW: 1,
          canvasH: 1,
          left: 0,
          top: 0,
          width: 1,
          height: 1,
        );
    final cropped = _cropToInkBounds(working, ink);
    ink = measure(cropped) ?? ink;
    return (png: cropped, ink: ink);
  }

  /// Trim canvas to visible ink only — no pad so PDF scale height = ink height.
  static Uint8List _cropToInkBounds(Uint8List png, LogoInkMetrics ink) {
    if (!ink.isValid || png.isEmpty) return png;
    final image = img.decodeImage(png);
    if (image == null) return png;
    final x = ink.left;
    final y = ink.top;
    final w = ink.width;
    final h = ink.height;
    if (w <= 0 || h <= 0) return png;
    if (x == 0 && y == 0 && w == image.width && h == image.height) {
      return png;
    }
    return Uint8List.fromList(
      img.encodePng(img.copyCrop(image, x: x, y: y, width: w, height: h)),
    );
  }

  /// Bounding box of opaque ink including light outlines (full artwork AABB).
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
        // Include white letter outlines — skipping them clipped GCM "Modification".
        if (p.a.toInt() < 96) continue;
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        final sat = math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));
        final lum = (r + g + b) / 3.0;
        // Leftover photo / JPEG plate must not inflate the ink AABB — that
        // makes rectangular logos look tiny when scaled to green/red targets.
        if (lum >= 235 && sat <= 18) continue;
        if (lum >= 210 && sat <= 12) continue;
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

  /// Rasterize ink to exactly [inkHeightPt] tall (PDF pt = bitmap px at 72dpi).
  ///
  /// Guarantees `drawImage(..., w, h)` fills the red/green cell — no letterboxing
  /// from transparent canvas padding.
  static ({Uint8List png, LogoInkMetrics ink}) scaleToInkHeight(
    Uint8List png,
    LogoInkMetrics ink,
    double inkHeightPt,
  ) {
    if (!ink.isValid || inkHeightPt <= 0 || png.isEmpty) {
      return (png: png, ink: ink);
    }
    final wPt = ink.inkDrawWidth(inkHeightPt);
    final wPx = math.max(1, wPt.round());
    final hPx = math.max(1, inkHeightPt.round());
    final im = img.decodeImage(png);
    if (im == null) return (png: png, ink: ink);
    final resized = img.copyResize(
      im,
      width: wPx,
      height: hPx,
      interpolation: img.Interpolation.linear,
    );
    final out = Uint8List.fromList(img.encodePng(resized));
    final synced = LogoInkMetrics(
      canvasW: wPx,
      canvasH: hPx,
      left: 0,
      top: 0,
      width: wPx,
      height: hPx,
    );
    return (png: out, ink: synced);
  }
}
