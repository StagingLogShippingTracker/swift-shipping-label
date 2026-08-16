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
/// Proven path (BFL + Murray's Trucking):
/// 1. Gemini redraws the mark (vector-like edges, solid fills, keep letter
///    strokes). Do not upscale JPEG pixels.
/// 2. Crop empty plate, flatten every fill (any hue), restore a dropped
///    dark outline from the source, scale to [minDimension] px tall.
/// 3. If Gemini is down: local predictive mask rebuild, then the same
///    finish. Offline Windows can still run `logo_restorer.py` (RealESRGAN).
class LogoRestorer {
  LogoRestorer._();

  static const minDimension = 3000;
  static const pipelineVersion = 'print-ready-v1';
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

    Uint8List? png;
    Object? lastError;
    if (GeminiClient.isConfigured) {
      try {
        onLog?.call('logo_restorer: Gemini restore ${source.path}');
        png = await GeminiClient().restoreLogoPng(sourceBytes);
      } catch (e) {
        lastError = e;
        onLog?.call('logo_restorer: Gemini failed ($e); local rebuild');
      }
    }
    if (png == null || png.isEmpty) {
      try {
        onLog?.call('logo_restorer: local predictive rebuild');
        final decoded = img.decodeImage(sourceBytes);
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
    if (png == null || png.isEmpty) {
      throw StateError(
        'Logo restore needs Gemini (internet) or a local rebuild.'
        '${lastError == null ? '' : ' ($lastError)'}',
      );
    }
    final finalized = finalizeRestoredPng(png, sourceBytes: sourceBytes);
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

  /// Crop empty plate, flatten every fill (any hue), restore a dropped
  /// dark outline from the source, then scale to [minDimension] px tall.
  static Uint8List finalizeRestoredPng(
    Uint8List bytes, {
    Uint8List? sourceBytes,
  }) {
    if (bytes.isEmpty) return bytes;
    final cropped = LogoImageProcessor.normalizeToVisibleContent(bytes);
    var image = img.decodeImage(cropped.isNotEmpty ? cropped : bytes);
    if (image == null || image.height <= 0) return bytes;
    image = LogoImageProcessor.flattenSolidBrandFills(image);
    if (sourceBytes != null && sourceBytes.isNotEmpty) {
      final srcImg = img.decodeImage(sourceBytes);
      if (srcImg != null) {
        image = LogoImageProcessor.ensureLetterOutline(srcImg, image);
      }
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
