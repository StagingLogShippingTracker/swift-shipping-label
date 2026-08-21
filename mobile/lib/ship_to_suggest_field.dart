import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'address_book_sync.dart';

/// Free-text Ship To / consignee name with address-book memory suggestions.
///
/// Each saved location is listed separately (same name, different address).
/// Picking a row fills name + address via [onPicked]. Custom names are always
/// allowed when the user types without selecting.
class ShipToSuggestField extends StatefulWidget {
  const ShipToSuggestField({
    super.key,
    required this.controller,
    required this.entries,
    required this.onPicked,
    this.focusNode,
    this.labelText = 'SHIP TO NAME',
    this.hintText =
        'Type a name or pick a saved location from memory',
    this.dense = false,
  });

  final TextEditingController controller;
  final List<DeliveryAddressEntry> entries;
  final ValueChanged<DeliveryAddressEntry> onPicked;
  final FocusNode? focusNode;
  final String labelText;
  final String hintText;
  final bool dense;

  @override
  State<ShipToSuggestField> createState() => _ShipToSuggestFieldState();
}

class _ShipToSuggestFieldState extends State<ShipToSuggestField> {
  late final FocusNode _focus;
  var _ownsFocus = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _focus = widget.focusNode!;
    } else {
      _focus = FocusNode();
      _ownsFocus = true;
    }
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    if (_ownsFocus) _focus.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focus.hasFocus && widget.entries.isNotEmpty) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final t = widget.controller.text;
        widget.controller.value = TextEditingValue(
          text: t,
          selection: TextSelection.collapsed(offset: t.length),
        );
      });
    }
  }

  List<DeliveryAddressEntry> _filter(String raw) {
    final q = raw.trim().toLowerCase();
    final list = List<DeliveryAddressEntry>.from(widget.entries);
    // Newest first; keep every distinct location (do not collapse by name).
    list.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    if (q.isEmpty) return list.take(12).toList();
    final hit = <DeliveryAddressEntry>[];
    for (final e in list) {
      final name = e.shipToName.toLowerCase();
      final addr = e.address.toLowerCase();
      if (name.contains(q) || addr.contains(q)) hit.add(e);
      if (hit.length >= 12) break;
    }
    return hit;
  }

  String _optionKey(DeliveryAddressEntry e) =>
      '${e.shipToName}\u0001${e.address}\u0001${e.addressKey}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: widget.dense ? 4 : 6),
      child: RawAutocomplete<DeliveryAddressEntry>(
        textEditingController: widget.controller,
        focusNode: _focus,
        optionsBuilder: (TextEditingValue tev) {
          return _filter(tev.text);
        },
        displayStringForOption: (e) => e.shipToName,
        onSelected: (e) {
          widget.controller.text = e.shipToName;
          widget.onPicked(e);
        },
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            maxLines: 1,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => onFieldSubmitted(),
            decoration: InputDecoration(
              labelText: widget.labelText,
              hintText: widget.hintText,
            ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          final opts = options.toList();
          if (opts.isEmpty) return const SizedBox.shrink();
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280, maxWidth: 520),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: opts.length,
                  itemBuilder: (context, i) {
                    final e = opts[i];
                    return ListTile(
                      dense: true,
                      key: ValueKey(_optionKey(e)),
                      title: Text(
                        e.shipToName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        e.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => onSelected(e),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
