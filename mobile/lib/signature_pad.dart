import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Signature capture for mouse, touch, and stylus (S Pen) without extra packages.
class SignaturePad extends StatefulWidget {
  const SignaturePad({super.key, this.height = 220});

  final double height;

  @override
  State<SignaturePad> createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  final List<List<Offset>> _strokes = [];
  List<Offset>? _current;
  int? _activePointer;

  bool get isEmpty =>
      _strokes.isEmpty && (_current == null || _current!.length < 2);

  void clear() {
    setState(() {
      _strokes.clear();
      _current = null;
      _activePointer = null;
    });
  }

  Future<Uint8List?> exportPng({int width = 480, int height = 140}) async {
    if (isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final paint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in [..._strokes, if (_current != null) _current!]) {
      if (stroke.length < 2) continue;
      for (var i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  void _start(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    setState(() => _current = [event.localPosition]);
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    setState(() {
      _current = [...?_current, event.localPosition];
    });
  }

  void _end(int pointer) {
    if (pointer != _activePointer) return;
    setState(() {
      if (_current != null && _current!.length >= 2) {
        _strokes.add(List.of(_current!));
      }
      _current = null;
      _activePointer = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).dividerColor;

    return NotificationListener<ScrollNotification>(
      onNotification: (_) => true,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _start,
        onPointerMove: _move,
        onPointerUp: (event) => _end(event.pointer),
        onPointerCancel: (event) => _end(event.pointer),
        child: RepaintBoundary(
          child: SizedBox(
            width: double.infinity,
            height: widget.height,
            child: CustomPaint(
              painter: _SignaturePainter(
                strokes: _strokes,
                current: _current,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: borderColor),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter({required this.strokes, required this.current});

  final List<List<Offset>> strokes;
  final List<Offset>? current;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in [...strokes, if (current != null) current!]) {
      if (stroke.length < 2) continue;
      for (var i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter old) =>
      old.strokes.length != strokes.length ||
      old.current?.length != current?.length ||
      old.current != current;
}
