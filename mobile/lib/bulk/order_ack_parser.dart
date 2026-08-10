import 'bulk_label_models.dart';

/// Parses Swift Order Acknowledgement text (from pdfrx / pypdf) into bulk lines.
///
/// Identity field comes from OA line notes:
/// - `Order Line Notes: TAG# …` → valve sticker prints **TAG#**
/// - `Order Line Notes: PART# …` → non-valve sticker prints **PART#**
/// Only one of the two appears per line.
///
/// Lines with CPO but no TAG#/PART# are collected in
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
    final cpoRe = RegExp(
      r'Order\s+Line\s+Notes:\s*CPO\s*#\s*(\d+)',
      caseSensitive: false,
    );
    // TAG# or PART# (Propak PMs use one or the other per line).
    final idRe = RegExp(
      r'Order\s+Line\s+Notes:\s*(TAG|PART)\s*#\s*(.+)$',
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
        'No CPO line notes found (expected “Order Line Notes: CPO #…” ).',
      );
    }

    for (var i = 0; i < cpoMatches.length; i++) {
      final m = cpoMatches[i];
      final cpo = m.group(1)!.trim();
      final lineNo = int.tryParse(cpo) ?? (i + 1);

      final blockStart = m.end;
      final blockEnd =
          i + 1 < cpoMatches.length ? cpoMatches[i + 1].start : text.length;
      final after = text.substring(blockStart, blockEnd);

      var idMatch = idRe.firstMatch(after);
      // Id note may appear before CPO on a rare page-break layout.
      if (idMatch == null) {
        final lookBackStart = (m.start - 400).clamp(0, text.length);
        final around = text.substring(lookBackStart, blockEnd);
        final anyId = idRe.allMatches(around).toList();
        if (anyId.isNotEmpty) idMatch = anyId.last;
      }

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
        warnings.add('Line CPO #$cpo has no quantity — defaulting to 1 label.');
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

      if (idMatch == null) {
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

      final kindRaw = idMatch.group(1)!.toUpperCase();
      final idKind =
          kindRaw.startsWith('PART') ? BulkIdKind.part : BulkIdKind.tag;
      var identity = idMatch.group(2)!.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (identity.isEmpty) {
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
          tagOrPart: identity,
          idKind: idKind,
          quantity: qty,
          description: description,
        ),
      );
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

    final m3 = RegExp(r'\b(P\d{5,})\b').firstMatch(text);
    return m3?.group(1);
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
