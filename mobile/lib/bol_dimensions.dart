import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Length / width / height plus a unit, stored as one BOL line string.
class BolDimensionsValue {
  const BolDimensionsValue({
    this.length = '',
    this.width = '',
    this.height = '',
    this.unit = 'in',
  });

  final String length;
  final String width;
  final String height;
  final String unit;

  static const units = <String>['in', 'ft', 'cm', 'm', 'mm'];

  static const unitLabels = <String, String>{
    'in': 'Inches',
    'ft': 'Feet',
    'cm': 'Centimeters',
    'm': 'Meters',
    'mm': 'Millimeters',
  };

  bool get isEmpty =>
      length.trim().isEmpty && width.trim().isEmpty && height.trim().isEmpty;

  /// `48 × 40 × 48 in` — empty when no measurements were entered.
  String format() {
    if (isEmpty) return '';
    final l = length.trim().isEmpty ? '—' : length.trim();
    final w = width.trim().isEmpty ? '—' : width.trim();
    final h = height.trim().isEmpty ? '—' : height.trim();
    return '$l × $w × $h $unit';
  }

  static final _unitSuffix = RegExp(
    r'\s*(mm|cm|m|in|ft|inches?|feet|foot|meters?|'
    r'centimet(?:er|re)s?|millimet(?:er|re)s?)\s*$',
    caseSensitive: false,
  );

  static final _triple = RegExp(
    r'^\s*([0-9]*\.?[0-9]+)\s*[x×]\s*([0-9]*\.?[0-9]+)\s*[x×]\s*([0-9]*\.?[0-9]+)',
    caseSensitive: false,
  );

  static String normalizeUnit(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'inch':
      case 'inches':
      case 'in':
        return 'in';
      case 'foot':
      case 'feet':
      case 'ft':
        return 'ft';
      case 'centimeter':
      case 'centimeters':
      case 'centimetre':
      case 'centimetres':
      case 'cm':
        return 'cm';
      case 'meter':
      case 'meters':
      case 'metre':
      case 'metres':
      case 'm':
        return 'm';
      case 'millimeter':
      case 'millimeters':
      case 'millimetre':
      case 'millimetres':
      case 'mm':
        return 'mm';
      default:
        return 'in';
    }
  }

  static BolDimensionsValue parse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return const BolDimensionsValue();
    var body = s;
    var unit = 'in';
    final unitMatch = _unitSuffix.firstMatch(s);
    if (unitMatch != null) {
      unit = normalizeUnit(unitMatch.group(1)!);
      body = s.substring(0, unitMatch.start).trim();
    }
    final triple = _triple.firstMatch(body);
    if (triple != null) {
      return BolDimensionsValue(
        length: triple.group(1)!,
        width: triple.group(2)!,
        height: triple.group(3)!,
        unit: unit,
      );
    }
    return BolDimensionsValue(length: body, unit: unit);
  }
}

/// L / W / H boxes plus a unit dropdown, bound to the existing dimensions key.
class BolDimensionsFields extends StatefulWidget {
  const BolDimensionsFields({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<BolDimensionsFields> createState() => _BolDimensionsFieldsState();
}

class _BolDimensionsFieldsState extends State<BolDimensionsFields> {
  late final TextEditingController _length;
  late final TextEditingController _width;
  late final TextEditingController _height;
  late String _unit;
  var _writing = false;

  @override
  void initState() {
    super.initState();
    final parsed = BolDimensionsValue.parse(widget.controller.text);
    _length = TextEditingController(text: parsed.length);
    _width = TextEditingController(text: parsed.width);
    _height = TextEditingController(text: parsed.height);
    _unit = BolDimensionsValue.units.contains(parsed.unit) ? parsed.unit : 'in';
    widget.controller.addListener(_onParent);
    _length.addListener(_push);
    _width.addListener(_push);
    _height.addListener(_push);
  }

  @override
  void didUpdateWidget(covariant BolDimensionsFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onParent);
      widget.controller.addListener(_onParent);
      _pullFromParent();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onParent);
    _length
      ..removeListener(_push)
      ..dispose();
    _width
      ..removeListener(_push)
      ..dispose();
    _height
      ..removeListener(_push)
      ..dispose();
    super.dispose();
  }

  void _onParent() {
    if (_writing) return;
    _pullFromParent();
  }

  void _pullFromParent() {
    final parsed = BolDimensionsValue.parse(widget.controller.text);
    void sync(TextEditingController c, String v) {
      if (c.text == v) return;
      c.value = TextEditingValue(
        text: v,
        selection: TextSelection.collapsed(offset: v.length),
      );
    }

    sync(_length, parsed.length);
    sync(_width, parsed.width);
    sync(_height, parsed.height);
    final unit =
        BolDimensionsValue.units.contains(parsed.unit) ? parsed.unit : 'in';
    if (unit != _unit && mounted) setState(() => _unit = unit);
  }

  void _push() {
    final next = BolDimensionsValue(
      length: _length.text,
      width: _width.text,
      height: _height.text,
      unit: _unit,
    ).format();
    if (widget.controller.text == next) return;
    _writing = true;
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _writing = false;
  }

  InputDecoration _box(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'DIMENSIONS',
            style: TextStyle(
              fontFamily: 'Oswald',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: SwiftColors.muted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _length,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: _box('L'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _width,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: _box('W'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _height,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: _box('H'),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 118,
                child: DropdownButtonFormField<String>(
                  value: _unit,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'UNIT',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                  items: [
                    for (final u in BolDimensionsValue.units)
                      DropdownMenuItem(
                        value: u,
                        child: Text(
                          BolDimensionsValue.unitLabels[u] ?? u,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _unit = v);
                    _push();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
