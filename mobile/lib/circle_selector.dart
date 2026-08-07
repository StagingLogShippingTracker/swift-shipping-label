import 'package:flutter/material.dart';

import 'theme.dart';

/// Circle selector matching the React Native reference:
/// empty orange ring when off; ring + inset filled dot when on.
class SwiftCircleSelector extends StatelessWidget {
  const SwiftCircleSelector({
    super.key,
    required this.selected,
    this.size = 22,
    this.color = SwiftColors.accent,
  });

  final bool selected;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final gap = (size * 0.18).clamp(3.0, 5.0);
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
          color: Colors.transparent,
        ),
        child: selected
            ? Padding(
                padding: EdgeInsets.all(gap),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// Tappable circle checkbox with optional label.
class SwiftCircleCheckbox extends StatelessWidget {
  const SwiftCircleCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.subtitle,
    this.dense = false,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool?>? onChanged;
  final String? label;
  final String? subtitle;
  final bool dense;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final chrome = SwiftChromeColors.of(context);
    final canTap = enabled && onChanged != null;
    return InkWell(
      onTap: canTap ? () => onChanged!(!value) : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 2 : 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Opacity(
                opacity: enabled ? 1 : 0.45,
                child: SwiftCircleSelector(selected: value, size: dense ? 20 : 22),
              ),
            ),
            if (label != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label!,
                      style: TextStyle(
                        fontSize: dense ? 13 : 14,
                        fontWeight: FontWeight.w600,
                        color: chrome.ink.withValues(alpha: enabled ? 1 : 0.5),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          color: chrome.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Exclusive circle radio option.
class SwiftCircleRadio<T> extends StatelessWidget {
  const SwiftCircleRadio({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    required this.label,
    this.dense = false,
  });

  final T value;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final String label;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    final chrome = SwiftChromeColors.of(context);
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: dense ? 4 : 6,
          horizontal: dense ? 2 : 4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwiftCircleSelector(selected: selected, size: dense ? 18 : 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: dense ? 12 : 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: chrome.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
