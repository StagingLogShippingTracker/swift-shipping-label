import 'dart:ui';

/// BoxFit.contain math for mapping between image-normalized crop rects and
/// on-screen preview coordinates (handles letterboxing).
class LogoCropGeometry {
  LogoCropGeometry._();

  /// Pixel rect where [imageSize] is drawn with [BoxFit.contain] in [containerSize].
  static Rect containImageRect(Size containerSize, Size imageSize) {
    if (imageSize.width <= 0 || imageSize.height <= 0) {
      return Offset.zero & containerSize;
    }
    final imageAspect = imageSize.width / imageSize.height;
    final containerAspect = containerSize.width / containerSize.height;

    late double w;
    late double h;
    if (imageAspect > containerAspect) {
      w = containerSize.width;
      h = w / imageAspect;
    } else {
      h = containerSize.height;
      w = h * imageAspect;
    }
    return Rect.fromCenter(
      center: Offset(containerSize.width / 2, containerSize.height / 2),
      width: w,
      height: h,
    );
  }

  /// Normalized image rect (0–1) → display rect in container coords.
  static Rect normalizedToDisplay(
    Rect normalized,
    Size containerSize,
    Size imageSize,
  ) {
    final imageRect = containImageRect(containerSize, imageSize);
    return Rect.fromLTWH(
      imageRect.left + normalized.left * imageRect.width,
      imageRect.top + normalized.top * imageRect.height,
      normalized.width * imageRect.width,
      normalized.height * imageRect.height,
    );
  }

  /// Display point → normalized image coords (may be outside 0–1).
  static Offset displayToNormalized(
    Offset display,
    Size containerSize,
    Size imageSize,
  ) {
    final imageRect = containImageRect(containerSize, imageSize);
    if (imageRect.width <= 0 || imageRect.height <= 0) {
      return Offset.zero;
    }
    return Offset(
      (display.dx - imageRect.left) / imageRect.width,
      (display.dy - imageRect.top) / imageRect.height,
    );
  }

  /// Normalized display delta → normalized image delta.
  static Offset displayDeltaToNormalized(
    Offset displayDelta,
    Size containerSize,
    Size imageSize,
  ) {
    final imageRect = containImageRect(containerSize, imageSize);
    if (imageRect.width <= 0 || imageRect.height <= 0) {
      return Offset.zero;
    }
    return Offset(
      displayDelta.dx / imageRect.width,
      displayDelta.dy / imageRect.height,
    );
  }

  /// Clamp normalized crop rect inside image bounds with minimum size.
  static Rect clampNormalized(Rect rect, {double minSize = 0.05}) {
    var left = rect.left;
    var top = rect.top;
    var right = rect.right;
    var bottom = rect.bottom;

    if (right - left < minSize) {
      final cx = (left + right) / 2;
      left = cx - minSize / 2;
      right = cx + minSize / 2;
    }
    if (bottom - top < minSize) {
      final cy = (top + bottom) / 2;
      top = cy - minSize / 2;
      bottom = cy + minSize / 2;
    }

    if (left < 0) {
      right -= left;
      left = 0;
    }
    if (top < 0) {
      bottom -= top;
      top = 0;
    }
    if (right > 1) {
      left -= right - 1;
      right = 1;
    }
    if (bottom > 1) {
      top -= bottom - 1;
      bottom = 1;
    }

    left = left.clamp(0.0, 1.0 - minSize);
    top = top.clamp(0.0, 1.0 - minSize);
    right = right.clamp(left + minSize, 1.0);
    bottom = bottom.clamp(top + minSize, 1.0);
    return Rect.fromLTRB(left, top, right, bottom);
  }
}
