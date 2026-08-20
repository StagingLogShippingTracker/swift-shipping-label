import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Catalog of restore techniques that worked — refined after every Gemini pass.
///
/// Stored as `logo_restore_lessons.json` next to customer logos. Winning
/// prompt addenda and post-process steps are replayed on later restores.
class RestoreCatalog {
  RestoreCatalog({
    Map<String, RestoreTechnique>? techniques,
    List<String>? promptAddenda,
    List<RestoreHistoryEntry>? history,
    Map<String, int>? successCount,
    Map<String, int>? warpCount,
  })  : techniques = techniques ?? Map.of(_seedTechniques),
        promptAddenda = promptAddenda ?? List.of(_seedAddenda),
        history = history ?? [],
        successCount = successCount ?? {},
        warpCount = warpCount ?? {};

  final Map<String, RestoreTechnique> techniques;
  final List<String> promptAddenda;
  final List<RestoreHistoryEntry> history;
  final Map<String, int> successCount;
  final Map<String, int> warpCount;

  static const version = 3;
  static const maxHistory = 80;

  static const _seedAddenda = [
    'Never draw Gemini, Google, Spark, Imagen, or any AI watermark, badge, or wordmark.',
    'Do not add extra company names, taglines, or lockups that are not in the source.',
    'Keep true alpha — never bake a black, white, gray, or checkerboard plate.',
    'Enhance existing pixels; repair frayed edges and blotchy solids without redrawing or over-sharpening.',
    'Leave real gradients and texture; only even regions that should be one brand fill.',
    'Keep grey, silver, black, and white letter fills — never recolor them to a brighter accent.',
    'Outer plate only: dark letters on a dark plate are ink, not background.',
  ];

  static final Map<String, RestoreTechnique> _seedTechniques = {
    'gemini_primary': RestoreTechnique(
      id: 'gemini_primary',
      notes:
          'Legacy id — Gemini is secondary after Real-ESRGAN. Redraws are discarded by the fidelity gate.',
      uses: 24,
      wins: 21,
    ),
    'gemini_secondary': RestoreTechnique(
      id: 'gemini_secondary',
      notes:
          'Optional Gemini after Real-ESRGAN miss. Accept only when geometry and brand fills match.',
      uses: 0,
      wins: 0,
    ),
    'realesrgan_primary': RestoreTechnique(
      id: 'realesrgan_primary',
      notes:
          'Windows Real-ESRGAN via logo_restorer.py — invents edge/fill detail from degradation.',
      uses: 0,
      wins: 0,
    ),
    'plate_knockout': RestoreTechnique(
      id: 'plate_knockout',
      notes: 'Punch opaque white/checkerboard canvas to true alpha after Gemini.',
      uses: 24,
      wins: 21,
    ),
    'flatten_native_then_upscale': RestoreTechnique(
      id: 'flatten_native_then_upscale',
      notes: 'Flatten fills at <=1600px, then Lanczos to 3000px — k-means at full print size hangs.',
      uses: 21,
      wins: 21,
    ),
    'outline_preserve': RestoreTechnique(
      id: 'outline_preserve',
      notes: 'Detect source letter outlines and reapply if Gemini dropped the stroke.',
      uses: 8,
      wins: 8,
    ),
    'color_lock': RestoreTechnique(
      id: 'color_lock',
      notes: 'snapToSourceBrandColors after Gemini so hues cannot drift.',
      uses: 17,
      wins: 17,
    ),
    'aspect_match': RestoreTechnique(
      id: 'aspect_match',
      notes: 'Pass imageConfig.aspectRatio from the source lockup.',
      uses: 21,
      wins: 17,
      fails: 4,
    ),
    'no_watermark': RestoreTechnique(
      id: 'no_watermark',
      notes: 'Prompt ban + strip disconnected corner/bottom Gemini marks.',
      uses: 24,
      wins: 21,
    ),
    'halo_strip': RestoreTechnique(
      id: 'halo_strip',
      notes: 'Punch JPEG/Gemini white-gray fringe between ink and empty canvas.',
      uses: 0,
      wins: 0,
    ),
    'solid_fills': RestoreTechnique(
      id: 'solid_fills',
      notes: 'Flatten blotchy interiors that should be one brand fill; keep real edges.',
      uses: 0,
      wins: 0,
    ),
    'studio_finish': RestoreTechnique(
      id: 'studio_finish',
      notes:
          'Every restore: plate/halo knockout, color lock, interior flatten, 3000px PNG. Do not re-trace over Gemini.',
      uses: 0,
      wins: 0,
    ),
    'raster_conservator': RestoreTechnique(
      id: 'raster_conservator',
      notes:
          'Cubic enhance when Real-ESRGAN/Gemini are skipped, rejected, unavailable, or the source is already high-res.',
      uses: 0,
      wins: 0,
    ),
  };

  factory RestoreCatalog.fromJson(Map<String, dynamic> json) {
    final techniques = Map<String, RestoreTechnique>.of(_seedTechniques);
    final rawTech = json['techniques'];
    if (rawTech is Map) {
      for (final e in rawTech.entries) {
        if (e.value is Map) {
          techniques['${e.key}'] = RestoreTechnique.fromJson(
            '${e.key}',
            Map<String, dynamic>.from(e.value as Map),
          );
        }
      }
    }
    final addenda = <String>[..._seedAddenda];
    final rawAdd = json['promptAddenda'];
    if (rawAdd is List) {
      for (final e in rawAdd) {
        if (e is String && e.trim().isNotEmpty && !addenda.contains(e)) {
          addenda.add(e.trim());
        }
      }
    }
    final history = <RestoreHistoryEntry>[];
    final rawHist = json['history'];
    if (rawHist is List) {
      for (final e in rawHist) {
        if (e is Map) {
          history.add(
            RestoreHistoryEntry.fromJson(Map<String, dynamic>.from(e)),
          );
        }
      }
    }
    return RestoreCatalog(
      techniques: techniques,
      promptAddenda: addenda,
      history: history,
      successCount: _ints(json['successCount']),
      warpCount: _ints(json['warpCount']),
    );
  }

  static Map<String, int> _ints(dynamic raw) {
    final out = <String, int>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        final n = e.value;
        if (n is int) out['${e.key}'] = n;
        if (n is num) out['${e.key}'] = n.round();
      }
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'techniques': {
          for (final e in techniques.entries) e.key: e.value.toJson(),
        },
        'promptAddenda': promptAddenda,
        'history': [
          for (final e in history.skip(math.max(0, history.length - maxHistory)))
            e.toJson(),
        ],
        'successCount': successCount,
        'warpCount': warpCount,
      };

  /// Winning prompt lines to append on the next Gemini call.
  List<String> winningAddenda() {
    final learned = <String>[];
    for (final line in promptAddenda) {
      if (_seedAddenda.contains(line)) continue;
      if (learned.contains(line)) continue;
      learned.add(line);
    }
    return [
      ..._seedAddenda,
      ...learned.take(6),
    ];
  }

  /// Auto-lessons from a scored pass — replayed on later Gemini calls.
  static List<String> lessonsFrom(RestoreQuality q) {
    final notes = <String>[];
    if (q.whitePlateFrac >= 0.02) {
      notes.add('Knock out any remaining white or black plate to true alpha.');
    }
    if (q.aspectDrift >= 0.20) {
      notes.add('Keep the source lockup aspect ratio; do not stretch.');
    }
    if (q.hadCornerMark) {
      notes.add('Do not draw a generator watermark or extra lockup.');
    }
    if (q.grade == RestoreGrade.pristine || q.grade == RestoreGrade.favourable) {
      notes.add(
        'Enhance pixels and repair edges/fills only — do not restyle or over-sharpen.',
      );
    }
    return notes;
  }

  void record({
    required String sourceName,
    required RestoreGrade grade,
    required List<String> used,
    String? note,
    List<String> notes = const [],
  }) {
    for (final id in used) {
      final t = techniques[id] ??
          RestoreTechnique(id: id, notes: note ?? id);
      t.uses++;
      if (grade == RestoreGrade.pristine || grade == RestoreGrade.favourable) {
        t.wins++;
      } else if (grade == RestoreGrade.fail) {
        t.fails++;
      }
      techniques[id] = t;
    }
    final mergedNotes = [
      if (note != null && note.trim().isNotEmpty) note.trim(),
      ...notes.map((e) => e.trim()).where((e) => e.isNotEmpty),
    ];
    history.add(
      RestoreHistoryEntry(
        at: DateTime.now().toUtc(),
        source: sourceName,
        grade: grade,
        techniques: used,
        note: mergedNotes.isEmpty ? null : mergedNotes.join(' '),
      ),
    );
    if (history.length > maxHistory) {
      history.removeRange(0, history.length - maxHistory);
    }
    if (grade == RestoreGrade.pristine || grade == RestoreGrade.favourable) {
      for (final n in mergedNotes) {
        if (!promptAddenda.contains(n)) promptAddenda.add(n);
      }
    }
  }
}

class RestoreTechnique {
  RestoreTechnique({
    required this.id,
    required this.notes,
    this.uses = 0,
    this.wins = 0,
    this.fails = 0,
  });

  final String id;
  final String notes;
  int uses;
  int wins;
  int fails;

  double get winRate => uses <= 0 ? 0 : wins / uses;

  factory RestoreTechnique.fromJson(String id, Map<String, dynamic> json) {
    return RestoreTechnique(
      id: id,
      notes: '${json['notes'] ?? ''}',
      uses: (json['uses'] as num?)?.round() ?? 0,
      wins: (json['wins'] as num?)?.round() ?? 0,
      fails: (json['fails'] as num?)?.round() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'notes': notes,
        'uses': uses,
        'wins': wins,
        'fails': fails,
      };
}

class RestoreHistoryEntry {
  RestoreHistoryEntry({
    required this.at,
    required this.source,
    required this.grade,
    required this.techniques,
    this.note,
  });

  final DateTime at;
  final String source;
  final RestoreGrade grade;
  final List<String> techniques;
  final String? note;

  factory RestoreHistoryEntry.fromJson(Map<String, dynamic> json) {
    return RestoreHistoryEntry(
      at: DateTime.tryParse('${json['at']}') ?? DateTime.now().toUtc(),
      source: '${json['source'] ?? ''}',
      grade: RestoreGrade.tryParse('${json['grade']}') ?? RestoreGrade.fail,
      techniques: [
        for (final e in (json['techniques'] as List? ?? const []))
          if (e is String) e,
      ],
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'source': source,
        'grade': grade.name,
        'techniques': techniques,
        if (note != null) 'note': note,
      };
}

enum RestoreGrade {
  pristine,
  favourable,
  fail;

  static RestoreGrade? tryParse(String raw) {
    for (final g in RestoreGrade.values) {
      if (g.name == raw) return g;
    }
    return null;
  }
}

/// Score a Gemini restore against the source lockup.
class RestoreQuality {
  RestoreQuality({
    required this.geminiOk,
    required this.height,
    required this.opaqueFrac,
    required this.whitePlateFrac,
    required this.aspectDrift,
    required this.hadCornerMark,
  });

  final bool geminiOk;
  final int height;
  final double opaqueFrac;
  final double whitePlateFrac;
  final double aspectDrift;
  final bool hadCornerMark;

  RestoreGrade get grade {
    if (!geminiOk || height < 2000) return RestoreGrade.fail;
    if (whitePlateFrac > 0.18) return RestoreGrade.fail;
    if (height >= 3000 &&
        whitePlateFrac < 0.02 &&
        aspectDrift < 0.28 &&
        !hadCornerMark &&
        opaqueFrac < 0.88) {
      return RestoreGrade.pristine;
    }
    if (whitePlateFrac < 0.12 && aspectDrift < 0.40) {
      return RestoreGrade.favourable;
    }
    return RestoreGrade.fail;
  }

  static RestoreQuality measure({
    required bool geminiOk,
    required Uint8List source,
    required Uint8List restored,
    required bool hadCornerMark,
  }) {
    final src = img.decodeImage(source);
    final dst = img.decodeImage(restored);
    if (dst == null) {
      return RestoreQuality(
        geminiOk: geminiOk,
        height: 0,
        opaqueFrac: 1,
        whitePlateFrac: 1,
        aspectDrift: 1,
        hadCornerMark: hadCornerMark,
      );
    }
    var opaque = 0, white = 0, n = 0;
    for (var y = 0; y < dst.height; y += math.max(1, dst.height ~/ 180)) {
      for (var x = 0; x < dst.width; x += math.max(1, dst.width ~/ 180)) {
        final p = dst.getPixel(x, y);
        n++;
        if (p.a.toInt() > 32) opaque++;
        if (p.a.toInt() > 80 &&
            p.r.toInt() > 235 &&
            p.g.toInt() > 235 &&
            p.b.toInt() > 235) {
          white++;
        }
      }
    }
    final srcAspect = (src != null && src.height > 0)
        ? src.width / src.height
        : 1.0;
    final dstAspect = dst.height > 0 ? dst.width / dst.height : 1.0;
    final drift = (srcAspect - dstAspect).abs() / math.max(srcAspect, 0.01);
    return RestoreQuality(
      geminiOk: geminiOk,
      height: dst.height,
      opaqueFrac: n == 0 ? 1 : opaque / n,
      whitePlateFrac: n == 0 ? 1 : white / n,
      aspectDrift: drift,
      hadCornerMark: hadCornerMark,
    );
  }
}

String prettyJson(Object value) =>
    const JsonEncoder.withIndent('  ').convert(value);
