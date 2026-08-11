import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

import 'logo_import_options.dart';

/// Smart crop + solid-background removal for customer logos.
///
/// Crop only removes empty outer margin (transparent / solid-bg padding).
/// Logo artwork is never trimmed — a small safe pad is kept after crop.
class LogoImageProcessor {
  LogoImageProcessor._();

  static const alphaThreshold = 12;
  static const colorTolerance = 26;
  static const paddingFraction = 0.03;
  static const minPadding = 2;
  static const maxPadding = 14;
  /// Extra pixels kept inside the crop so anti-aliased edges are not clipped.
  static const safeInset = 1;

  /// Decode, trim empty margins, remove solid backgrounds, re-encode PNG.
  static Uint8List process(Uint8List input) =>
      processWithOptions(input, LogoImportOptions.standard());

  /// Crop to opaque / non-background content bounds so PDF height matching
  /// uses the visible artwork, not transparent (or flat) padding.
  ///
  /// Uses a true pixel bounding-box (not whole-row peeling), so soft shadows
  /// or single fringe pixels cannot keep large empty margins around square icons.
  static Uint8List normalizeToVisibleContent(Uint8List input) {
    if (input.isEmpty) return input;
    final decoded = img.decodeImage(input);
    if (decoded == null) return input;

    var image = decoded.numChannels == 4
        ? decoded.clone()
        : decoded.convert(numChannels: 4);

    // Transparent padding → alpha. Opaque white/flat canvas → bg match.
    final bg = _hasMeaningfulTransparency(image)
        ? null
        : _estimateBackgroundColor(image);

    final beforeW = image.width;
    final beforeH = image.height;
    // Ignore faint anti-alias / drop-shadow fringe when finding the ink box.
    image = _cropToContentBBox(image, bg, minAlpha: 40);

    if (image.width == beforeW && image.height == beforeH) {
      // Fallback: looser alpha peel if bbox found nothing new.
      image = _trimEmptyMargins(image, bg);
      if (image.width == beforeW &&
          image.height == beforeH &&
          decoded.numChannels == 4) {
        return input;
      }
    }

    // Minimal pad only (1px) — large pad would shrink visible ink vs Swift again.
    image = _addPadding(image, fraction: 0.01, minPad: 1, maxPad: 4);
    return Uint8List.fromList(img.encodePng(image));
  }

  /// Apply [options]: optional manual crop, bg removal, auto margin trim.
  static Uint8List processWithOptions(
    Uint8List input,
    LogoImportOptions options,
  ) {
    // True leave-as-is: no crop and no background strip.
    if (options.cropMode == LogoCropMode.none && !options.removeBackground) {
      return input;
    }

    final decoded = img.decodeImage(input);
    if (decoded == null) return input;

    var image = decoded.numChannels == 4
        ? decoded.clone()
        : decoded.convert(numChannels: 4);

    if (options.cropMode == LogoCropMode.manual &&
        options.manualCropRect != null) {
      image = _applyManualCrop(image, options.manualCropRect!);
    }

    final bg = options.removeBackground && !_hasMeaningfulTransparency(image)
        ? _estimateBackgroundColor(image)
        : null;

    if (bg != null) {
      _removeSolidBackground(image, bg);
    }

    if (options.cropMode == LogoCropMode.auto) {
      image = _trimEmptyMargins(image, bg);
      image = _addPadding(image);
    }

    return Uint8List.fromList(img.encodePng(image));
  }

  /// Prepare a saved/drawn signature for BOL embed: knock out white/light
  /// paper background to transparent ink, then crop to the stroke bounds.
  ///
  /// Without this, a large white PNG canvas is fit into a tiny signature cell
  /// and the ink looks microscopic while the white plate covers other fields.
  static Uint8List prepareSignatureInk(Uint8List input) {
    if (input.isEmpty) return input;
    final decoded = img.decodeImage(input);
    if (decoded == null) return input;

    var image = decoded.numChannels == 4
        ? decoded.clone()
        : decoded.convert(numChannels: 4);

    final w = image.width;
    final h = image.height;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        final a = p.a.toInt();
        if (a < alphaThreshold) {
          image.setPixelRgba(x, y, 0, 0, 0, 0);
          continue;
        }
        // Darkness of the stroke (white paper → 0, black ink → 255).
        final ink = (255 - ((r + g + b) / 3.0)).round().clamp(0, 255);
        if (ink < 18) {
          image.setPixelRgba(x, y, 0, 0, 0, 0);
        } else {
          // Solid black ink with alpha from darkness (anti-aliased edges).
          final outA = (ink * a / 255.0).round().clamp(0, 255);
          image.setPixelRgba(x, y, 0, 0, 0, outA);
        }
      }
    }

    image = _cropToContentBBox(image, null, minAlpha: 24);
    image = _addPadding(image, fraction: 0.04, minPad: 2, maxPad: 8);
    return Uint8List.fromList(img.encodePng(image));
  }

  static img.Image _applyManualCrop(img.Image image, Rect normalized) {
    final left = (normalized.left * image.width).round().clamp(0, image.width - 1);
    final top = (normalized.top * image.height).round().clamp(0, image.height - 1);
    final right =
        (normalized.right * image.width).round().clamp(left + 1, image.width);
    final bottom =
        (normalized.bottom * image.height).round().clamp(top + 1, image.height);
    return img.copyCrop(
      image,
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );
  }

  /// True when border pixels are already mostly transparent (good PNG).
  static bool _hasMeaningfulTransparency(img.Image image) {
    final w = image.width;
    final h = image.height;
    if (w < 2 || h < 2) return false;

    var transparent = 0;
    var total = 0;

    void sample(int x, int y) {
      final a = image.getPixel(x, y).a.toInt();
      total++;
      if (a < alphaThreshold) transparent++;
    }

    for (var x = 0; x < w; x++) {
      sample(x, 0);
      sample(x, h - 1);
    }
    for (var y = 1; y < h - 1; y++) {
      sample(0, y);
      sample(w - 1, y);
    }

    return total > 0 && transparent / total >= 0.35;
  }

  static void _removeSolidBackground(
    img.Image image,
    (int r, int g, int b) bg,
  ) {
    final w = image.width;
    final h = image.height;
    final visited = Uint8List(w * h);
    final queue = <(int, int)>[];

    void trySeed(int x, int y) {
      if (x < 0 || y < 0 || x >= w || y >= h) return;
      final idx = y * w + x;
      if (visited[idx] != 0) return;
      if (!_isEmptyPixel(image.getPixel(x, y), bg)) return;
      visited[idx] = 1;
      queue.add((x, y));
    }

    for (var x = 0; x < w; x++) {
      trySeed(x, 0);
      trySeed(x, h - 1);
    }
    for (var y = 0; y < h; y++) {
      trySeed(0, y);
      trySeed(w - 1, y);
    }

    while (queue.isNotEmpty) {
      final (x, y) = queue.removeLast();
      image.setPixelRgba(x, y, 0, 0, 0, 0);

      trySeed(x + 1, y);
      trySeed(x - 1, y);
      trySeed(x, y + 1);
      trySeed(x, y - 1);
    }
  }

  /// Sample corner regions; return a shared bg color when corners agree.
  static (int r, int g, int b)? _estimateBackgroundColor(img.Image image) {
    final w = image.width;
    final h = image.height;
    final samples = <img.Pixel>[];

    void corner(int cx, int cy) {
      final radius = math.min(3, math.min(w, h));
      for (var dy = 0; dy < radius; dy++) {
        for (var dx = 0; dx < radius; dx++) {
          final x = (cx + dx).clamp(0, w - 1);
          final y = (cy + dy).clamp(0, h - 1);
          samples.add(image.getPixel(x, y));
        }
      }
    }

    corner(0, 0);
    corner(w - 3, 0);
    corner(0, h - 3);
    corner(w - 3, h - 3);

    if (samples.isEmpty) return null;

    final rs = samples.map((p) => p.r.toInt()).toList()..sort();
    final gs = samples.map((p) => p.g.toInt()).toList()..sort();
    final bs = samples.map((p) => p.b.toInt()).toList()..sort();
    final mid = samples.length ~/ 2;
    final mr = rs[mid];
    final mg = gs[mid];
    final mb = bs[mid];

    var agree = 0;
    for (final p in samples) {
      if (_colorDistance(p.r.toInt(), p.g.toInt(), p.b.toInt(), mr, mg, mb) <=
          colorTolerance) {
        agree++;
      }
    }
    if (agree / samples.length < 0.75) return null;

    return (mr, mg, mb);
  }

  /// Empty = transparent or matches known flat background (margin only).
  static bool _isEmptyPixel(img.Pixel pixel, (int r, int g, int b)? bg) {
    if (pixel.a.toInt() < alphaThreshold) return true;
    if (bg == null) return false;
    return _colorDistance(
          pixel.r.toInt(),
          pixel.g.toInt(),
          pixel.b.toInt(),
          bg.$1,
          bg.$2,
          bg.$3,
        ) <=
        colorTolerance;
  }

  static int _colorDistance(int r1, int g1, int b1, int r2, int g2, int b2) {
    return math.max(
      (r1 - r2).abs(),
      math.max((g1 - g2).abs(), (b1 - b2).abs()),
    );
  }

  /// Pixel AABB of "solid" content (ignores faint fringe below [minAlpha]).
  static img.Image _cropToContentBBox(
    img.Image image,
    (int r, int g, int b)? bg, {
    int minAlpha = 40,
  }) {
    var minX = image.width;
    var minY = image.height;
    var maxX = -1;
    var maxY = -1;

    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        if (p.a.toInt() < minAlpha) continue;
        if (bg != null &&
            _colorDistance(
                  p.r.toInt(),
                  p.g.toInt(),
                  p.b.toInt(),
                  bg.$1,
                  bg.$2,
                  bg.$3,
                ) <=
                colorTolerance) {
          continue;
        }
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }

    if (maxX < minX || maxY < minY) return image;

    minX = math.max(0, minX - safeInset);
    minY = math.max(0, minY - safeInset);
    maxX = math.min(image.width - 1, maxX + safeInset);
    maxY = math.min(image.height - 1, maxY + safeInset);

    return img.copyCrop(
      image,
      x: minX,
      y: minY,
      width: maxX - minX + 1,
      height: maxY - minY + 1,
    );
  }

  /// Peel only fully empty outer rows/columns — never shrink into artwork.
  static img.Image _trimEmptyMargins(
    img.Image image,
    (int r, int g, int b)? bg,
  ) {
    var top = 0;
    var left = 0;
    var bottom = image.height - 1;
    var right = image.width - 1;

    bool rowEmpty(int y) {
      for (var x = left; x <= right; x++) {
        if (!_isEmptyPixel(image.getPixel(x, y), bg)) return false;
      }
      return true;
    }

    bool colEmpty(int x) {
      for (var y = top; y <= bottom; y++) {
        if (!_isEmptyPixel(image.getPixel(x, y), bg)) return false;
      }
      return true;
    }

    while (top < bottom && rowEmpty(top)) {
      top++;
    }
    while (bottom > top && rowEmpty(bottom)) {
      bottom--;
    }
    while (left < right && colEmpty(left)) {
      left++;
    }
    while (right > left && colEmpty(right)) {
      right--;
    }

    if (top == 0 &&
        left == 0 &&
        bottom == image.height - 1 &&
        right == image.width - 1) {
      return image;
    }

    // Keep a tiny safe inset so anti-aliased logo edges are not clipped.
    top = math.max(0, top - safeInset);
    left = math.max(0, left - safeInset);
    bottom = math.min(image.height - 1, bottom + safeInset);
    right = math.min(image.width - 1, right + safeInset);

    return img.copyCrop(
      image,
      x: left,
      y: top,
      width: right - left + 1,
      height: bottom - top + 1,
    );
  }

  static img.Image _addPadding(
    img.Image image, {
    double fraction = paddingFraction,
    int minPad = minPadding,
    int maxPad = maxPadding,
  }) {
    final side = math.max(image.width, image.height);
    final pad =
        (side * fraction).round().clamp(minPad, maxPad).toInt();

    final out = img.Image(
      width: image.width + pad * 2,
      height: image.height + pad * 2,
      numChannels: 4,
    );

    img.compositeImage(out, image, dstX: pad, dstY: pad);
    return out;
  }
}
