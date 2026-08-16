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
  /// Edge flood removes white/black/transparent canvas first, then a true
  /// pixel bounding-box (not whole-row peeling) so a square icon on a large
  /// plate is sized by the mark, not the plate.
  static Uint8List normalizeToVisibleContent(Uint8List input) {
    if (input.isEmpty) return input;
    final decoded = img.decodeImage(input);
    if (decoded == null) return input;

    var image = decoded.numChannels == 4
        ? decoded.clone()
        : decoded.convert(numChannels: 4);

    final bg = _estimateBackgroundColor(image);
    if (bg != null) {
      _removeSolidBackground(image, bg);
    }
    // Punch leftover white plate from the edges even when corners were transparent.
    _removeSolidBackground(image, (255, 255, 255));

    final beforeW = image.width;
    final beforeH = image.height;
    image = _cropToContentBBox(image, null, minAlpha: 96);
    image = _trimLowCoverageMargins(image);

    if (image.width == beforeW && image.height == beforeH) {
      image = _trimEmptyMargins(image, bg);
    }

    // Always re-encode the flooded/cropped bitmap — never keep the padded original.
    return Uint8List.fromList(img.encodePng(image));
  }

  /// Collapse JPEG / upscale mottling and weak interior gradients to a single
  /// flat fill per connected region, for every hue. Anti-aliased edges are
  /// left alone so geometry stays sharp.
  static img.Image flattenSolidBrandFills(img.Image source) {
    final image = source.numChannels == 4
        ? source.clone()
        : source.convert(numChannels: 4);
    final w = image.width;
    final h = image.height;
    if (w <= 2 || h <= 2) return image;

    const minAlpha = 200;
    const joinTol = 28;
    const edgeTol = 36;
    final visited = List<bool>.filled(w * h, false);
    final region = <int>[];
    final queue = <int>[];

    bool opaqueAt(int i) {
      final p = image.getPixel(i % w, i ~/ w);
      return p.a.toInt() >= minAlpha;
    }

    int dist(int i, int j) {
      final a = image.getPixel(i % w, i ~/ w);
      final b = image.getPixel(j % w, j ~/ w);
      return _colorDistance(
        a.r.toInt(),
        a.g.toInt(),
        a.b.toInt(),
        b.r.toInt(),
        b.g.toInt(),
        b.b.toInt(),
      );
    }

    bool isEdgePixel(int i) {
      final x = i % w;
      final y = i ~/ w;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) return true;
          final n = image.getPixel(nx, ny);
          if (n.a.toInt() < minAlpha) return true;
          if (dist(i, ny * w + nx) > edgeTol) return true;
        }
      }
      return false;
    }

    for (var i = 0; i < w * h; i++) {
      if (visited[i] || !opaqueAt(i)) continue;
      region.clear();
      queue
        ..clear()
        ..add(i);
      visited[i] = true;
      var qi = 0;
      while (qi < queue.length) {
        final cur = queue[qi++];
        region.add(cur);
        final x = cur % w;
        final y = cur ~/ w;
        for (final n in [cur - 1, cur + 1, cur - w, cur + w]) {
          if (n < 0 || n >= w * h) continue;
          final nx = n % w;
          final ny = n ~/ w;
          if ((nx - x).abs() + (ny - y).abs() != 1) continue;
          if (visited[n] || !opaqueAt(n)) continue;
          if (dist(cur, n) > joinTol) continue;
          visited[n] = true;
          queue.add(n);
        }
      }
      if (region.length < 24) continue;

      final interiors = <int>[];
      for (final idx in region) {
        if (!isEdgePixel(idx)) interiors.add(idx);
      }
      if (interiors.length < 12) continue;

      final rs = interiors.map((idx) => image.getPixel(idx % w, idx ~/ w).r.toInt()).toList()
        ..sort();
      final gs = interiors.map((idx) => image.getPixel(idx % w, idx ~/ w).g.toInt()).toList()
        ..sort();
      final bs = interiors.map((idx) => image.getPixel(idx % w, idx ~/ w).b.toInt()).toList()
        ..sort();
      final mid = interiors.length ~/ 2;
      final fr = rs[mid];
      final fg = gs[mid];
      final fb = bs[mid];
      for (final idx in interiors) {
        final p = image.getPixel(idx % w, idx ~/ w);
        image.setPixelRgba(idx % w, idx ~/ w, fr, fg, fb, p.a.toInt());
      }
    }
    return image;
  }

  /// True when [source] has a dark stroke hugging chromatic fills (not a plate).
  static ({int r, int g, int b, double widthFrac})? detectLetterOutline(
    img.Image source,
  ) {
    final image = source.numChannels == 4 ? source : source.convert(numChannels: 4);
    final w = image.width;
    final h = image.height;
    if (w < 8 || h < 8) return null;
    var fillN = 0;
    var ringN = 0;
    var sr = 0, sg = 0, sb = 0;
    bool isBg(img.Pixel p) {
      if (p.a.toInt() < 40) return true;
      final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
      return r + g + b >= 720 && (r - g).abs() < 36 && (r - b).abs() < 36;
    }

    bool isFill(img.Pixel p) {
      if (p.a.toInt() < 40 || isBg(p)) return false;
      final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
      final lum = (r + g + b) / 3.0;
      final sat = math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));
      return sat > 40 && lum > 55;
    }

    bool isDark(img.Pixel p) {
      if (p.a.toInt() < 40 || isBg(p)) return false;
      final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
      final lum = (r + g + b) / 3.0;
      final sat = math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));
      return lum < 70 && sat < 55;
    }

    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final p = image.getPixel(x, y);
        if (isFill(p)) fillN++;
        if (!isDark(p)) continue;
        var nextFill = false;
        var nextBg = false;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final n = image.getPixel(x + dx, y + dy);
            if (isFill(n)) nextFill = true;
            if (isBg(n)) nextBg = true;
          }
        }
        if (nextFill) {
          ringN++;
          sr += p.r.toInt();
          sg += p.g.toInt();
          sb += p.b.toInt();
        }
      }
    }
    if (ringN < 16 || fillN < 30) return null;
    if (ringN < fillN * 0.03) return null;
    var r = (sr / ringN).round();
    var g = (sg / ringN).round();
    var b = (sb / ringN).round();
    // JPEG black outlines read as navy/brown; lockup strokes are ink black.
    if ((r + g + b) / 3 < 90) {
      r = 0;
      g = 0;
      b = 0;
    }
    return (
      r: r.clamp(0, 255),
      g: g.clamp(0, 255),
      b: b.clamp(0, 255),
      widthFrac: (2.4 / math.min(w, h)).clamp(0.006, 0.03),
    );
  }

  /// Paint a clean even stroke when the source lockup had one and the restore
  /// dropped it (Gemini often treats black borders as background).
  static img.Image ensureLetterOutline(img.Image source, img.Image restored) {
    final hint = detectLetterOutline(source);
    if (hint == null) return restored;
    if (detectLetterOutline(restored) != null) return restored;

    final image = restored.numChannels == 4
        ? restored.clone()
        : restored.convert(numChannels: 4);
    final w = image.width;
    final h = image.height;
    final radius = math.max(2, (math.min(w, h) * hint.widthFrac).round());
    final fill = List<bool>.filled(w * h, false);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        if (p.a.toInt() < 40) continue;
        final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
        final lum = (r + g + b) / 3.0;
        final sat = math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));
        if (sat > 40 && lum > 55) fill[y * w + x] = true;
      }
    }
    var dilate = List<bool>.from(fill);
    for (var pass = 0; pass < radius; pass++) {
      final next = List<bool>.from(dilate);
      for (var y = 1; y < h - 1; y++) {
        for (var x = 1; x < w - 1; x++) {
          final i = y * w + x;
          if (dilate[i]) continue;
          if (dilate[i - 1] ||
              dilate[i + 1] ||
              dilate[i - w] ||
              dilate[i + w]) {
            next[i] = true;
          }
        }
      }
      dilate = next;
    }
    for (var i = 0; i < w * h; i++) {
      if (!dilate[i] || fill[i]) continue;
      image.setPixelRgba(i % w, i ~/ w, hint.r, hint.g, hint.b, 255);
    }
    return image;
  }

  /// Rebuild lettering / shapes with predicted smooth edges.
  ///
  /// Classifies ink into a few solid colors, upsamples each mask with a
  /// blur-threshold so stair-stepped JPEG edges become curves, then paints
  /// dark outline first and fills after.
  static img.Image rebuildPredictedEdges(img.Image source, {int? targetHeight}) {
    final src = source.numChannels == 4
        ? source.clone()
        : source.convert(numChannels: 4);
    final sw = src.width;
    final sh = src.height;
    if (sw < 4 || sh < 4) return src;

    final samples = <List<int>>[];
    for (var y = 0; y < sh; y++) {
      for (var x = 0; x < sw; x++) {
        final p = src.getPixel(x, y);
        if (p.a.toInt() < 40) continue;
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        if (r + g + b >= 720 && (r - b).abs() < 36 && (r - g).abs() < 36) {
          continue;
        }
        samples.add([r, g, b, x, y]);
      }
    }
    if (samples.length < 40) return src;

    final k = math.min(4, math.max(2, samples.length ~/ 80));
    final centers = <List<int>>[];
    for (var i = 0; i < k; i++) {
      final s = samples[(i * samples.length) ~/ k];
      centers.add([s[0], s[1], s[2]]);
    }
    for (var iter = 0; iter < 8; iter++) {
      final sums = List.generate(k, (_) => [0, 0, 0, 0]);
      for (final s in samples) {
        var best = 0;
        var bestD = 1 << 30;
        for (var c = 0; c < k; c++) {
          final d = _colorDistance(s[0], s[1], s[2], centers[c][0], centers[c][1], centers[c][2]);
          if (d < bestD) {
            bestD = d;
            best = c;
          }
        }
        sums[best][0] += s[0];
        sums[best][1] += s[1];
        sums[best][2] += s[2];
        sums[best][3] += 1;
      }
      for (var c = 0; c < k; c++) {
        if (sums[c][3] == 0) continue;
        centers[c][0] = (sums[c][0] / sums[c][3]).round();
        centers[c][1] = (sums[c][1] / sums[c][3]).round();
        centers[c][2] = (sums[c][2] / sums[c][3]).round();
      }
    }

    final order = List<int>.generate(k, (i) => i)
      ..sort((a, b) =>
          (centers[a][0] + centers[a][1] + centers[a][2])
              .compareTo(centers[b][0] + centers[b][1] + centers[b][2]));

    final th = targetHeight ?? math.max(sh, 3000);
    final tw = math.max(1, (sw * th / sh).round());
    final out = img.Image(width: tw, height: th, numChannels: 4);
    img.fill(out, color: img.ColorRgba8(0, 0, 0, 0));

    for (final ci in order) {
      final mask = img.Image(width: sw, height: sh, numChannels: 4);
      img.fill(mask, color: img.ColorRgba8(0, 0, 0, 0));
      var count = 0;
      for (final s in samples) {
        var best = 0;
        var bestD = 1 << 30;
        for (var c = 0; c < k; c++) {
          final d = _colorDistance(s[0], s[1], s[2], centers[c][0], centers[c][1], centers[c][2]);
          if (d < bestD) {
            bestD = d;
            best = c;
          }
        }
        if (best != ci) continue;
        mask.setPixelRgba(s[3], s[4], 255, 255, 255, 255);
        count++;
      }
      if (count < 20) continue;
      var scaled = img.copyResize(
        mask,
        width: tw,
        height: th,
        interpolation: img.Interpolation.cubic,
      );
      scaled = img.gaussianBlur(scaled, radius: math.max(1, th ~/ 900));
      final cr = centers[ci][0];
      final cg = centers[ci][1];
      final cb = centers[ci][2];
      for (var y = 0; y < th; y++) {
        for (var x = 0; x < tw; x++) {
          if (scaled.getPixel(x, y).r.toInt() < 128) continue;
          out.setPixelRgba(x, y, cr, cg, cb, 255);
        }
      }
    }
    return out;
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
      return normalizeToVisibleContent(Uint8List.fromList(img.encodePng(image)));
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
          final p = image.getPixel(x, y);
          if (p.a.toInt() < alphaThreshold) continue;
          samples.add(p);
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

  /// Empty = transparent, matches known flat background, or near-white padding.
  static bool _isEmptyPixel(img.Pixel pixel, (int r, int g, int b)? bg) {
    if (pixel.a.toInt() < alphaThreshold) return true;
    final r = pixel.r.toInt();
    final g = pixel.g.toInt();
    final b = pixel.b.toInt();
    // Square web logos often sit on opaque white; treat that as margin.
    if (r >= 240 && g >= 240 && b >= 240) return true;
    if (bg == null) return false;
    if (_colorDistance(r, g, b, bg.$1, bg.$2, bg.$3) <= colorTolerance) {
      return true;
    }
    // Solid black (or near-black) canvas around a logo.
    if (bg.$1 <= 32 && bg.$2 <= 32 && bg.$3 <= 32 && r <= 32 && g <= 32 && b <= 32) {
      return true;
    }
    return false;
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
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        if (r >= 240 && g >= 240 && b >= 240) continue;
        if (bg != null &&
            _colorDistance(r, g, b, bg.$1, bg.$2, bg.$3) <= colorTolerance) {
          continue;
        }
        if (bg != null &&
            bg.$1 <= 32 &&
            bg.$2 <= 32 &&
            bg.$3 <= 32 &&
            r <= 32 &&
            g <= 32 &&
            b <= 32) {
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

  /// Drop outer rows/columns that are almost empty (anti-aliased halo) so a
  /// square mark is not sized by a 1-pixel fringe around a large canvas.
  static img.Image _trimLowCoverageMargins(img.Image image) {
    const minAlpha = 96;
    bool isInk(int x, int y) {
      final p = image.getPixel(x, y);
      if (p.a.toInt() < minAlpha) return false;
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      if (r >= 240 && g >= 240 && b >= 240) return false;
      return true;
    }

    var top = 0;
    var left = 0;
    var bottom = image.height - 1;
    var right = image.width - 1;

    bool rowWeak(int y) {
      var n = 0;
      final span = right - left + 1;
      if (span <= 0) return true;
      for (var x = left; x <= right; x++) {
        if (isInk(x, y)) n++;
      }
      return n / span < 0.02;
    }

    bool colWeak(int x) {
      var n = 0;
      final span = bottom - top + 1;
      if (span <= 0) return true;
      for (var y = top; y <= bottom; y++) {
        if (isInk(x, y)) n++;
      }
      return n / span < 0.02;
    }

    while (top < bottom && rowWeak(top)) {
      top++;
    }
    while (bottom > top && rowWeak(bottom)) {
      bottom--;
    }
    while (left < right && colWeak(left)) {
      left++;
    }
    while (right > left && colWeak(right)) {
      right--;
    }

    if (top == 0 &&
        left == 0 &&
        bottom == image.height - 1 &&
        right == image.width - 1) {
      return image;
    }

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
