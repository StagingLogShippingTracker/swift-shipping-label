import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'gemini_client.dart';
import 'logo_image_process.dart';
import 'restore_catalog.dart';

/// Print-ready customer logo restore.
///
/// Gemini (`restoreLogoPng`) may super-resolve low-res rasters when a key is
/// configured. Output that changes geometry or brand fills is discarded and
/// the source raster is cubic-enhanced instead. Sources already at/above
/// [generativeMaxHeight] skip Gemini (knockout + cubic scale only).
/// Do not unwire Gemini. Every pass is scored into [lessonsFileName].
class LogoRestorer {
  LogoRestorer._();

  static const minDimension = 3000;
  static const pipelineVersion = 'print-ready-v11-ink-crop';
  /// Below this source height, Gemini may super-resolve. At or above it, only
  /// a gentle raster conservator (knockout + cubic scale) runs.
  static const generativeMaxHeight = 1600;
  static const cacheFileName = 'logo_restore_cache.json';
  static const lessonsFileName = 'logo_restore_lessons.json';
  static final Map<String, Future<File>> _inFlight = {};
  static int _epoch = 0;

  static int get epoch => _epoch;

  /// Abort in-flight restores. Completions after this are discarded.
  static void cancelAll() {
    _epoch++;
    _inFlight.clear();
  }

  static Future<File> ensureHighRes(
    File source, {
    required Directory logosDir,
    void Function(String)? onLog,
  }) async {
    if (!await source.exists()) return source;

    final identity = await _sourceIdentity(source);
    final existing = _inFlight[identity];
    if (existing != null) return existing;

    final started = _epoch;
    final future = _ensureHighResUncapped(
      source,
      logosDir: logosDir,
      identity: identity,
      startedEpoch: started,
      onLog: onLog,
    );
    _inFlight[identity] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(identity);
    }
  }

  static Future<File> _ensureHighResUncapped(
    File source, {
    required Directory logosDir,
    required String identity,
    required int startedEpoch,
    void Function(String)? onLog,
  }) async {
    bool cancelled() => startedEpoch != _epoch;

    await logosDir.create(recursive: true);
    final cache = await _loadCache(logosDir);
    final cachedPath = cache[identity];
    if (cachedPath != null) {
      final cached = File(cachedPath);
      if (await cached.exists() && await cached.length() > 0) {
        onLog?.call('logo_restorer: cache hit ${cached.path}');
        return cached;
      }
    }

    final sourceBytes = await source.readAsBytes();
    if (cancelled()) return source;
    if (_isPrintReadyRestored(source, sourceBytes)) {
      onLog?.call('logo_restorer: already print-ready ${source.path}');
      cache[identity] = source.absolute.path;
      await _saveCache(logosDir, cache);
      return source;
    }

    final sourceHeight = heightOfBytes(sourceBytes);
    final catalog = await _loadCatalog(logosDir);
    final addenda = catalog.winningAddenda();

    var usedGemini = false;
    late Uint8List png;
    final referenceBytes = sourceBytes;
    late Uint8List workBytes;

    if (!usesGenerativeRestore(sourceHeight)) {
      onLog?.call(
        'logo_restorer: high-res conservator (${sourceHeight}px, no generative redraw)',
      );
      png = _conservatorRaster(sourceBytes);
      workBytes = LogoImageProcessor.prepareRasterForRestore(sourceBytes);
      if (workBytes.isEmpty) workBytes = sourceBytes;
    } else {
      final prepared = LogoImageProcessor.prepareRasterForRestore(sourceBytes);
      onLog?.call('logo_restorer: prepared transparent raster for enhance');
      workBytes = prepared.isNotEmpty ? prepared : sourceBytes;

      if (GeminiClient.isConfigured) {
        try {
          onLog?.call('logo_restorer: Gemini restoreLogoPng');
          png = await GeminiClient().restoreLogoPng(
            workBytes,
            addenda: addenda,
          );
          usedGemini = png.isNotEmpty;
          if (!usedGemini) {
            throw StateError('Gemini returned empty image');
          }
          if (!LogoImageProcessor.isFaithfulRestore(workBytes, png) ||
              !LogoImageProcessor.isFaithfulRestore(sourceBytes, png) ||
              LogoImageProcessor.aspectDrift(sourceBytes, png) > 0.32) {
            onLog?.call(
              'logo_restorer: Gemini changed the artwork; cubic enhance',
            );
            usedGemini = false;
            // Source-anchored conservator fallback avoids geometry/color drift
            // introduced by aggressive prep rasters.
            png = _conservatorRaster(sourceBytes);
          }
        } catch (e) {
          onLog?.call('logo_restorer: Gemini failed ($e); cubic fallback');
          usedGemini = false;
          png = _conservatorRaster(sourceBytes);
        }
      } else {
        onLog?.call('logo_restorer: Gemini unconfigured; cubic raster enhance');
        png = _conservatorRaster(sourceBytes);
      }
    }

    final fingerprint = _cheapFingerprint(workBytes);
    catalog.successCount[fingerprint] =
        (catalog.successCount[fingerprint] ?? 0) + 1;

    if (cancelled()) return source;

    final decoded = img.decodeImage(png);
    if (decoded != null) {
      LogoImageProcessor.stripForeignMarks(decoded);
      png = Uint8List.fromList(img.encodePng(decoded));
    }

    final finalized = finalizeRestoredPng(
      png,
      sourceBytes: referenceBytes,
      enhanceOnly: !usedGemini,
    );
    // Keep the ink-cropped canvas. Letterboxing back to the source plate
    // made contact sheets shrink the mark and failed knockout-relative IoU.

    final quality = RestoreQuality.measure(
      geminiOk: usedGemini,
      source: referenceBytes,
      restored: finalized,
      hadCornerMark: false,
    );
    catalog.record(
      sourceName: p.basename(source.path),
      grade: quality.grade,
      used: [
        if (usedGemini) 'gemini_primary',
        if (!usedGemini) 'raster_conservator',
        'plate_knockout',
        'no_watermark',
        'halo_strip',
        'solid_fills',
        'color_lock',
        'ink_crop',
        'studio_finish',
      ],
      notes: RestoreCatalog.lessonsFrom(quality),
    );
    await _saveCatalog(logosDir, catalog);
    if (cancelled()) return source;

    final dest = await _restoredDestFile(source, logosDir);
    await dest.writeAsBytes(finalized, flush: true);
    cache[identity] = dest.absolute.path;
    await _saveCache(logosDir, cache);
    onLog?.call('logo_restorer: wrote ${dest.path}');
    return dest;
  }

  static bool usesGenerativeRestore(int sourceHeight) =>
      sourceHeight > 0 && sourceHeight < generativeMaxHeight;

  static Uint8List _conservatorRaster(Uint8List sourceBytes) {
    final prepared = LogoImageProcessor.prepareRasterForRestore(sourceBytes);
    final bytes = prepared.isNotEmpty ? prepared : sourceBytes;
    final decoded = LogoImageProcessor.decodeToRgba(bytes);
    if (decoded == null || decoded.height <= 0) return bytes;
    // Punch milky cubic/JPEG rim before upscale so it does not become a
    // white outline at 3000px. Grey/silver letter bodies stay protected.
    LogoImageProcessor.stripHaloFringe(decoded);
    if (decoded.height == minDimension) {
      return Uint8List.fromList(img.encodePng(decoded));
    }
    final scale = minDimension / decoded.height;
    final w = math.max(1, (decoded.width * scale).round());
    final out = img.copyResize(
      decoded,
      width: w,
      height: minDimension,
      interpolation: img.Interpolation.cubic,
    );
    return Uint8List.fromList(img.encodePng(out));
  }

  static bool _isPrintReadyRestored(File source, Uint8List bytes) {
    final name = p.basename(source.path).toLowerCase();
    if (!name.contains('restored')) return false;
    return heightOfBytes(bytes) >= 2000;
  }

  static int heightOfBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return 0;
    return decoded.height;
  }

  static String _cheapFingerprint(Uint8List bytes) {
    var h = bytes.length;
    final step = math.max(1, bytes.length ~/ 512);
    for (var i = 0; i < bytes.length; i += step) {
      h = 0x1fffffff & (h * 31 + bytes[i]);
    }
    return '$h:${bytes.length}:$pipelineVersion';
  }

  /// Studio finish after Gemini (or cubic fallback): plate/halo out, lock
  /// brand colors, even blotchy interiors, PNG at [minDimension] px tall.
  ///
  /// Does not re-trace or cartoon edges — Gemini already repaired them.
  static Uint8List finalizeRestoredPng(
    Uint8List bytes, {
    Uint8List? sourceBytes,
    bool enhanceOnly = false,
  }) {
    if (bytes.isEmpty) return bytes;

    if (enhanceOnly) {
      return _finalizeConservatorOnly(bytes);
    }

    final cropped = LogoImageProcessor.normalizeToVisibleContent(bytes);
    var image = img.decodeImage(cropped.isNotEmpty ? cropped : bytes);
    if (image == null || image.height <= 0) {
      return LogoImageProcessor.upscaleForPrint(
        bytes,
        minHeight: minDimension,
      );
    }
    LogoImageProcessor.stripHaloFringe(image);

    if (!enhanceOnly && sourceBytes != null && sourceBytes.isNotEmpty) {
      image = LogoImageProcessor.snapToSourceBrandColors(image, sourceBytes);
      final srcImg = img.decodeImage(sourceBytes);
      if (srcImg != null) {
        image = LogoImageProcessor.ensureLetterOutline(srcImg, image);
      }
      final locked = Uint8List.fromList(img.encodePng(image));
      if (!LogoImageProcessor.retainsBrandColors(sourceBytes, locked)) {
        return _finalizeFromSourceFallback(sourceBytes);
      }
    }

    if (!enhanceOnly) {
      // Flatten at working size — k-means/flood at 3000px hangs and over-edges.
      if (image.height > 1600) {
        final s = 1600 / image.height;
        image = img.copyResize(
          image,
          width: math.max(1, (image.width * s).round()),
          height: 1600,
          interpolation: img.Interpolation.cubic,
        );
      }
      image = LogoImageProcessor.flattenSolidBrandFills(image);
    }

    if (image.height < minDimension) {
      final scale = minDimension / image.height;
      final w = math.max(1, (image.width * scale).round());
      image = img.copyResize(
        image,
        width: w,
        height: minDimension,
        interpolation: img.Interpolation.cubic,
      );
    }
    return Uint8List.fromList(img.encodePng(image));
  }

  /// Cubic conservator: strip milky fringe, then scale. Grey/silver fills stay.
  static Uint8List _finalizeConservatorOnly(Uint8List bytes) {
    final image = LogoImageProcessor.decodeToRgba(bytes);
    if (image == null || image.height <= 0) return bytes;
    LogoImageProcessor.stripHaloFringe(image);
    if (image.height >= minDimension) {
      return Uint8List.fromList(img.encodePng(image));
    }
    final scale = minDimension / image.height;
    final w = math.max(1, (image.width * scale).round());
    final out = img.copyResize(
      image,
      width: w,
      height: minDimension,
      interpolation: img.Interpolation.cubic,
    );
    return Uint8List.fromList(img.encodePng(out));
  }

  static Uint8List _finalizeFromSourceFallback(Uint8List sourceBytes) {
    final cropped = LogoImageProcessor.normalizeToVisibleContent(sourceBytes);
    var image = img.decodeImage(cropped.isNotEmpty ? cropped : sourceBytes);
    if (image == null || image.height <= 0) return sourceBytes;
    if (image.height < minDimension) {
      final scale = minDimension / image.height;
      final w = math.max(1, (image.width * scale).round());
      image = img.copyResize(
        image,
        width: w,
        height: minDimension,
        interpolation: img.Interpolation.cubic,
      );
    }
    return Uint8List.fromList(img.encodePng(image));
  }

  static Future<String> _sourceIdentity(File source) async {
    final stat = await source.stat();
    return '${p.normalize(source.absolute.path)}|'
        '${stat.size}|${stat.modified.millisecondsSinceEpoch}|'
        '$pipelineVersion';
  }

  static Future<File> _restoredDestFile(File source, Directory logosDir) async {
    var stem = p.basenameWithoutExtension(source.path);
    if (stem.toLowerCase().endsWith('_restored')) {
      stem = stem.substring(0, stem.length - '_restored'.length);
    }
    stem = stem.replaceAll(RegExp(r'[^\w\- .]+'), '_');
    if (stem.isEmpty) stem = 'logo';
    var dest = File(p.join(logosDir.path, '${stem}_restored.png'));
    if (p.equals(dest.path, source.absolute.path)) {
      dest = File(p.join(logosDir.path, '${stem}_restored_hr.png'));
    }
    return dest;
  }

  static File _cacheFile(Directory logosDir) =>
      File(p.join(logosDir.path, cacheFileName));

  static File _lessonsFile(Directory logosDir) =>
      File(p.join(logosDir.path, lessonsFileName));

  static Future<Map<String, String>> _loadCache(Directory logosDir) async {
    final file = _cacheFile(logosDir);
    if (!await file.exists()) return {};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveCache(
    Directory logosDir,
    Map<String, String> cache,
  ) async {
    final file = _cacheFile(logosDir);
    await file.writeAsBytes(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(cache)),
    );
  }

  static Future<RestoreCatalog> _loadCatalog(Directory logosDir) async {
    final file = _lessonsFile(logosDir);
    if (!await file.exists()) return RestoreCatalog();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return RestoreCatalog();
      return RestoreCatalog.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return RestoreCatalog();
    }
  }

  static Future<void> _saveCatalog(
    Directory logosDir,
    RestoreCatalog catalog,
  ) async {
    final file = _lessonsFile(logosDir);
    await file.writeAsBytes(
      utf8.encode(prettyJson(catalog.toJson())),
    );
  }
}
