import 'bulk/bulk_label_models.dart';
import 'gemini_client.dart';

/// Gemini overlay for Swift OA / packing-list field extraction and
/// leftover address-book merge decisions.
class JobPdfAi {
  JobPdfAi({GeminiClient? client}) : _gemini = client ?? GeminiClient();

  final GeminiClient _gemini;

  Future<OrderAckParseResult> enrich(OrderAckParseResult parsed, String text) async {
    if (!GeminiClient.isConfigured) return parsed;
    final snippet = text.length > 9000 ? text.substring(0, 9000) : text;
    final data = await _gemini.generateJson(
      prompt: '''
You extract fields from a Swift Oilfield Supply Order Acknowledgement or Packing List.

Document text:
"""
$snippet
"""

Return JSON only:
{
  "document_kind": "order_ack" or "packing_list",
  "customer_name": "Bill To company name only",
  "sales_order": "Swift order number",
  "packing_slip": "Swift packing slip/list number if this is a packing list, else empty",
  "po_number": "customer PO",
  "project": "project number",
  "delivery_ship_to_name": "name from Delivery Instructions (c/o), else empty",
  "delivery_ship_to_address": "street/city from Delivery Instructions, else empty",
  "header_ship_to_name": "Ship To header name",
  "header_ship_to_address": "Ship To header address",
  "carrier": "carrier from delivery instructions if present"
}

Rules:
- packing_slip is only on packing lists, never invent one for an OA.
- Prefer Delivery Instructions over the Ship To header for the actual destination.
- Empty string when unknown.
''',
    );
    if (data == null) return parsed;
    String g(String k) => '${data[k] ?? ''}'.trim();

    String pick(String current, String incoming) =>
        current.isNotEmpty ? current : incoming;

    final kind = g('document_kind');
    final packing = g('packing_slip');
    final deliveryName = g('delivery_ship_to_name');
    final deliveryAddr = g('delivery_ship_to_address');
    return parsed.copyWith(
      documentKind: kind == 'packing_list' || parsed.documentKind == 'packing_list'
          ? 'packing_list'
          : parsed.documentKind,
      customerName: pick(parsed.customerName, g('customer_name')),
      orderNumber: pick(parsed.orderNumber, g('sales_order')),
      packingSlipNumber: pick(parsed.packingSlipNumber, packing),
      poNumber: pick(parsed.poNumber, g('po_number')),
      projectNumber: pick(parsed.projectNumber, g('project')),
      deliveryShipToName: pick(parsed.deliveryShipToName, deliveryName),
      deliveryShipToAddress: pick(parsed.deliveryShipToAddress, deliveryAddr),
      headerShipToName: pick(parsed.headerShipToName, g('header_ship_to_name')),
      headerShipToAddress:
          pick(parsed.headerShipToAddress, g('header_ship_to_address')),
      deliveryCarrier: pick(parsed.deliveryCarrier, g('carrier')),
      hasDeliveryShipTo: parsed.hasDeliveryShipTo ||
          deliveryName.isNotEmpty ||
          deliveryAddr.isNotEmpty,
    );
  }

  /// When two rows share a ship-to name but rules did not merge, ask Gemini.
  Future<bool> samePlace({
    required String shipToA,
    required String addressA,
    required String shipToB,
    required String addressB,
  }) async {
    if (!GeminiClient.isConfigured) return false;
    final data = await _gemini.generateJson(
      timeout: const Duration(seconds: 12),
      prompt: '''
Are these the same physical delivery location for a warehouse address book?
Name A: "$shipToA"
Address A: "$addressA"
Name B: "$shipToB"
Address B: "$addressB"

Treat extra city, province, or postal code as the same place.
Different civic numbers are different places.
Different companies / c/o names are different places.

Return JSON only: { "same_place": true }
''',
    );
    if (data == null) return false;
    final v = data['same_place'];
    return v == true || v == 'true';
  }

  /// Predictive delivery-address lines. Empty if unconfigured or query too short.
  Future<List<String>> suggestAddresses({
    required String query,
    String shipToName = '',
    String customer = '',
  }) async {
    if (!GeminiClient.isConfigured) return const [];
    final q = query.trim();
    if (q.length < 3) return const [];
    final data = await _gemini.generateJson(
      timeout: const Duration(seconds: 12),
      prompt: '''
Suggest up to 5 Canadian oilfield / industrial delivery addresses for a shipping label.

User is typing: "$q"
Ship To Name: "${shipToName.trim().isEmpty ? '(none)' : shipToName.trim()}"
Customer: "${customer.trim().isEmpty ? '(none)' : customer.trim()}"

Return JSON only:
{ "suggestions": ["3360 10 Street\\nNisku, AB T9E 1E7"] }

Rules:
- Western Canada (AB/BC/SK) industrial, shop, and wellsite addresses are in scope.
- Remote locations, LSD, lease roads, and site numbers that are NOT on Google Maps are valid. If the user typed a site or LSD, suggest completing that site — do not invent a city street instead.
- Do not invent a civic number you are not reasonably sure about.
- Prefer 1–3 line addresses (street or site, city/province, postal if known).
- If nothing is plausible, return { "suggestions": [] }.
''',
    );
    if (data == null) return const [];
    final list = data['suggestions'];
    if (list is! List) return const [];
    final out = <String>[];
    final seen = <String>{};
    for (final item in list) {
      final s = '$item'.replaceAll('\r\n', '\n').trim();
      if (s.isEmpty) continue;
      final k = s.toLowerCase();
      if (seen.add(k)) out.add(s);
      if (out.length >= 5) break;
    }
    return out;
  }
}

String joinJobPdfValues(Iterable<String> values) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in values) {
    final t = raw.trim();
    if (t.isEmpty) continue;
    final k = t.toLowerCase();
    if (seen.add(k)) out.add(t);
  }
  return out.join(' / ');
}
