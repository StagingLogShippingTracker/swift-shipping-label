import 'dart:convert';

/// Multi-value sales-order / PO / packing-list / project parsing and SO mapping.

/// Join token used in the form and on PDFs: `NUMBER / NUMBER / NUMBER`.
const multiValueJoin = ' / ';

final _namedSplit = RegExp(r'\s*/\s*|,\s*');

/// Extract tokens and format as `n / n / n` — same rules as PO / project.
String formatSalesOrders(String raw, {bool finalize = true}) {
  return formatNamedSegments(raw, finalize: finalize);
}

List<String> parseSalesOrders(String raw) {
  return parseNamedSegments(raw, finalize: true);
}

/// PO / packing list / project: never split on spaces.
/// Comma (while typing or on blur) and `/` (on blur) are separators.
String formatNamedSegments(String raw, {required bool finalize}) {
  if (!finalize && !raw.contains(',')) return raw;
  final parts = parseNamedSegments(raw, finalize: finalize);
  final trailingSep = !finalize && raw.trimRight().endsWith(',');
  if (parts.isEmpty) {
    return trailingSep ? '' : (finalize ? raw.trim() : raw);
  }
  final joined = parts.join(multiValueJoin);
  if (trailingSep) return '$joined$multiValueJoin';
  return joined;
}

List<String> parseNamedSegments(String raw, {bool finalize = true}) {
  final s = raw.trim();
  if (s.isEmpty) return const [];
  final chunks = finalize ? s.split(_namedSplit) : s.split(',');
  final out = <String>[];
  for (final c in chunks) {
    final t = c.trim();
    if (t.isEmpty) continue;
    out.add(t);
  }
  if (out.isEmpty) return s.isEmpty ? const [] : [s];
  return out;
}

/// How many extras can be paired 1:1 with sales orders.
int pairableCount(int extraCount, int salesOrderCount) {
  if (extraCount <= 1 || salesOrderCount <= 1) return 0;
  return extraCount < salesOrderCount ? extraCount : salesOrderCount;
}

/// Next mapping step. [assigned] maps extra-index → sales order.
class MappingStep {
  const MappingStep._({
    required this.done,
    this.askIndex,
    this.askValue,
    this.choices = const [],
    this.assigned = const {},
  });

  final bool done;
  final int? askIndex;
  final String? askValue;
  final List<String> choices;
  final Map<int, String> assigned;

  factory MappingStep.complete(Map<int, String> assigned) =>
      MappingStep._(done: true, assigned: Map<int, String>.from(assigned));

  factory MappingStep.ask({
    required int index,
    required String value,
    required List<String> choices,
    required Map<int, String> assigned,
  }) =>
      MappingStep._(
        done: false,
        askIndex: index,
        askValue: value,
        choices: List<String>.from(choices),
        assigned: Map<int, String>.from(assigned),
      );
}

/// Deduce remaining 1:1 pairs; ask until only one extra and one SO remain
/// among the pairable set. Leftover extras beyond [salesOrders] are ignored.
MappingStep nextMappingStep({
  required List<String> extras,
  required List<String> salesOrders,
  Map<int, String> assigned = const {},
}) {
  final n = pairableCount(extras.length, salesOrders.length);
  if (n == 0) return MappingStep.complete(const {});

  final map = Map<int, String>.from(assigned);
  map.removeWhere((i, so) => i < 0 || i >= n || so.trim().isEmpty);

  while (true) {
    final used = map.values.map((e) => e.trim()).toSet();
    final remainingIdx = <int>[
      for (var i = 0; i < n; i++)
        if (!map.containsKey(i)) i,
    ];
    final remainingSos = [
      for (final so in salesOrders)
        if (!used.contains(so)) so,
    ];
    if (remainingIdx.isEmpty) {
      return MappingStep.complete(map);
    }
    if (remainingSos.length == 1 && remainingIdx.length == 1) {
      map[remainingIdx.first] = remainingSos.first;
      continue;
    }
    final idx = remainingIdx.first;
    return MappingStep.ask(
      index: idx,
      value: extras[idx],
      choices: remainingSos,
      assigned: map,
    );
  }
}

Map<String, String> mappingBySalesOrder({
  required List<String> extras,
  required Map<int, String> assigned,
}) {
  final out = <String, String>{};
  for (final e in assigned.entries) {
    if (e.key < 0 || e.key >= extras.length) continue;
    final so = e.value.trim();
    if (so.isEmpty) continue;
    out[so] = extras[e.key];
  }
  return out;
}

/// JSON for [LabelFields.soFieldMap]: `{ "po_num": { "1422989": "PO A" }, ... }`.
class SoFieldMap {
  SoFieldMap([Map<String, Map<String, String>>? links])
      : links = links ?? {};

  final Map<String, Map<String, String>> links;

  Map<String, String> forField(String fieldKey) =>
      links[fieldKey] ?? const {};

  String valueFor(String fieldKey, String salesOrder) =>
      (links[fieldKey]?[salesOrder] ?? '').trim();

  void setField(String fieldKey, Map<String, String> soToValue) {
    links[fieldKey] = Map<String, String>.from(soToValue);
  }

  String encode() => jsonEncode(links);

  static SoFieldMap decode(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return SoFieldMap();
    try {
      final decoded = jsonDecode(t);
      if (decoded is! Map) return SoFieldMap();
      final out = <String, Map<String, String>>{};
      for (final e in decoded.entries) {
        final inner = e.value;
        if (inner is! Map) continue;
        out['${e.key}'] = {
          for (final ie in inner.entries) '${ie.key}': '${ie.value}',
        };
      }
      return SoFieldMap(out);
    } catch (_) {
      return SoFieldMap();
    }
  }
}
