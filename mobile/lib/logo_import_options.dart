import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'theme.dart';

/// How to crop a logo before import.
enum LogoCropMode {
  auto,
  manual,
  none;

  String get label => switch (this) {
        LogoCropMode.auto => 'Auto-crop',
        LogoCropMode.manual => 'Manual crop',
        LogoCropMode.none => 'Leave as is',
      };
}

/// Post-pick editing choices for logo import.
class LogoImportOptions {
  const LogoImportOptions({
    required this.removeBackground,
    required this.cropMode,
    this.manualCropRect,
  });

  /// When [recreate] is true, background removal is handled by the vectorizer.
  factory LogoImportOptions.forRecreate({
    LogoCropMode cropMode = LogoCropMode.auto,
    Rect? manualCropRect,
  }) =>
      LogoImportOptions(
        removeBackground: true,
        cropMode: cropMode,
        manualCropRect: manualCropRect,
      );

  factory LogoImportOptions.standard({
    bool removeBackground = true,
    LogoCropMode cropMode = LogoCropMode.auto,
    Rect? manualCropRect,
  }) =>
      LogoImportOptions(
        removeBackground: removeBackground,
        cropMode: cropMode,
        manualCropRect: manualCropRect,
      );

  final bool removeBackground;
  final LogoCropMode cropMode;

  /// Normalized crop rect (0–1) relative to image bounds; used when
  /// [cropMode] is [LogoCropMode.manual].
  final Rect? manualCropRect;
}

/// Post-pick logo edit prompt — crop + optional background removal.
///
/// When [recreate] is checked, Recreate options (crop) are shown first and
/// background removal is implied by the vectorizer.
Future<LogoImportOptions?> showLogoImportEditDialog(
  BuildContext context, {
  required Uint8List previewBytes,
  required bool recreate,
}) {
  return showDialog<LogoImportOptions>(
    context: context,
    builder: (ctx) => _LogoImportEditDialog(
      previewBytes: previewBytes,
      recreate: recreate,
    ),
  );
}

class _LogoImportEditDialog extends StatefulWidget {
  const _LogoImportEditDialog({
    required this.previewBytes,
    required this.recreate,
  });

  final Uint8List previewBytes;
  final bool recreate;

  @override
  State<_LogoImportEditDialog> createState() => _LogoImportEditDialogState();
}

class _LogoImportEditDialogState extends State<_LogoImportEditDialog> {
  var _removeBg = true;
  var _cropMode = LogoCropMode.auto;
  Rect? _manualCrop;

  @override
  Widget build(BuildContext context) {
    final title = widget.recreate ? 'Prepare for Recreate' : 'Edit logo';
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.recreate) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: SwiftColors.bg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: SwiftColors.border),
                  ),
                  child: const Text(
                    'Recreate will vectorize this logo, strip the background, '
                    'and output a high-definition transparent PNG. Choose how '
                    'to crop the source before tracing.',
                    style: TextStyle(fontSize: 13, color: SwiftColors.muted),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ColoredBox(
                  color: const Color(0xFFE8E8E8),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: _cropMode == LogoCropMode.manual
                        ? _ManualCropEditor(
                            bytes: widget.previewBytes,
                            initialRect: _manualCrop,
                            onChanged: (r) => setState(() => _manualCrop = r),
                          )
                        : Image.memory(
                            widget.previewBytes,
                            height: 120,
                            fit: BoxFit.contain,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                widget.recreate ? 'CROP BEFORE RECREATE' : 'CROP',
                style: const TextStyle(
                  fontFamily: 'Oswald',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: SwiftColors.muted,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 6),
              SegmentedButton<LogoCropMode>(
                segments: [
                  for (final mode in LogoCropMode.values)
                    ButtonSegment(value: mode, label: Text(mode.label)),
                ],
                selected: {_cropMode},
                onSelectionChanged: (s) =>
                    setState(() => _cropMode = s.first),
              ),
              if (!widget.recreate) ...[
                const SizedBox(height: 14),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _removeBg,
                  onChanged: (v) => setState(() => _removeBg = v ?? false),
                  title: const Text('Remove background'),
                  subtitle: const Text(
                    'Strip a solid outer background to transparent',
                    style: TextStyle(fontSize: 12, color: SwiftColors.muted),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_cropMode == LogoCropMode.manual &&
                (_manualCrop == null || _manualCrop!.width < 0.05)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Drag the crop box or choose Auto-crop.'),
                ),
              );
              return;
            }
            Navigator.pop(
              context,
              widget.recreate
                  ? LogoImportOptions.forRecreate(
                      cropMode: _cropMode,
                      manualCropRect: _manualCrop,
                    )
                  : LogoImportOptions.standard(
                      removeBackground: _removeBg,
                      cropMode: _cropMode,
                      manualCropRect: _manualCrop,
                    ),
            );
          },
          child: Text(widget.recreate ? 'Recreate & import' : 'Import'),
        ),
      ],
    );
  }
}

/// Interactive normalized crop rectangle over [bytes].
class _ManualCropEditor extends StatefulWidget {
  const _ManualCropEditor({
    required this.bytes,
    required this.onChanged,
    this.initialRect,
  });

  final Uint8List bytes;
  final Rect? initialRect;
  final ValueChanged<Rect> onChanged;

  @override
  State<_ManualCropEditor> createState() => _ManualCropEditorState();
}

class _ManualCropEditorState extends State<_ManualCropEditor> {
  late Rect _rect;

  @override
  void initState() {
    super.initState();
    _rect = widget.initialRect ?? const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8);
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onChanged(_rect));
  }

  void _update(Rect r) {
    setState(() => _rect = r);
    widget.onChanged(r);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const maxH = 220.0;
        return SizedBox(
          height: maxH,
          child: GestureDetector(
            onPanUpdate: (d) {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null) return;
              final size = box.size;
              final dx = d.delta.dx / size.width;
              final dy = d.delta.dy / size.height;
              var next = _rect.shift(Offset(dx, dy));
              next = Rect.fromLTWH(
                next.left.clamp(0.0, 1.0 - next.width),
                next.top.clamp(0.0, 1.0 - next.height),
                next.width,
                next.height,
              );
              _update(next);
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(widget.bytes, fit: BoxFit.contain),
                CustomPaint(
                  painter: _CropOverlayPainter(normalizedRect: _rect),
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: IconButton.filledTonal(
                    tooltip: 'Reset crop',
                    onPressed: () =>
                        _update(const Rect.fromLTWH(0.05, 0.05, 0.9, 0.9)),
                    icon: const Icon(Icons.crop_free, size: 18),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  _CropOverlayPainter({required this.normalizedRect});

  final Rect normalizedRect;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      normalizedRect.left * size.width,
      normalizedRect.top * size.height,
      normalizedRect.width * size.width,
      normalizedRect.height * size.height,
    );
    final shade = Paint()..color = const Color(0x88000000);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRect(rect),
      ),
      shade,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = SwiftColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) =>
      oldDelegate.normalizedRect != normalizedRect;
}
