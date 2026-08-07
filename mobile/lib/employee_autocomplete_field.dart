import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'employee_directory.dart';

/// Free-text employee name field with roster autocomplete.
///
/// Suggestions come from [names] (Supabase `dropdown_roster` / person_by).
/// The user may always type and keep a custom name that is not in the list —
/// there is no forced selection / validation against the roster.
class EmployeeAutocompleteField extends StatefulWidget {
  const EmployeeAutocompleteField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.names,
    this.labelText = 'SWIFT CONTACT',
    this.hintText = 'Type a name or pick from directory',
    this.loading = false,
    this.onRequestRefresh,
    this.dense = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> names;
  final String labelText;
  final String hintText;
  final bool loading;
  final VoidCallback? onRequestRefresh;
  final bool dense;

  @override
  State<EmployeeAutocompleteField> createState() =>
      _EmployeeAutocompleteFieldState();
}

class _EmployeeAutocompleteFieldState extends State<EmployeeAutocompleteField> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant EmployeeAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (widget.focusNode.hasFocus) {
      widget.onRequestRefresh?.call();
      // Nudge Autocomplete to re-run optionsBuilder once the roster arrives
      // while the field is already focused.
      if (widget.names.isNotEmpty) {
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
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: widget.dense ? 4 : 6),
      child: RawAutocomplete<String>(
        // Rebuild when roster size changes so options refresh without retyping.
        key: ValueKey('emp-ac-${widget.names.length}-${widget.labelText}'),
        textEditingController: widget.controller,
        focusNode: widget.focusNode,
        optionsBuilder: (textEditingValue) {
          return EmployeeDirectory.filter(widget.names, textEditingValue.text);
        },
        displayStringForOption: (n) => n,
        onSelected: (n) {
          widget.controller.value = TextEditingValue(
            text: n,
            selection: TextSelection.collapsed(offset: n.length),
          );
        },
        fieldViewBuilder: (context, textController, focusNode, onSubmit) {
          return TextField(
            controller: textController,
            focusNode: focusNode,
            maxLines: 1,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              labelText: widget.labelText,
              hintText: widget.loading
                  ? 'Loading directory…'
                  : widget.hintText,
              suffixIcon: widget.loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (widget.names.isEmpty
                      ? IconButton(
                          tooltip: 'Refresh directory',
                          onPressed: widget.onRequestRefresh,
                          icon: const Icon(Icons.refresh, size: 18),
                        )
                      : Icon(
                          Icons.arrow_drop_down,
                          color: Theme.of(context).hintColor,
                        )),
            ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          final opts = options.toList(growable: false);
          if (opts.isEmpty) return const SizedBox.shrink();
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 260,
                  maxWidth: 420,
                  minWidth: 220,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: opts.length,
                  itemBuilder: (context, i) {
                    final name = opts[i];
                    return ListTile(
                      dense: true,
                      title: Text(name),
                      onTap: () => onSelected(name),
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
