import 'dart:async';

import 'package:flutter/material.dart';

import 'address_book_sync.dart';
import 'osm_nominatim_client.dart';

class AddressSuggestion {
  const AddressSuggestion({
    required this.address,
    required this.caption,
    this.fromBook = false,
    this.placeName = '',
  });

  final String address;
  final String caption;
  final bool fromBook;
  /// Ship-to / company name from the address book; empty for OSM hits.
  final String placeName;
}

/// Full current field text for Nominatim — including an incomplete last word.
/// Do not drop the last token or wait for a trailing space.
String addressSearchQuery(String raw) => raw.trim();

bool shouldSearchRemoteAddress(String raw) =>
    addressSearchQuery(raw).length >= 3;

/// Subtitle for an address-book hit. Keeps ship-to / company text.
String savedAddressCaption(String shipToName) {
  final name = shipToName.trim();
  return name.isEmpty ? 'Saved' : 'Saved · $name';
}

/// Overlay rows: optional section headers, then suggestions.
class AddressSuggestOverlayItem {
  const AddressSuggestOverlayItem.header(this.header) : suggestion = null;

  const AddressSuggestOverlayItem.suggestion(this.suggestion) : header = null;

  final String? header;
  final AddressSuggestion? suggestion;

  bool get isHeader => header != null;
}

List<AddressSuggestOverlayItem> addressSuggestOverlayItems(
  List<AddressSuggestion> options,
) {
  final book = options.where((s) => s.fromBook).toList();
  final osm = options.where((s) => !s.fromBook).toList();
  final out = <AddressSuggestOverlayItem>[];
  if (book.isNotEmpty) {
    out.add(const AddressSuggestOverlayItem.header('Saved addresses'));
    for (final s in book) {
      out.add(AddressSuggestOverlayItem.suggestion(s));
    }
  }
  if (osm.isNotEmpty) {
    out.add(const AddressSuggestOverlayItem.header('Suggested addresses'));
    for (final s in osm) {
      out.add(AddressSuggestOverlayItem.suggestion(s));
    }
  }
  return out;
}

List<AddressSuggestion> mergeAddressSuggestions({
  required String raw,
  required List<DeliveryAddressEntry> entries,
  required List<NominatimHit> osmHits,
  int limit = 8,
}) {
  final q = raw.trim().toLowerCase();
  final out = <AddressSuggestion>[];
  final seen = <String>{};

  void add(AddressSuggestion s) {
    final k = s.address.trim().toLowerCase();
    if (k.isEmpty || !seen.add(k)) return;
    out.add(s);
  }

  for (final e in entries) {
    if (q.isEmpty) {
      add(
        AddressSuggestion(
          address: e.address,
          caption: savedAddressCaption(e.shipToName),
          fromBook: true,
          placeName: e.shipToName,
        ),
      );
      continue;
    }
    final blob = '${e.shipToName} ${e.address}'.toLowerCase();
    if (blob.contains(q)) {
      add(
        AddressSuggestion(
          address: e.address,
          caption: savedAddressCaption(e.shipToName),
          fromBook: true,
          placeName: e.shipToName,
        ),
      );
    }
  }

  // Nominatim ranking — keep hits even if they do not substring-match [raw].
  for (final p in osmHits) {
    add(
      AddressSuggestion(
        address: p.displayAddress,
        caption: 'Suggested address',
      ),
    );
  }

  return out.take(limit).toList();
}

/// Delivery address: address book first, then OpenStreetMap Nominatim.
class AddressSuggestField extends StatefulWidget {
  const AddressSuggestField({
    super.key,
    required this.controller,
    required this.entries,
    required this.shipToName,
    required this.customer,
    this.labelText = 'DELIVERY ADDRESS',
    this.onPickedBookEntry,
    this.onPicked,
  });

  final TextEditingController controller;
  final List<DeliveryAddressEntry> entries;
  final String Function() shipToName;
  final String Function() customer;
  final String labelText;
  final ValueChanged<DeliveryAddressEntry>? onPickedBookEntry;
  final ValueChanged<AddressSuggestion>? onPicked;

  @override
  State<AddressSuggestField> createState() => _AddressSuggestFieldState();
}

class _AddressSuggestFieldState extends State<AddressSuggestField> {
  final _focus = FocusNode();
  final _layerLink = LayerLink();
  final _fieldKey = GlobalKey();
  final _osm = OsmNominatimClient();
  OverlayEntry? _overlay;
  Timer? _debounce;
  Timer? _hideTimer;
  List<NominatimHit> _osmHits = const [];
  bool _thinking = false;
  int _req = 0;
  String _lastText = '';
  String? _hideAfterPick;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    _lastText = widget.controller.text;
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(covariant AddressSuggestField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hideTimer?.cancel();
    widget.controller.removeListener(_onText);
    _focus.removeListener(_onFocus);
    _removeOverlay();
    _focus.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _hideTimer?.cancel();
      _scheduleSuggest(widget.controller.text);
      _syncOverlay();
    } else {
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(milliseconds: 150), () {
        if (!_focus.hasFocus) _removeOverlay();
      });
    }
  }

  void _onText() {
    final t = widget.controller.text;
    if (t != _lastText) {
      _lastText = t;
      if (_hideAfterPick != null && t != _hideAfterPick) {
        _hideAfterPick = null;
      }
      _scheduleSuggest(t);
    }
    _syncOverlay();
  }

  void _scheduleSuggest(String query) {
    _debounce?.cancel();
    if (!shouldSearchRemoteAddress(query)) {
      if (_osmHits.isNotEmpty) {
        setState(() => _osmHits = const []);
        _syncOverlay();
      }
      return;
    }
    // Nominatim: 1 req/s. Short debounce + stale-response ignore (not Space).
    _debounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_fetch(addressSearchQuery(query)));
    });
  }

  Future<void> _fetch(String query) async {
    final id = ++_req;
    if (mounted) setState(() => _thinking = true);
    try {
      final hits = await _osm.search(query);
      if (!mounted || id != _req) return;
      setState(() {
        _osmHits = hits;
        _thinking = false;
      });
      _syncOverlay();
    } catch (_) {
      if (!mounted || id != _req) return;
      setState(() => _thinking = false);
    }
  }

  List<AddressSuggestion> _options(String raw) {
    return mergeAddressSuggestions(
      raw: raw,
      entries: widget.entries,
      osmHits: _osmHits,
    );
  }

  void _pick(AddressSuggestion s) {
    final addr = s.address;
    _hideAfterPick = addr;
    widget.controller.value = TextEditingValue(
      text: addr,
      selection: TextSelection.collapsed(offset: addr.length),
    );
    _removeOverlay();
    widget.onPicked?.call(s);
    if (s.fromBook && widget.onPickedBookEntry != null) {
      for (final e in widget.entries) {
        if (e.address.trim().toLowerCase() == s.address.trim().toLowerCase()) {
          widget.onPickedBookEntry!(e);
          break;
        }
      }
    }
  }

  void _syncOverlay() {
    if (!mounted || !_focus.hasFocus) return;
    if (_hideAfterPick != null &&
        widget.controller.text == _hideAfterPick) {
      _removeOverlay();
      return;
    }
    final options = _options(widget.controller.text);
    if (options.isEmpty) {
      _removeOverlay();
      return;
    }
    if (_overlay == null) {
      _overlay = OverlayEntry(builder: _buildOverlay);
      Overlay.of(context, rootOverlay: true).insert(_overlay!);
    } else {
      _overlay!.markNeedsBuild();
    }
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    final options = _options(widget.controller.text);
    if (options.isEmpty) return const SizedBox.shrink();
    final rows = addressSuggestOverlayItems(options);
    final theme = Theme.of(context);
    final chromeHint = theme.hintColor;
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 520;
    return CompositedTransformFollower(
      link: _layerLink,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      child: Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: 280, maxWidth: width),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final row = rows[i];
                if (row.isHeader) {
                  return Padding(
                    padding: EdgeInsets.fromLTRB(16, i == 0 ? 8 : 10, 16, 4),
                    child: Text(
                      row.header!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.35,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  );
                }
                final s = row.suggestion!;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      dense: true,
                      title: Text(s.address, maxLines: 3),
                      subtitle: Text(
                        s.caption,
                        style: TextStyle(color: chromeHint, fontSize: 12),
                      ),
                      onTap: () => _pick(s),
                    ),
                    if (i < rows.length - 1 && !rows[i + 1].isHeader)
                      const Divider(height: 1),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        key: _fieldKey,
        controller: widget.controller,
        focusNode: _focus,
        minLines: 2,
        maxLines: 3,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          labelText: widget.labelText,
          hintText:
              'Type a street or pick a suggestion — or enter manually',
          suffixIcon: _thinking
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
