import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'gemini_client.dart';
import 'logo_image_process.dart';

/// Print-ready customer logo restore.
///
/// Order (critical for color fidelity):
/// 1. Strip solid / checkerboard plate from the **raw** raster.
/// 2. Gemini redraws edges on that cleaned transparent PNG (exact brand hexes).
/// 3. Snap fills back to source brand colors, crop, optional outline, scale.
///
/// Never send a raw plate/checkerboard to Gemini and flatten afterward — that
/// blends and invents hues. Offline: local predictive rebuild, then same finish.
class LogoRestorer {
  LogoRestorer._();

  static const minDimension = 3000;
  static const pipelineVersion = 'print-ready-v5-plate-counters';
  static const cacheFileName = 'logo_restore_cache.json';
  static final Map<String, Future<File>> _inFlight = {};

  static Future<File> ensureHighRes(
    File source, {
    required Directory logosDir,
    void Function(String)? onLog,
  }) async {
    if (!await source.exists()) return source;

    final identity = await _sourceIdentity(source);
    final existing = _inFlight[identity];
    if (existing != null) return existing;

    final future = _ensureHighResUncapped(
      source,
      logosDir: logosDir,
      identity: identity,
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
    void Function(String)? onLog,
  }) async {
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
    if (_isPrintReadyRestored(source, sourceBytes)) {
      onLog?.call('logo_restorer: already print-ready ${source.path}');
      cache[identity] = source.absolute.path;
      await _saveCache(logosDir, cache);
      return source;
    }

    // 1) Background off the raw raster BEFORE any recreate.
    final prepared = LogoImageProcessor.prepareRasterForRestore(sourceBytes);
    onLog?.call('logo_restorer: prepared transparent raster for restore');

    Uint8List? png;
    Object? lastError;
    if (GeminiClient.isConfigured) {
      try {
        onLog?.call('logo_restorer: Gemini restore ${source.path}');
        png = await GeminiClient().restoreLogoPng(prepared);
      } catch (e) {
        lastError = e;
        onLog?.call('logo_restorer: Gemini failed ($e); local rebuild');
      }
    }
    if (png == null || png.isEmpty) {
      try {
        onLog?.call('logo_restorer: local predictive rebuild');
        final decoded = img.decodeImage(prepared);
        if (decoded != null) {
          final rebuilt = LogoImageProcessor.rebuildPredictedEdges(
            decoded,
            targetHeight: minDimension,
          );
          png = Uint8List.fromList(img.encodePng(rebuilt));
        }
      } catch (e) {
        lastError = e;
      }
    }
    if (png != null &&
        png.isNotEmpty &&
        LogoImageProcessor.looksLikeCheckerboardMatte(png)) {
      onLog?.call(
        'logo_restorer: restore looks like checkerboard matte; rejecting',
      );
      png = null;
    }
    if (png != null &&
        png.isNotEmpty &&
        !LogoImageProcessor.retainsBrandColors(prepared, png) &&
        !LogoImageProcessor.retainsBrandColors(sourceBytes, png)) {
      onLog?.call(
        'logo_restorer: restore lost brand colors; using cleaned source',
      );
      png = null;
    }
    if (png == null || png.isEmpty) {
      // Clean source fallback (still print-ready height via finalize).
      png = prepared.isNotEmpty ? prepared : sourceBytes;
      if (lastError != null) {
        onLog?.call('logo_restorer: fallback after errors ($lastError)');
      }
    }
    final finalized = finalizeRestoredPng(
      png,
      sourceBytes: prepared.isNotEmpty ? prepared : sourceBytes,
    );
    final dest = await _restoredDestFile(source, logosDir);
    await dest.writeAsBytes(finalized, flush: true);
    cache[identity] = dest.absolute.path;
    await _saveCache(logosDir, cache);
    onLog?.call('logo_restorer: wrote ${dest.path}');
    return dest;
  }

  /// Skip a second Gemini pass on a file this pipeline already finished.
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

  /// Crop empty plate, snap fills to source brand colors, restore outline,
  /// then scale to [minDimension] px tall.
  ///
  /// If the restore dropped a major brand fill (e.g. green wordmark kept only
  /// the orange accent), fall back to a normalized source so PDFs do not show
  /// a huge cut-off fragment scaled to Swift height.
  static Uint8List finalizeRestoredPng(
    Uint8List bytes, {
    Uint8List? sourceBytes,
  }) {
    if (bytes.isEmpty) return bytes;
    final cropped = LogoImageProcessor.normalizeToVisibleContent(bytes);
    var image = img.decodeImage(cropped.isNotEmpty ? cropped : bytes);
    if (image == null || image.height <= 0) return bytes;

    if (sourceBytes != null && sourceBytes.isNotEmpty) {
      // Color lock first — do not flatten before snap (that blends hues).
      image = LogoImageProcessor.snapToSourceBrandColors(image, sourceBytes);
      final srcImg = img.decodeImage(sourceBytes);
      if (srcImg != null) {
        image = LogoImageProcessor.ensureLetterOutline(srcImg, image);
      }
      final locked = Uint8List.fromList(img.encodePng(image));
      if (!LogoImageProcessor.retainsBrandColors(sourceBytes, locked)) {
        return _finalizeFromSourceFallback(sourceBytes);
      }
    } else {
      image = LogoImageProcessor.flattenSolidBrandFills(image);
    }

    if (image.height < minDimension) {
      final scale = minDimension / image.height;
      final w = math.max(1, (image.width * scale).round());
      // Nearest after color-lock keeps exact brand hexes (no cubic bleed).
      image = img.copyResize(
        image,
        width: w,
        height: minDimension,
        interpolation: sourceBytes != null && sourceBytes.isNotEmpty
            ? img.Interpolation.nearest
            : img.Interpolation.cubic,
      );
    }
    return Uint8List.fromList(img.encodePng(image));
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
}
