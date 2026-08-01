import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'app_storage.dart';
import 'label_data.dart';
import 'pdf/shipping_label_pdf.dart';
import 'platform_io.dart';
import 'theme.dart';
import 'update_sheet.dart';

const _shippingGroups = <(String title, String hint, List<String> keys)>[
  (
    'Customer & job',
    'Who the shipment is for',
    [
      LabelFields.customer,
      LabelFields.poNum,
      LabelFields.project,
      LabelFields.specialInstructions,
    ],
  ),
  (
    'Ship to',
    'Destination the warehouse reads first',
    [LabelFields.shipTo, LabelFields.location, LabelFields.attn],
  ),
  (
    'Swift references',
    'Internal tracking',
    [
      LabelFields.carrier,
      LabelFields.packingSlip,
      LabelFields.salesOrder,
      LabelFields.swiftContact,
    ],
  ),
  (
    'Piece count',
    'Match the BOL',
    [
      LabelFields.palletNum,
      LabelFields.palletOf,
      LabelFields.boxNum,
      LabelFields.boxOf,
    ],
  ),
];

const _receivingGroups = <(String title, String hint, List<String> keys)>[
  (
    'Customer & job',
    'Who the staged material is for',
    [
      LabelFields.customer,
      LabelFields.project,
      LabelFields.poNum,
      LabelFields.specialInstructions,
    ],
  ),
  (
    'Order & PM',
    'Swift sales order and project manager',
    [LabelFields.salesOrder, LabelFields.pm],
  ),
  (
    'Received',
    'Dock stamp — date and who signed',
    [LabelFields.dateReceived, LabelFields.receivedBy],
  ),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.storage, required this.pdf});

  final AppStorage storage;
  final ShippingLabelPdf pdf;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Map<String, TextEditingController> _controllers;
  String? _presetName;
  String? _activeLogoPath;
  String? _pickedLogoName;
  bool _busy = false;
  LabelKind _kind = LabelKind.shipping;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final def in LabelFields.formDefs)
        def.$1: TextEditingController(),
    };
    final logos = widget.storage.listLogos();
    if (logos.isNotEmpty) {
      final sample = logos.firstWhere(
        (f) => p.basename(f.path).contains('Pacific'),
        orElse: () => logos.first,
      );
      _activeLogoPath = sample.path;
      _pickedLogoName = p.basename(sample.path);
    }
    if (widget.storage.presets.containsKey('Pacific Canbriam')) {
      _presetName = 'Pacific Canbriam';
      _applyPreset('Pacific Canbriam', notify: false);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  ShippingLabelData _collect() {
    final data = ShippingLabelData();
    for (final e in _controllers.entries) {
      data.set(e.key, e.value.text);
    }
    return data;
  }

  void _setField(String key, String value) {
    _controllers[key]?.text = value;
  }

  (String, String, bool) _meta(String key) {
    return LabelFields.formDefs.firstWhere((d) => d.$1 == key);
  }

  void _applyPreset(String name, {bool notify = true}) {
    final preset = widget.storage.presets[name];
    if (preset == null) return;
    for (final key in LabelFields.presetKeys) {
      if (preset.fields.containsKey(key)) {
        _setField(key, preset.fields[key] ?? '');
      }
    }
    if (preset.logoFileName.isNotEmpty) {
      final path = p.join(widget.storage.logosDir.path, preset.logoFileName);
      if (File(path).existsSync()) {
        _activeLogoPath = path;
        _pickedLogoName = preset.logoFileName;
      }
    }
    _presetName = name;
    if (notify) setState(() {});
  }

  Future<void> _savePreset() async {
    final defaultName = _controllers[LabelFields.customer]!.text.trim().isEmpty
        ? (_presetName ?? 'New customer')
        : _controllers[LabelFields.customer]!.text.trim();
    final name = await _askString('Save preset', 'Preset name', defaultName);
    if (name == null || name.trim().isEmpty) return;

    final fields = <String, String>{};
    for (final key in LabelFields.presetKeys) {
      fields[key] = _controllers[key]?.text.trim() ?? '';
    }

    var logoName = '';
    final logoPath = _activeLogoPath;
    if (logoPath != null && logoPath.isNotEmpty) {
      final lp = File(logoPath);
      if (await lp.exists()) {
        if (p.dirname(lp.path) == widget.storage.logosDir.path) {
          logoName = p.basename(lp.path);
        } else {
          final imported = await widget.storage.importLogo(lp);
          logoName = p.basename(imported.path);
          _activeLogoPath = imported.path;
          _pickedLogoName = logoName;
        }
      }
    }

    widget.storage.presets[name.trim()] = CustomerPreset(
      name: name.trim(),
      fields: fields,
      logoFileName: logoName,
    );
    await widget.storage.savePresets();
    setState(() => _presetName = name.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved preset “${name.trim()}”.')),
      );
    }
  }

  Future<void> _deletePreset() async {
    final name = _presetName;
    if (name == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete preset'),
        content: Text('Delete preset “$name”?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    widget.storage.presets.remove(name);
    await widget.storage.savePresets();
    setState(() => _presetName = null);
  }

  Future<String?> _askString(String title, String label, String initial) async {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(labelText: label.toUpperCase()),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<List<String>> _pickImages({required bool multiple}) =>
      pickImagePaths(multiple: multiple);

  Future<void> _importLogos() async {
    final paths = await _pickImages(multiple: true);
    if (paths.isEmpty) return;
    if (!mounted) return;

    final createPresets = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Create presets?'),
            content: Text(
              'Import ${paths.length} logo(s).\n\n'
              'Also create a customer preset from each file name?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Logos only'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Create presets'),
              ),
            ],
          ),
        ) ??
        false;

    if (!mounted) return;

    String? first;
    for (final path in paths) {
      final imported = await widget.storage.importLogo(File(path));
      first ??= imported.path;
      if (createPresets) {
        final name = widget.storage.safeCustomerName(
          p.basenameWithoutExtension(imported.path),
        );
        widget.storage.presets.putIfAbsent(
          name,
          () => CustomerPreset(
            name: name,
            logoFileName: p.basename(imported.path),
            fields: {LabelFields.customer: name.toUpperCase()},
          ),
        );
      }
    }
    await widget.storage.savePresets();
    setState(() {
      if (first != null) {
        _activeLogoPath = first;
        _pickedLogoName = p.basename(first);
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${paths.length} logo(s).')),
      );
    }
  }

  Future<void> _pickActiveLogo() async {
    final paths = await _pickImages(multiple: false);
    if (paths.isEmpty) return;
    final imported = await widget.storage.importLogo(File(paths.first));
    setState(() {
      _activeLogoPath = imported.path;
      _pickedLogoName = p.basename(imported.path);
    });
  }

  void _loadSample() {
    final s = _kind == LabelKind.receiving
        ? ShippingLabelData.receivingSample
        : ShippingLabelData.sample;
    for (final e in s.values.entries) {
      _setField(e.key, e.value);
    }
    setState(() {});
  }

  void _clearShipment() {
    final clear = _kind == LabelKind.receiving
        ? {
            LabelFields.poNum,
            LabelFields.project,
            LabelFields.salesOrder,
            LabelFields.pm,
            LabelFields.dateReceived,
            LabelFields.receivedBy,
            LabelFields.specialInstructions,
          }
        : {
            LabelFields.poNum,
            LabelFields.project,
            LabelFields.packingSlip,
            LabelFields.salesOrder,
            LabelFields.palletNum,
            LabelFields.palletOf,
            LabelFields.boxNum,
            LabelFields.boxOf,
            LabelFields.specialInstructions,
          };
    for (final key in clear) {
      _controllers[key]?.clear();
    }
    setState(() {});
  }

  void _clearAll() {
    for (final c in _controllers.values) {
      c.clear();
    }
    setState(() {});
  }

  Future<void> _generateAndShare() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      Uint8List? logoBytes;
      final logoPath = _activeLogoPath;
      if (logoPath != null && File(logoPath).existsSync()) {
        logoBytes = await File(logoPath).readAsBytes();
      }

      final data = _collect();
      final bytes = _kind == LabelKind.receiving
          ? await widget.pdf.buildReceiving(
              data: data,
              customerLogoBytes: logoBytes,
            )
          : await widget.pdf.build(
              data: data,
              customerLogoBytes: logoBytes,
            );

      final customer = data.get(LabelFields.customer);
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('.', '')
          .substring(0, 15);
      final kindLabel =
          _kind == LabelKind.receiving ? 'Receiving Label' : 'Shipping Label';
      final name = customer.isEmpty
          ? 'Swift Supply $kindLabel $stamp.pdf'
          : 'Swift Supply $kindLabel - ${widget.storage.safeCustomerName(customer)} $stamp.pdf';

      final file = await widget.storage.writePdf(name, bytes);

      await shareOrOpenFile(file: file);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved:\n${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final logos = widget.storage.listLogos();
    final presetNames = widget.storage.presets.keys.toList()..sort();
    final groups =
        _kind == LabelKind.receiving ? _receivingGroups : _shippingGroups;

    return Scaffold(
      body: Column(
        children: [
          RepaintBoundary(child: _Header(busy: _busy)),
          Expanded(
            child: ListView(
              cacheExtent: 500,
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                SegmentedButton<LabelKind>(
                  segments: const [
                    ButtonSegment(
                      value: LabelKind.shipping,
                      label: Text('Shipping Label'),
                      icon: Icon(Icons.local_shipping_outlined, size: 18),
                    ),
                    ButtonSegment(
                      value: LabelKind.receiving,
                      label: Text('Receiving Label'),
                      icon: Icon(Icons.inventory_2_outlined, size: 18),
                    ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) {
                    setState(() => _kind = s.first);
                  },
                  style: ButtonStyle(
                    textStyle: WidgetStatePropertyAll(
                      TextStyle(
                        fontFamily: 'Oswald',
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _kind == LabelKind.receiving
                      ? 'Pre-fill the receiving / staging label → Generate PDF. Special Instructions stay two lines.'
                      : 'Pre-fill the label → Generate PDF. Long PO / Project lines wrap and shrink Special Instructions for print.',
                  style: TextStyle(
                    color: SwiftColors.muted,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                _Card(
                  title: 'Customer preset',
                  hint: 'Reuse customer defaults; shipment fields stay per job',
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        key: ValueKey('preset-$_presetName-${presetNames.length}'),
                        initialValue: presetNames.contains(_presetName)
                            ? _presetName
                            : null,
                        decoration: const InputDecoration(labelText: 'PRESET'),
                        items: [
                          for (final n in presetNames)
                            DropdownMenuItem(value: n, child: Text(n)),
                        ],
                        onChanged: (v) {
                          if (v != null) _applyPreset(v);
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _savePreset,
                              child: const Text('Save'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed:
                                  _presetName == null ? null : _deletePreset,
                              child: const Text('Delete'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _Card(
                  title: 'Customer logos',
                  hint: 'Import once, pick per job',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        key: ValueKey('logo-$_pickedLogoName-${logos.length}'),
                        initialValue: logos.any(
                              (f) => p.basename(f.path) == _pickedLogoName,
                            )
                            ? _pickedLogoName
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'LOGOS IN APP STORAGE',
                        ),
                        items: [
                          for (final f in logos)
                            DropdownMenuItem(
                              value: p.basename(f.path),
                              child: Text(p.basename(f.path)),
                            ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _pickedLogoName = v;
                            _activeLogoPath =
                                p.join(widget.storage.logosDir.path, v);
                          });
                        },
                      ),
                      if (_activeLogoPath != null &&
                          File(_activeLogoPath!).existsSync()) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: SwiftColors.bg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: SwiftColors.border),
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Image.file(
                              File(_activeLogoPath!),
                              height: 52,
                              cacheWidth: 240,
                              filterQuality: FilterQuality.medium,
                              gaplessPlayback: true,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _importLogos,
                              child: const Text('Import…'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _pickActiveLogo,
                              child: const Text('Browse…'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                for (final group in groups)
                  _Card(
                    title: group.$1,
                    hint: group.$2,
                    child: group.$1 == 'Piece count'
                        ? _PieceGrid(
                            keys: group.$3,
                            controllers: _controllers,
                            meta: _meta,
                          )
                        : Column(
                            children: [
                              for (final key in group.$3) ...[
                                Builder(
                                  builder: (_) {
                                    final m = _meta(key);
                                    final lines = !m.$3
                                        ? 1
                                        : (key ==
                                                    LabelFields
                                                        .specialInstructions &&
                                                _kind == LabelKind.receiving)
                                            ? 2
                                            : 3;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: TextField(
                                        controller: _controllers[key],
                                        maxLines: lines,
                                        decoration: InputDecoration(
                                          labelText: m.$2.toUpperCase(),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: _loadSample,
                      child: const Text('Load sample'),
                    ),
                    TextButton(
                      onPressed: _clearShipment,
                      child: const Text('Clear shipment'),
                    ),
                    TextButton(
                      onPressed: _clearAll,
                      child: const Text('Clear all'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          RepaintBoundary(
            child: _BottomBar(
              busy: _busy,
              onGenerate: _generateAndShare,
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.busy});

  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SwiftColors.accent,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 16),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SWIFT SUPPLY',
                      style: TextStyle(
                        fontFamily: 'Oswald',
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                        color: Colors.white,
                        letterSpacing: 0.8,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Shipping Label Generator',
                      style: TextStyle(
                        fontFamily: 'Calibri',
                        fontSize: 13,
                        color: Color(0xFFFFE8E0),
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                TextButton.icon(
                  onPressed: () => showUpdateFlow(context),
                  style: TextButton.styleFrom(
                    foregroundColor: SwiftColors.accent,
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.system_update_alt, size: 18),
                  label: const Text(
                    'Update',
                    style: TextStyle(
                      fontFamily: 'Oswald',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.busy, required this.onGenerate});

  final bool busy;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SwiftColors.surface,
      elevation: 8,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : onGenerate,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
              label: Text(busy ? 'Generating…' : 'Generate PDF'),
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.hint,
    required this.child,
  });

  final String title;
  final String hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Oswald',
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: SwiftColors.ink,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                hint,
                style: const TextStyle(
                  fontSize: 12,
                  color: SwiftColors.muted,
                ),
              ),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _PieceGrid extends StatelessWidget {
  const _PieceGrid({
    required this.keys,
    required this.controllers,
    required this.meta,
  });

  final List<String> keys;
  final Map<String, TextEditingController> controllers;
  final (String, String, bool) Function(String key) meta;

  @override
  Widget build(BuildContext context) {
    // Row layout (not GridView): wide Windows windows inflate GridView cell
    // height via childAspectRatio and leave huge gaps between piece fields.
    final rows = <List<String>>[];
    for (var i = 0; i < keys.length; i += 2) {
      rows.add(keys.sublist(i, i + 2 > keys.length ? keys.length : i + 2));
    }
    return Column(
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < rows[r].length; c++) ...[
                if (c > 0) const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controllers[rows[r][c]],
                    decoration: InputDecoration(
                      labelText: meta(rows[r][c]).$2.toUpperCase(),
                    ),
                  ),
                ),
              ],
              if (rows[r].length == 1) const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ],
      ],
    );
  }
}
