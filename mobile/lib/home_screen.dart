import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'app_storage.dart';
import 'bol_document_number.dart';
import 'label_data.dart';
import 'logo_finder.dart';
import 'pdf/bol_label_pdf.dart';
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

final _bolGroups = <(String title, String hint, List<String> keys)>[
  (
    'Document',
    'Document number (SW-####) is assigned automatically from the shared company counter when you Generate',
    [
      BolFields.documentDate,
      BolFields.bookingRef,
      BolFields.probillNumber,
    ],
  ),
  (
    'Ship to (consignee)',
    'Delivery party',
    [
      BolFields.consigneeName,
      BolFields.consigneeAddress,
      BolFields.consigneeContactName,
      BolFields.consigneeContactNumber,
    ],
  ),
  (
    'Billing & freight',
    'Collect / prepaid',
    [BolFields.thirdPartyBilling, BolFields.freightCharges],
  ),
  (
    'Tracking & references',
    'PO, packing list, order, project',
    [
      LabelFields.poNum,
      BolFields.packingList,
      BolFields.orderNum,
      LabelFields.project,
      LabelFields.salesOrder,
      LabelFields.specialInstructions,
    ],
  ),
  (
    'Line 1',
    'First goods row',
    [
      BolFields.lineKey(1, 'pieces'),
      BolFields.lineKey(1, 'item_type'),
      BolFields.lineKey(1, 'dimensions'),
      BolFields.lineKey(1, 'description'),
      BolFields.lineKey(1, 'weight'),
    ],
  ),
  (
    'Line 2',
    'Second goods row',
    [
      BolFields.lineKey(2, 'pieces'),
      BolFields.lineKey(2, 'item_type'),
      BolFields.lineKey(2, 'dimensions'),
      BolFields.lineKey(2, 'description'),
      BolFields.lineKey(2, 'weight'),
    ],
  ),
  (
    'Line 3',
    'Third goods row (optional)',
    [
      BolFields.lineKey(3, 'pieces'),
      BolFields.lineKey(3, 'item_type'),
      BolFields.lineKey(3, 'description'),
      BolFields.lineKey(3, 'weight'),
    ],
  ),
  (
    'Signatures',
    'Shipper / driver / consignee',
    [
      BolFields.shipperCertName,
      BolFields.shipperCertDate,
      BolFields.driverPrint,
      BolFields.driverDate,
      BolFields.vehicleId,
      BolFields.consigneePrint,
      BolFields.consigneeDate,
    ],
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
  /// Selected customer logo paths (primary first, optional C/O second).
  final List<String> _logoPaths = [];
  bool _busy = false;
  bool _findingLogo = false;
  bool _showManualLogoUpload = false;
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
      _logoPaths.add(sample.path);
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
    return LabelFields.formDefs.firstWhere(
      (d) => d.$1 == key,
      orElse: () => (key, key, false),
    );
  }

  void _applyPreset(String name, {bool notify = true}) {
    final preset = widget.storage.presets[name];
    if (preset == null) return;
    for (final key in LabelFields.presetKeys) {
      if (preset.fields.containsKey(key)) {
        _setField(key, preset.fields[key] ?? '');
      }
    }
    _logoPaths
      ..clear()
      ..addAll(
        preset.logoFileNames
            .map((n) => p.join(widget.storage.logosDir.path, n))
            .where((path) => File(path).existsSync())
            .take(maxCustomerLogos),
      );
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

    final logoNames = <String>[];
    for (final logoPath in _logoPaths.take(maxCustomerLogos)) {
      final lp = File(logoPath);
      if (!await lp.exists()) continue;
      if (p.dirname(lp.path) == widget.storage.logosDir.path) {
        logoNames.add(p.basename(lp.path));
      } else {
        final imported = await widget.storage.importLogo(lp);
        logoNames.add(p.basename(imported.path));
      }
    }

    widget.storage.presets[name.trim()] = CustomerPreset(
      name: name.trim(),
      fields: fields,
      logoFileNames: logoNames,
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

    final importedPaths = <String>[];
    for (final path in paths) {
      final imported = await widget.storage.importLogo(File(path));
      importedPaths.add(imported.path);
      if (createPresets) {
        final name = widget.storage.safeCustomerName(
          p.basenameWithoutExtension(imported.path),
        );
        widget.storage.presets.putIfAbsent(
          name,
          () => CustomerPreset(
            name: name,
            logoFileNames: [p.basename(imported.path)],
            fields: {LabelFields.customer: name.toUpperCase()},
          ),
        );
      }
    }
    await widget.storage.savePresets();
    setState(() {
      for (final path in importedPaths) {
        if (_logoPaths.length >= maxCustomerLogos) break;
        if (!_logoPaths.contains(path)) _logoPaths.add(path);
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${paths.length} logo(s).')),
      );
    }
  }

  Future<void> _addLogoSlot() async {
    if (_logoPaths.length >= maxCustomerLogos) return;
    final paths = await _pickImages(multiple: false);
    if (paths.isEmpty) return;
    final imported = await widget.storage.importLogo(File(paths.first));
    setState(() {
      if (_logoPaths.length < maxCustomerLogos &&
          !_logoPaths.contains(imported.path)) {
        _logoPaths.add(imported.path);
      }
    });
  }

  Future<void> _findLogoOnWeb() async {
    if (_findingLogo) return;
    if (_logoPaths.length >= maxCustomerLogos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Already have 2 logos. Remove one to find another.'),
        ),
      );
      return;
    }

    final nameCtrl = TextEditingController(
      text: _controllers[LabelFields.customer]?.text.trim() ?? '',
    );
    final domainCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Find logo on the web'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'We’ll look up a high-quality brand mark (Clearbit, Wikipedia, etc.). '
              'A website domain helps a lot.',
              style: TextStyle(fontSize: 13, color: SwiftColors.muted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'CUSTOMER / COMPANY'),
              autofocus: true,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: domainCtrl,
              decoration: const InputDecoration(
                labelText: 'WEBSITE DOMAIN (OPTIONAL)',
                hintText: 'e.g. conocophillips.com',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Search'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _findingLogo = true);
    try {
      final finder = LogoFinder();
      final result = await finder.find(
        companyName: nameCtrl.text,
        domain: domainCtrl.text,
      );
      if (!mounted) return;
      if (!result.ok || result.bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.error ??
                  'No logo found. Use Upload manually below.',
            ),
          ),
        );
        setState(() => _showManualLogoUpload = true);
        return;
      }

      final base = widget.storage.safeCustomerName(
        nameCtrl.text.trim().isEmpty ? 'logo' : nameCtrl.text.trim(),
      );
      final ext = LogoFinder.extensionForBytes(result.bytes!);
      final file = await widget.storage.importLogoBytes(
        result.bytes!,
        preferredName: '$base$ext',
      );
      if (!mounted) return;
      setState(() {
        if (_logoPaths.length < maxCustomerLogos &&
            !_logoPaths.contains(file.path)) {
          _logoPaths.add(file.path);
        }
      });
      final hint = result.hint.isEmpty ? '' : '\n${result.hint}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logo from ${result.source}.$hint')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Web find failed: $e. Upload manually instead.'),
          ),
        );
        setState(() => _showManualLogoUpload = true);
      }
    } finally {
      if (mounted) setState(() => _findingLogo = false);
    }
  }

  void _removeLogoAt(int index) {
    if (index < 0 || index >= _logoPaths.length) return;
    setState(() => _logoPaths.removeAt(index));
  }

  Future<void> _replaceLogoAt(int index) async {
    final paths = await _pickImages(multiple: false);
    if (paths.isEmpty) return;
    final imported = await widget.storage.importLogo(File(paths.first));
    setState(() {
      if (index >= 0 && index < _logoPaths.length) {
        _logoPaths[index] = imported.path;
      }
    });
  }

  Future<List<Uint8List>> _loadSelectedLogoBytes() async {
    final out = <Uint8List>[];
    for (final path in _logoPaths.take(maxCustomerLogos)) {
      final f = File(path);
      if (await f.exists()) out.add(await f.readAsBytes());
    }
    return out;
  }

  Future<PieceCountPlan?> _askPieceCounts() async {
    final palletCtrl = TextEditingController(text: '1');
    final boxCtrl = TextEditingController(text: '0');
    var error = '';
    return showDialog<PieceCountPlan>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('How many labels?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter how many Pallet/Crate and Box labels to print. '
                'Each unit gets its own page (1 of N, 2 of N, …).',
                style: TextStyle(fontSize: 13, color: SwiftColors.muted),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: palletCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'PALLET / CRATE LABELS',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: boxCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'BOX LABELS',
                ),
              ),
              if (error.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  error,
                  style: const TextStyle(color: SwiftColors.accent, fontSize: 13),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final pallets = int.tryParse(palletCtrl.text.trim()) ?? -1;
                final boxes = int.tryParse(boxCtrl.text.trim()) ?? -1;
                if (pallets < 0 || boxes < 0 || pallets + boxes <= 0) {
                  setLocal(
                    () => error = 'Enter at least one pallet/crate or box.',
                  );
                  return;
                }
                if (pallets + boxes > 200) {
                  setLocal(() => error = 'Keep total labels at 200 or fewer.');
                  return;
                }
                Navigator.pop(
                  ctx,
                  PieceCountPlan(palletCrates: pallets, boxes: boxes),
                );
              },
              child: const Text('Generate'),
            ),
          ],
        ),
      ),
    );
  }

  void _loadSample() {
    final s = switch (_kind) {
      LabelKind.receiving => ShippingLabelData.receivingSample,
      LabelKind.bol => ShippingLabelData.bolSample,
      LabelKind.shipping => ShippingLabelData.sample,
    };
    for (final e in s.values.entries) {
      _setField(e.key, e.value);
    }
    // Mirror ship-to into BOL consignee when loading BOL sample
    if (_kind == LabelKind.bol) {
      final name = _controllers[BolFields.consigneeName]?.text ?? '';
      if (name.isNotEmpty) _setField(LabelFields.shipTo, name);
    }
    setState(() {});
  }

  void _clearShipment() {
    final clear = switch (_kind) {
      LabelKind.receiving => {
          LabelFields.poNum,
          LabelFields.project,
          LabelFields.salesOrder,
          LabelFields.pm,
          LabelFields.dateReceived,
          LabelFields.receivedBy,
          LabelFields.specialInstructions,
        },
      LabelKind.bol => {
          for (final d in BolFields.formDefs) d.$1,
          LabelFields.poNum,
          LabelFields.project,
          LabelFields.salesOrder,
          LabelFields.specialInstructions,
        },
      LabelKind.shipping => {
          LabelFields.poNum,
          LabelFields.project,
          LabelFields.packingSlip,
          LabelFields.salesOrder,
          LabelFields.palletNum,
          LabelFields.palletOf,
          LabelFields.boxNum,
          LabelFields.boxOf,
          LabelFields.specialInstructions,
        },
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

    PieceCountPlan? piecePlan;
    if (_kind == LabelKind.shipping) {
      piecePlan = await _askPieceCounts();
      if (piecePlan == null || piecePlan.isEmpty) return;
    }

    setState(() => _busy = true);
    try {
      final logoBytes = await _loadSelectedLogoBytes();
      final data = _collect();
      // Keep BOL consignee in sync with shared ship-to when empty
      if (_kind == LabelKind.bol) {
        if (data.get(BolFields.consigneeName).isEmpty) {
          data.set(BolFields.consigneeName, data.get(LabelFields.shipTo));
        }
        if (data.get(BolFields.consigneeAddress).isEmpty) {
          data.set(BolFields.consigneeAddress, data.get(LabelFields.location));
        }
        if (data.get(BolFields.orderNum).isEmpty) {
          data.set(BolFields.orderNum, data.get(LabelFields.salesOrder));
        }
        if (data.get(BolFields.packingList).isEmpty) {
          data.set(BolFields.packingList, data.get(LabelFields.packingSlip));
        }
        // Shared cloud serial — every Windows/Android generate bumps SW-####.
        final docNo = await BolDocumentNumber.allocate(
          source: 'swift_document_generator',
          note: data.get(BolFields.consigneeName).isEmpty
              ? data.get(LabelFields.customer)
              : data.get(BolFields.consigneeName),
        );
        data.set(BolFields.documentNumber, docNo);
        _setField(BolFields.documentNumber, docNo);
        if (data.get(BolFields.documentDate).isEmpty) {
          final today = BolDocumentNumber.todayStamp();
          data.set(BolFields.documentDate, today);
          _setField(BolFields.documentDate, today);
        }
      }

      final Uint8List bytes;
      switch (_kind) {
        case LabelKind.receiving:
          bytes = await widget.pdf.buildReceiving(
            data: data,
            customerLogoBytes: logoBytes,
          );
        case LabelKind.bol:
          bytes = await BolLabelPdf(widget.pdf).build(
            data: data,
            customerLogoBytes: logoBytes,
          );
        case LabelKind.shipping:
          bytes = await widget.pdf.build(
            data: data,
            customerLogoBytes: logoBytes,
            piecePlan: piecePlan!,
          );
      }

      final so = data.get(LabelFields.salesOrder).isNotEmpty
          ? data.get(LabelFields.salesOrder)
          : data.get(BolFields.orderNum);
      final name = widget.storage.labelPdfBaseName(
        kind: _kind,
        customer: data.get(LabelFields.customer).isNotEmpty
            ? data.get(LabelFields.customer)
            : data.get(BolFields.consigneeName),
        salesOrder: so,
      );

      final file = await widget.storage.writePdf(name, bytes);

      await shareOrOpenFile(file: file);

      if (mounted) {
        final pages = switch (_kind) {
          LabelKind.shipping => ' (${piecePlan!.totalPages} pages)',
          LabelKind.bol =>
            ' (3 copies · ${data.get(BolFields.documentNumber)})',
          LabelKind.receiving => '',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved$pages:\n${file.path}')),
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
    final groups = switch (_kind) {
      LabelKind.receiving => _receivingGroups,
      LabelKind.bol => _bolGroups,
      LabelKind.shipping => _shippingGroups,
    };

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
                      label: Text('Shipping'),
                      icon: Icon(Icons.local_shipping_outlined, size: 18),
                    ),
                    ButtonSegment(
                      value: LabelKind.receiving,
                      label: Text('Receiving'),
                      icon: Icon(Icons.inventory_2_outlined, size: 18),
                    ),
                    ButtonSegment(
                      value: LabelKind.bol,
                      label: Text('Bill of Lading'),
                      icon: Icon(Icons.description_outlined, size: 18),
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
                        fontSize: 12,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  switch (_kind) {
                    LabelKind.receiving =>
                      'Pre-fill the receiving / staging label → Generate PDF. Special Instructions stay two lines.',
                    LabelKind.bol =>
                      'Straight Bill of Lading (3 copies). Document number SW-#### is assigned from the shared company counter on Generate (needs network).',
                    LabelKind.shipping =>
                      'Pre-fill the label → Generate PDF. You’ll be asked how many pallet/crate and box labels to print.',
                  },
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
                  hint:
                      'Up to $maxCustomerLogos per label — second logo is C/O',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < _logoPaths.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: SwiftColors.bg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: SwiftColors.border),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      i == 0 ? 'CUSTOMER' : 'C/O',
                                      style: const TextStyle(
                                        fontFamily: 'Oswald',
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: SwiftColors.muted,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    if (File(_logoPaths[i]).existsSync())
                                      Image.file(
                                        File(_logoPaths[i]),
                                        height: 44,
                                        cacheWidth: 220,
                                        filterQuality: FilterQuality.medium,
                                        gaplessPlayback: true,
                                        fit: BoxFit.contain,
                                      )
                                    else
                                      Text(
                                        p.basename(_logoPaths[i]),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Replace',
                                onPressed: () => _replaceLogoAt(i),
                                icon: const Icon(Icons.swap_horiz, size: 20),
                              ),
                              IconButton(
                                tooltip: 'Remove',
                                onPressed: () => _removeLogoAt(i),
                                icon: const Icon(Icons.close, size: 20),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_logoPaths.isNotEmpty) const SizedBox(height: 12),
                      // Two clear choices (tagger-style): web find vs manual upload
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: (_findingLogo ||
                                      _logoPaths.length >= maxCustomerLogos)
                                  ? null
                                  : _findLogoOnWeb,
                              icon: _findingLogo
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.travel_explore, size: 18),
                              label: Text(
                                _findingLogo
                                    ? 'Searching…'
                                    : 'Find logo on the web',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _logoPaths.length >= maxCustomerLogos
                                  ? null
                                  : () => setState(
                                        () => _showManualLogoUpload =
                                            !_showManualLogoUpload,
                                      ),
                              icon: const Icon(Icons.upload_file, size: 18),
                              label: Text(
                                _showManualLogoUpload
                                    ? 'Hide upload'
                                    : 'Upload manually',
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_showManualLogoUpload) ...[
                        const SizedBox(height: 12),
                        if (_logoPaths.length < maxCustomerLogos &&
                            logos.isNotEmpty)
                          DropdownButtonFormField<String>(
                            key: ValueKey(
                              'logo-pick-${_logoPaths.length}-${logos.length}',
                            ),
                            initialValue: null,
                            decoration: InputDecoration(
                              labelText: _logoPaths.isEmpty
                                  ? 'ADD FROM STORAGE'
                                  : 'ADD C/O FROM STORAGE',
                            ),
                            items: [
                              for (final f in logos)
                                if (!_logoPaths.contains(f.path))
                                  DropdownMenuItem(
                                    value: f.path,
                                    child: Text(p.basename(f.path)),
                                  ),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() {
                                if (_logoPaths.length < maxCustomerLogos &&
                                    !_logoPaths.contains(v)) {
                                  _logoPaths.add(v);
                                }
                              });
                            },
                          ),
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
                                onPressed:
                                    _logoPaths.length >= maxCustomerLogos
                                        ? null
                                        : _addLogoSlot,
                                child: Text(
                                  _logoPaths.isEmpty ? 'Browse…' : 'Add C/O…',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                for (final group in groups)
                  _Card(
                    title: group.$1,
                    hint: group.$2,
                    child: Column(
                      children: [
                        for (final key in group.$3) ...[
                          Builder(
                            builder: (_) {
                              final m = _meta(key);
                              final lines = !m.$3
                                  ? 1
                                  : (key == LabelFields.specialInstructions &&
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
                      'Document Generator',
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
