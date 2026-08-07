import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Multiline [TextField] that prefers the parent form scroll view for mouse
/// wheel / trackpad / PageUp / PageDown when the field content does not overflow.
///
/// Fixes the desktop UX where focused multiline fields steal scroll even when
/// empty or short, and where wheel events die over form fields / empty gaps.
class FormScrollTextField extends StatefulWidget {
  const FormScrollTextField({
    super.key,
    required this.controller,
    required this.maxLines,
    this.minLines = 1,
    this.decoration,
  });

  final TextEditingController controller;
  final int maxLines;
  final int minLines;
  final InputDecoration? decoration;

  @override
  State<FormScrollTextField> createState() => _FormScrollTextFieldState();
}

class _FormScrollTextFieldState extends State<FormScrollTextField> {
  final _scrollController = ScrollController();

  bool get _isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  bool _innerCanScroll() {
    if (!_scrollController.hasClients) return false;
    return _scrollController.position.maxScrollExtent > 0.5;
  }

  ScrollPosition? _outerPosition() {
    // Prefer the enclosing form ListView (ancestor). The field's own
    // EditableText Scrollable is a descendant, so it is not returned here.
    final nearest = Scrollable.maybeOf(context);
    if (nearest != null) return nearest.position;
    final primary = PrimaryScrollController.maybeOf(context);
    if (primary != null && primary.hasClients) return primary.position;
    return null;
  }

  void _scrollOuter(double delta) {
    final position = _outerPosition();
    if (position == null || !position.hasPixels) return;
    final next = (position.pixels + delta).clamp(
      0.0,
      position.maxScrollExtent,
    );
    position.jumpTo(next);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (!_isDesktop || event is! PointerScrollEvent) return;
    // When the field itself has overflow, let the TextField scroll its content.
    if (_innerCanScroll()) return;

    // Claim the pointer signal so the empty/short field does not absorb it.
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      if (resolved is PointerScrollEvent) {
        _scrollOuter(resolved.scrollDelta.dy);
      }
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_isDesktop || event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_innerCanScroll()) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.pageDown) {
      _scrollOuter(320);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      _scrollOuter(-320);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: widget.controller,
      scrollController: _scrollController,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      decoration: widget.decoration,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      // Keep caret/selection; never let the field steal viewport focus for wheel.
      scrollPhysics: _isDesktop
          ? const ClampingScrollPhysics()
          : null,
    );

    if (!_isDesktop || widget.maxLines <= 1) {
      return field;
    }

    return Focus(
      onKeyEvent: _onKey,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: _onPointerSignal,
        child: field,
      ),
    );
  }
}
