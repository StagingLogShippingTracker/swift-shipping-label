import 'bulk_label_models.dart';

/// Parses Swift Order Acknowledgement text (from pdfrx / pypdf) into bulk lines.
///
/// Identity field comes from OA line notes:
/// - `Order Line Notes: TAG# …` → valve sticker prints **TAG#**
/// - `Order Line Notes: PART# …` → non-valve sticker prints **PART#**
/// - Loose `part # 050211` / `TAG# …` on the line after CPO (common Propak layout)
/// - If still missing: use the first non-empty line under the CPO note as PART#
///
/// CPO detection accepts both legacy `CPO #4` and current `CPO LINE 1` /
/// `CPO LINE 8, 9` forms.
///
/// Lines with CPO but no usable identity are collected in
/// [OrderAckParseResult.incompleteLines] so the UI can prompt
/// Proceed / Skip / Cancel.
class OrderAckParser {
  const OrderAckParser();

  OrderAckParseResult parseText(
    String raw, {
    String sourceFileName = '',
  }) {
    final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final warnings = <String>[];

    final poNumber = _extractPo(text);
    if (poNumber == null || poNumber.isEmpty) {
      warnings.add('Could not find PO Number on the Order Acknowledgement.');
    }

    final orderNumber = _extractOrderNumber(text) ?? '';

    final lines = <BulkLabelLine>[];
    final incomplete = <BulkIncompleteLine>[];

    // Legacy: "Order Line Notes: CPO #4"
    // Current: "Order Line Notes: CPO LINE 1" / "CPO LINE 8, 9"
    final cpoRe = RegExp(
      r'Order\s+Line\s+Notes:\s*CPO\s*(?:LINE\s*)?#?\s*'
      r'([0-9]+(?:\s*,\s*[0-9]+)*)',
      caseSensitive: false,
    );
    // Classic identity note on its own Order Line Notes row.
    final idNoteRe = RegExp(
      r'Order\s+Line\s+Notes:\s*(TAG|PART)\s*#\s*(.+)$',
      caseSensitive: false,
      multiLine: true,
    );
    // Loose "part # 050211" / "TAG# abc" (often directly under CPO LINE).
    final idLooseRe = RegExp(
      r'^\s*(TAG|PART)\s*#\s*(.+?)\s*$',
      caseSensitive: false,
      multiLine: true,
    );
    // pypdf often mashes "…EA2.00…" (qty after EA, always with decimals).
    final qtyAfterEaRe = RegExp(
      r'EA\s*(\d+\.\d+)',
      caseSensitive: false,
    );
    // pdfrx layout often has "2.00 EA …" (qty before EA with a space).
    final qtyBeforeEaRe = RegExp(
      r'(\d+\.\d+)\s+EA\b',
      caseSensitive: false,
    );

    final cpoMatches = cpoRe.allMatches(text).toList();
    if (cpoMatches.isEmpty) {
      warnings.add(
        'No CPO line notes found (expected “Order Line Notes: CPO LINE …” '
        'or “Order Line Notes: CPO #…” ).',
      );
    }

    for (var i = 0; i < cpoMatches.length; i++) {
      final m = cpoMatches[i];
      final cpoNums = m
          .group(1)!
          .split(RegExp(r'\s*,\s*'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (cpoNums.isEmpty) continue;

      final blockStart = m.end;
      final blockEnd =
          i + 1 < cpoMatches.length ? cpoMatches[i + 1].start : text.length;
      final after = text.substring(blockStart, blockEnd);

      // Quantity + description from text before this CPO note.
      final before = text.substring(0, m.start);
      final qtyCandidates = <(int end, double value)>[
        for (final qm in qtyAfterEaRe.allMatches(before))
          (qm.end, double.tryParse(qm.group(1)!) ?? 0),
        for (final qm in qtyBeforeEaRe.allMatches(before))
          (qm.end, double.tryParse(qm.group(1)!) ?? 0),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      var qty = 1;
      if (qtyCandidates.isNotEmpty) {
        final parsed = qtyCandidates.last.$2;
        if (parsed > 0) {
          qty = parsed.round();
          if (qty < 1) qty = 1;
        }
      } else {
        warnings.add(
          'Line CPO #${cpoNums.join(",")} has no quantity — defaulting to 1 label.',
        );
      }

      var description = '';
      if (qtyCandidates.isNotEmpty) {
        final qEnd = qtyCandidates.last.$1;
        final slice = before.substring(qEnd).trim();
        final linesSlice = slice
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && !RegExp(r'^\d+$').hasMatch(l))
            .take(3)
            .join(' ');
        description = linesSlice.length > 120
            ? '${linesSlice.substring(0, 117)}…'
            : linesSlice;
      }

      final identity = _resolveIdentity(
        after: after,
        lookBackStart: (m.start - 400).clamp(0, text.length),
        around: text.substring((m.start - 400).clamp(0, text.length), blockEnd),
        idNoteRe: idNoteRe,
        idLooseRe: idLooseRe,
      );

      for (final cpo in cpoNums) {
        final lineNo = int.tryParse(cpo) ?? (i + 1);
        if (identity == null) {
          incomplete.add(
            BulkIncompleteLine(
              lineNo: lineNo,
              cpo: cpo,
              quantity: qty,
              description: description,
              reason: 'Missing TAG# / PART#',
            ),
          );
          continue;
        }

        final (idKind, idValue) = identity;
        if (idValue.isEmpty) {
          incomplete.add(
            BulkIncompleteLine(
              lineNo: lineNo,
              cpo: cpo,
              quantity: qty,
              description: description,
              reason: 'Empty ${idKind.fieldLabel}',
            ),
          );
          continue;
        }

        lines.add(
          BulkLabelLine(
            lineNo: lineNo,
            cpo: cpo,
            tagOrPart: idValue,
            idKind: idKind,
            quantity: qty,
            description: description,
          ),
        );
      }
    }

    // Deduplicate by CPO if page headers re-emit the same note.
    final deduped = <BulkLabelLine>[];
    final seen = <String>{};
    for (final line in lines) {
      final key = line.cpo;
      if (seen.contains(key)) {
        warnings.add('Duplicate CPO #${line.cpo} ignored.');
        continue;
      }
      seen.add(key);
      deduped.add(line);
    }

    final dedupedIncomplete = <BulkIncompleteLine>[];
    for (final inc in incomplete) {
      if (seen.contains(inc.cpo)) {
        warnings.add(
          'Duplicate incomplete CPO #${inc.cpo} ignored '
          '(already have a complete line).',
        );
        continue;
      }
      seen.add(inc.cpo);
      dedupedIncomplete.add(inc);
    }

    if (deduped.isEmpty && dedupedIncomplete.isEmpty) {
      warnings.add('No printable label lines were parsed from this document.');
    }

    return OrderAckParseResult(
      poNumber: poNumber ?? '',
      orderNumber: orderNumber,
      lines: deduped,
      warnings: warnings,
      incompleteLines: dedupedIncomplete,
      sourceFileName: sourceFileName,
    );
  }

  /// Resolve TAG#/PART# from notes after (or near) a CPO block.
  ///
  /// Fallback: first meaningful line under the CPO note becomes PART#.
  static (BulkIdKind, String)? _resolveIdentity({
    required String after,
    required int lookBackStart,
    required String around,
    required RegExp idNoteRe,
    required RegExp idLooseRe,
  }) {
    var idMatch = idNoteRe.firstMatch(after);
    if (idMatch == null) {
      final anyId = idNoteRe.allMatches(around).toList();
      if (anyId.isNotEmpty) idMatch = anyId.last;
    }
    if (idMatch != null) {
      final kindRaw = idMatch.group(1)!.toUpperCase();
      final idKind =
          kindRaw.startsWith('PART') ? BulkIdKind.part : BulkIdKind.tag;
      final identity =
          idMatch.group(2)!.replaceAll(RegExp(r'\s+'), ' ').trim();
      return (idKind, identity);
    }

    final loose = idLooseRe.firstMatch(after);
    if (loose != null) {
      final kindRaw = loose.group(1)!.toUpperCase();
      final idKind =
          kindRaw.startsWith('PART') ? BulkIdKind.part : BulkIdKind.tag;
      final identity = loose.group(2)!.replaceAll(RegExp(r'\s+'), ' ').trim();
      // Truncate if trailing OA mash leaked onto the same line.
      final cut = identity.split(RegExp(r'\s{2,}|\bEA\b')).first.trim();
      return (idKind, cut.isEmpty ? identity : cut);
    }

    // Fallback: the first non-empty line directly under the CPO note.
    // If that line is a catalog/price row, treat identity as missing (do not
    // scrape following description wrap lines).
    for (final rawLine in after.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (RegExp(r'^Order\s+Line\s+Notes:', caseSensitive: false)
          .hasMatch(line)) {
        return null;
      }
      if (RegExp(r'^Rev\b|^Page\b|^Subtotal\b|^GST\b|^Total\b',
              caseSensitive: false)
          .hasMatch(line)) {
        return null;
      }
      if (RegExp(r'^\d{1,3}$').hasMatch(line)) {
        return null;
      }
      // Catalog/qty rows are not identities.
      if (RegExp(r'\d\s*EA\s*\d|\dEA\d|\bEA\b', caseSensitive: false)
          .hasMatch(line)) {
        return null;
      }
      final identity = line.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (identity.isEmpty) return null;
      return (BulkIdKind.part, identity);
    }
    return null;
  }

  static String? _extractPo(String text) {
    final m = RegExp(
      r'PO\s*Number\s*(P?\d{4,})',
      caseSensitive: false,
    ).firstMatch(text);
    if (m != null) return m.group(1)!.trim();

    final m2 = RegExp(
      r'PO\s*Number[^\n]*\n\s*(P?\d{4,})',
      caseSensitive: false,
    ).firstMatch(text);
    if (m2 != null) return m2.group(1)!.trim();

    // "ProjectLocationPO Number\nP613120" mashed headers.
    final m3 = RegExp(
      r'PO\s*Number[\s\S]{0,40}?\b(P\d{5,})\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (m3 != null) return m3.group(1);

    final m4 = RegExp(r'\b(P\d{5,})\b').firstMatch(text);
    return m4?.group(1);
  }

  static String? _extractOrderNumber(String text) {
    final m = RegExp(
      r'ORDER\s+ACKNOWLEDGEMENT\s*\n\s*(\d{5,})',
      caseSensitive: false,
    ).firstMatch(text);
    if (m != null) return m.group(1);
    final m2 = RegExp(
      r'Order\s*Number\s*(\d{5,})',
      caseSensitive: false,
    ).firstMatch(text);
    return m2?.group(1);
  }
}
