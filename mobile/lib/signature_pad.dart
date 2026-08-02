import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Lightweight signature capture (mouse / touch) without extra packages.
class SignaturePad extends StatefulWidget {
  const SignaturePad({super.key, this.height = 140});

  final double height;

  @override
  State<SignaturePad> createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  final List<List<Offset>> _strokes = [];
  List<Offset>? _current;

  bool get isEmpty =>
      _strokes.isEmpty && (_current == null || _current!.length < 2);

  void clear() {
    setState(() {
      _strokes.clear();
      _current = null;
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

  void _start(Offset pos) {
    setState(() => _current = [pos]);
  }

  void _move(Offset pos) {
    setState(() => _current?.add(pos));
  }

  void _end() {
    setState(() {
      if (_current != null && _current!.length >= 2) {
        _strokes.add(List.of(_current!));
      }
      _current = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) => _start(e.localPosition),
      onPointerMove: (e) => _move(e.localPosition),
      onPointerUp: (_) => _end(),
      onPointerCancel: (_) => _end(),
      child: CustomPaint(
        size: Size(double.infinity, widget.height),
        painter: _SignaturePainter(
          strokes: _strokes,
          current: _current,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
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
      old.strokes != strokes || old.current != current;
}
