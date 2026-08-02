import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'app_storage.dart';
import 'bol_document_number.dart';
import 'bol_item_type.dart';
import 'preset_sync.dart';
import 'signature_pad.dart';
import 'signature_sync.dart';
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

const _bolMaxLines = 7;

const _bolGroupsBeforeLines = <(String title, String hint, List<String> keys)>[
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
    'Prepaid, collect, or third party',
    [BolFields.thirdPartyBilling],
  ),
  (
    'Tracking & references',
    'PO, packing list, sales order, project',
    [
      LabelFields.poNum,
      BolFields.packingList,
      LabelFields.salesOrder,
      LabelFields.project,
      LabelFields.specialInstructions,
    ],
  ),
];

const _bolSignaturesGroup = (
  'Signatures',
  'Shipper / driver / consignee',
  [
    BolFields.shipperCertName,
    BolFields.shipperCertDate,
    BolFields.driverCompany,
    BolFields.driverPrint,
    BolFields.driverDate,
    BolFields.departureTime,
    BolFields.vehicleId,
    BolFields.consigneePrint,
    BolFields.consigneeDate,
  ],
);

List<String> _bolLineFieldKeys(int lineNum) => [
      BolFields.lineKey(lineNum, 'pieces'),
      BolFields.lineKey(lineNum, 'item_type'),
      BolFields.lineKey(lineNum, 'dimensions'),
      BolFields.lineKey(lineNum, 'description'),
      BolFields.lineKey(lineNum, 'weight'),
    ];

String _bolLineHint(int lineNum) => switch (lineNum) {
      1 => 'First goods row',
      2 => 'Second goods row',
      _ => 'Additional goods row (optional)',
    };

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
  /// Which BOL copy pages to generate (all selected by default).
  bool _bolStoreCopy = true;
  bool _bolDriverCopy = true;
  bool _bolCustomerCopy = true;
  /// Visible BOL goods lines (1..7); start with line 1 only.
  int _bolLineCount = 1;
  late final PresetSync _presetSync;
  late final SignatureSync _signatureSync;
  Uint8List? _shipperSignatureBytes;
  SavedSignature? _selectedSavedSignature;

  @override
  void initState() {
    super.initState();
    _presetSync = PresetSync(widget.storage);
    _signatureSync = SignatureSync(widget.storage);
    _controllers = {
      for (final def in LabelFields.formDefs)
        def.$1: TextEditingController(),
      BolFields.freightCharges: TextEditingController(
        text: BolFields.freightPrepaid,
      ),
    };
    _syncPresetsOnLaunch();
  }

  Future<void> _syncPresetsOnLaunch() async {
    try {
      await _presetSync.syncOnLaunch();
      if (mounted) setState(() {});
    } on PresetSyncException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Preset sync: ${e.message}')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Preset sync failed — using local presets.'),
          ),
        );
      }
    }
    await _syncSignaturesQuietly();
  }

  Future<void> _syncSignaturesQuietly() async {
    try {
      await _signatureSync.syncOnLaunch();
      if (mounted) setState(() {});
    } on SignatureSyncException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Signature sync: ${e.message}')),
        );
      }
    } catch (_) {
      // Signatures are optional — ignore offline failures.
    }
  }

  Future<void> _pushPresetQuietly(LabelKind kind, String displayName) async {
    try {
      await _presetSync.pushPreset(kind, displayName);
    } on PresetSyncException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cloud sync: ${e.message}')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cloud sync failed — saved locally.')),
        );
      }
    }
  }

  Future<void> _deletePresetQuietly(LabelKind kind, String displayName) async {
    try {
      await _presetSync.deletePreset(kind, displayName);
    } on PresetSyncException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cloud sync: ${e.message}')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cloud sync failed — deleted locally only.'),
          ),
        );
      }
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
    if (key == BolFields.freightCharges) {
      _controllers[key]?.text = _normalizeFreightCharges(value);
      return;
    }
    _controllers[key]?.text = value;
  }

  String _normalizeFreightCharges(String raw) {
    final f = raw.toLowerCase().trim();
    if (f == BolFields.freightCollect) return BolFields.freightCollect;
    if (f == BolFields.freightThirdParty ||
        f == '3rd party' ||
        f == 'third party') {
      return BolFields.freightThirdParty;
    }
    if (f == BolFields.freightPrepaid) return BolFields.freightPrepaid;
    return '';
  }

  Set<String> _selectedFreightCharges() {
    final v = _normalizeFreightCharges(
      _controllers[BolFields.freightCharges]?.text ?? '',
    );
    return v.isEmpty ? {} : {v};
  }

  int _detectBolLineCount() {
    var maxLine = 1;
    for (var i = 1; i <= _bolMaxLines; i++) {
      final hasData = _bolLineFieldKeys(i).any(
        (key) => (_controllers[key]?.text.trim() ?? '').isNotEmpty,
      );
      if (hasData) maxLine = i;
    }
    return maxLine;
  }

  void _clearBolLineFields(int lineNum) {
    for (final key in _bolLineFieldKeys(lineNum)) {
      _controllers[key]?.clear();
    }
  }

  void _addBolLine() {
    if (_bolLineCount >= _bolMaxLines) return;
    setState(() => _bolLineCount++);
  }

  void _removeBolLine(int lineNum) {
    if (lineNum <= 1 || lineNum > _bolLineCount) return;
    for (var from = lineNum + 1; from <= _bolLineCount; from++) {
      final to = from - 1;
      for (final suffix
          in ['pieces', 'item_type', 'dimensions', 'description', 'weight']) {
        _setField(
          BolFields.lineKey(to, suffix),
          _controllers[BolFields.lineKey(from, suffix)]?.text ?? '',
        );
      }
    }
    _clearBolLineFields(_bolLineCount);
    setState(() => _bolLineCount--);
  }

  (String, String, bool) _meta(String key) {
    return LabelFields.formDefs.firstWhere(
      (d) => d.$1 == key,
      orElse: () => (key, key, false),
    );
  }

  String _presetStorageKey(String displayName) =>
      AppStorage.presetStorageKey(_kind, displayName);

  void _applyPreset(String displayName, {bool notify = true}) {
    final preset = widget.storage.presetFor(_kind, displayName);
    if (preset == null) return;
    for (final key in presetKeysFor(_kind)) {
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
    _presetName = displayName;
    if (notify) setState(() {});
  }

  Future<void> _savePreset() async {
    final defaultName = _controllers[LabelFields.customer]!.text.trim().isEmpty
        ? (_presetName ?? 'New customer')
        : _controllers[LabelFields.customer]!.text.trim();
    final name = await _askString('Save preset', 'Preset name', defaultName);
    if (name == null || name.trim().isEmpty) return;

    final fields = <String, String>{};
    for (final key in presetKeysFor(_kind)) {
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

    final displayName = name.trim();
    widget.storage.presets[_presetStorageKey(displayName)] = CustomerPreset(
      name: displayName,
      kind: _kind,
      fields: fields,
      logoFileNames: logoNames,
    );
    await widget.storage.savePresets();
    setState(() => _presetName = displayName);
    await _pushPresetQuietly(_kind, displayName);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved preset “$displayName”.')),
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
    widget.storage.presets.remove(_presetStorageKey(name));
    await widget.storage.savePresets();
    setState(() => _presetName = null);
    await _deletePresetQuietly(_kind, name);
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
        final storageKey = AppStorage.presetStorageKey(_kind, name);
        widget.storage.presets.putIfAbsent(
          storageKey,
          () => CustomerPreset(
            name: name,
            kind: _kind,
            logoFileNames: [p.basename(imported.path)],
            fields: {LabelFields.customer: name.toUpperCase()},
          ),
        );
      }
    }
    await widget.storage.savePresets();
    if (createPresets) {
      for (final path in importedPaths) {
        final name = widget.storage.safeCustomerName(
          p.basenameWithoutExtension(path),
        );
        await _pushPresetQuietly(_kind, name);
      }
    }
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
    final retoolConfigured = LogoSearchEngine.retoolClearbitConfigured();
    final engineOptions =
        LogoSearchEngine.pickerOptions(retoolConfigured: retoolConfigured);
    final savedEngineId = await widget.storage.loadLogoSearchEngine();
    var selectedEngine =
        LogoSearchEngine.tryParse(savedEngineId) ?? LogoSearchEngine.defaultEngine;
    if (!engineOptions.contains(selectedEngine)) {
      selectedEngine = LogoSearchEngine.defaultEngine;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Find logo on the web'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Search Google, Bing, Clearbit, Brands of the World, and other '
                'sources. A website domain improves accuracy.',
                style: TextStyle(fontSize: 13, color: SwiftColors.muted),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'CUSTOMER / COMPANY',
                ),
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
              const SizedBox(height: 14),
              DropdownButtonFormField<LogoSearchEngine>(
                value: selectedEngine,
                decoration: const InputDecoration(
                  labelText: 'SEARCH SOURCE',
                ),
                items: [
                  for (final engine in engineOptions)
                    DropdownMenuItem(
                      value: engine,
                      child: Text(engine.label),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => selectedEngine = value);
                },
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
      ),
    );
    if (confirmed != true || !mounted) return;

    await widget.storage.saveLogoSearchEngine(selectedEngine.id);

    setState(() => _findingLogo = true);
    try {
      final finder = LogoFinder();
      final rawCandidates = await finder.findDownloadedCandidates(
        companyName: nameCtrl.text,
        domain: domainCtrl.text,
        engine: selectedEngine,
      );
      final candidates = LogoFinder.filterForPicker(rawCandidates);
      if (!mounted) return;
      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No logo found across Google, Bing, Brands of the World, and other sources. '
              'Try a website domain or upload manually.',
            ),
          ),
        );
        setState(() => _showManualLogoUpload = true);
        return;
      }

      LogoDownloadedCandidate chosen = candidates.first;
      if (candidates.length > 1) {
        final picked = await showDialog<LogoDownloadedCandidate>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Choose a logo'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Top ${candidates.length} result${candidates.length == 1 ? '' : 's'} — tap a thumbnail',
                    style: const TextStyle(fontSize: 13, color: SwiftColors.muted),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 440),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final c in candidates)
                            InkWell(
                              onTap: () => Navigator.pop(ctx, c),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 96,
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  border: Border.all(color: SwiftColors.muted),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Image.memory(
                                      c.bytes,
                                      height: 56,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(
                                        Icons.broken_image_outlined,
                                        size: 40,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      c.source,
                                      style: const TextStyle(fontSize: 10),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
        if (picked == null || !mounted) return;
        chosen = picked;
      }

      final base = widget.storage.safeCustomerName(
        nameCtrl.text.trim().isEmpty ? 'logo' : nameCtrl.text.trim(),
      );
      final ext = LogoFinder.extensionForBytes(chosen.bytes);
      final file = await widget.storage.importLogoBytes(
        chosen.bytes,
        preferredName: '$base$ext',
      );
      if (!mounted) return;
      setState(() {
        if (_logoPaths.length < maxCustomerLogos &&
            !_logoPaths.contains(file.path)) {
          _logoPaths.add(file.path);
        }
      });
      final hint = chosen.hint.isEmpty ? '' : '\n${chosen.hint}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logo from ${chosen.source}.$hint')),
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
      _bolLineCount = _detectBolLineCount();
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
          BolFields.freightCharges,
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
    if (_kind == LabelKind.bol) {
      _bolLineCount = 1;
    }
    setState(() {});
  }

  void _clearAll() {
    for (final c in _controllers.values) {
      c.clear();
    }
    _bolLineCount = 1;
    setState(() {});
  }

  Future<void> _generateAndShare() async {
    if (_busy) return;

    PieceCountPlan? piecePlan;
    if (_kind == LabelKind.shipping) {
      piecePlan = await _askPieceCounts();
      if (piecePlan == null || piecePlan.isEmpty) return;
    }

    final bolCopies = <String>[];
    if (_kind == LabelKind.bol) {
      if (_bolStoreCopy) bolCopies.add('STORE COPY');
      if (_bolDriverCopy) bolCopies.add('DRIVER COPY');
      if (_bolCustomerCopy) bolCopies.add('CUSTOMER COPY');
      if (bolCopies.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Select at least one BOL copy to generate.'),
          ),
        );
        return;
      }
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
        final soVal = data.get(LabelFields.salesOrder);
        if (soVal.isNotEmpty) {
          data.set(BolFields.orderNum, soVal);
        }
        if (data.get(BolFields.packingList).isEmpty) {
          data.set(BolFields.packingList, data.get(LabelFields.packingSlip));
        }
        if (data.get(BolFields.freightCharges).isEmpty) {
          data.set(BolFields.freightCharges, BolFields.freightPrepaid);
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
            shipperSignatureBytes: _shipperSignatureBytes,
            copies: bolCopies,
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
            ' (${bolCopies.length} ${bolCopies.length == 1 ? 'copy' : 'copies'} · ${data.get(BolFields.documentNumber)})',
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

  Future<void> _pickDate(String key) async {
    final current = AppDates.parse(_controllers[key]!.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      _setField(key, AppDates.format(picked));
      setState(() {});
    }
  }

  Widget _buildDateField(String key) {
    final m = _meta(key);
    final ctrl = _controllers[key]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TextField(
        controller: ctrl,
        readOnly: true,
        decoration: InputDecoration(
          labelText: m.$2.toUpperCase(),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ctrl.text.isNotEmpty)
                IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _setField(key, '');
                    setState(() {});
                  },
                ),
              IconButton(
                tooltip: 'Pick date',
                icon: const Icon(Icons.calendar_today, size: 20),
                onPressed: () => _pickDate(key),
              ),
            ],
          ),
        ),
        onTap: () => _pickDate(key),
      ),
    );
  }

  Widget _buildItemTypeField(String key) {
    final raw = _controllers[key]?.text ?? '';
    final normalized = BolItemTypes.normalizeStored(raw);
    if (normalized != raw && normalized.isNotEmpty) {
      _controllers[key]?.text = normalized;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DropdownButtonFormField<String>(
        value: BolItemTypes.options.contains(normalized) ? normalized : null,
        decoration: const InputDecoration(labelText: 'ITEM TYPE'),
        hint: const Text('Select type'),
        items: [
          for (final opt in BolItemTypes.options)
            DropdownMenuItem(value: opt, child: Text(opt)),
        ],
        onChanged: (v) {
          _setField(key, v ?? '');
          setState(() {});
        },
      ),
    );
  }

  Future<void> _captureShipperSignature() async {
    final padKey = GlobalKey<SignaturePadState>();
    Uint8List? captured;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final pad = padKey.currentState;
          final canUse = pad != null && !pad.isEmpty;

          return AlertDialog(
            title: const Text('Shipper signature'),
            content: SizedBox(
              width: 420,
              child: SignaturePad(
                key: padKey,
                onChanged: () => setDialogState(() {}),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  padKey.currentState?.clear();
                  setDialogState(() {});
                },
                child: const Text('Clear'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: canUse
                    ? () async {
                        final state = padKey.currentState;
                        if (state == null || state.isEmpty) return;
                        captured = await state.exportPng();
                        if (ctx.mounted && captured != null) {
                          Navigator.pop(ctx, true);
                        }
                      }
                    : null,
                child: const Text('Use'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || captured == null || !mounted) return;

    final png = captured!;

    setState(() {
      _shipperSignatureBytes = png;
      _selectedSavedSignature = null;
    });

    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save for future use?'),
        content: const Text(
          'Store this signature in the cloud so you can reuse it on later BOLs.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No, this BOL only'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, save'),
          ),
        ],
      ),
    );
    if (save != true || !mounted) return;

    final defaultName =
        _controllers[BolFields.shipperCertName]?.text.trim() ?? '';
    final name = await _askString(
      'Name signature',
      'Short name',
      defaultName.isEmpty ? 'My signature' : defaultName,
    );
    if (name == null || !mounted) return;

    try {
      final saved = await _signatureSync.saveSignature(
        name: name,
        pngBytes: png,
      );
      if (mounted) {
        setState(() => _selectedSavedSignature = saved);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved signature “${saved.name}”.')),
        );
      }
    } on SignatureSyncException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save signature: ${e.message}')),
        );
      }
    }
  }

  Future<void> _pickSavedSignature() async {
    final sigs = _signatureSync.localSignatures;
    if (sigs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No saved signatures yet.')),
        );
      }
      return;
    }
    final picked = await showDialog<SavedSignature>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Saved signatures'),
        children: [
          for (final sig in sigs)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, sig),
              child: Text(sig.name),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final bytes = await _signatureSync.loadBytes(picked);
    if (bytes == null || !mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load signature.')),
      );
      return;
    }
    setState(() {
      _shipperSignatureBytes = bytes;
      _selectedSavedSignature = picked;
    });
  }

  void _clearShipperSignature() {
    setState(() {
      _shipperSignatureBytes = null;
      _selectedSavedSignature = null;
    });
  }

  Widget _buildShipperSignatureRow() {
    final label = _selectedSavedSignature?.name ??
        (_shipperSignatureBytes != null ? 'Drawn signature' : null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'SHIPPER SIGNATURE (OPTIONAL)',
            style: TextStyle(
              fontFamily: 'Oswald',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: SwiftColors.muted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          if (_shipperSignatureBytes != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: SwiftColors.border),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              child: Image.memory(
                _shipperSignatureBytes!,
                height: 56,
                fit: BoxFit.contain,
              ),
            ),
            if (label != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(label, style: const TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _captureShipperSignature,
                icon: const Icon(Icons.gesture, size: 18),
                label: Text(
                  _shipperSignatureBytes == null ? 'Add signature' : 'Redraw',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickSavedSignature,
                icon: const Icon(Icons.bookmark_outline, size: 18),
                label: const Text('Pick saved'),
              ),
              if (_shipperSignatureBytes != null)
                TextButton(
                  onPressed: _clearShipperSignature,
                  child: const Text('Clear'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormField(String key) {
    if (key.endsWith('_item_type')) {
      return _buildItemTypeField(key);
    }
    if (appDateFieldKeys.contains(key)) {
      return _buildDateField(key);
    }
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
  }

  Widget _buildFreightChargesSelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'FREIGHT CHARGES',
            style: TextStyle(
              fontFamily: 'Oswald',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: SwiftColors.muted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            emptySelectionAllowed: true,
            segments: [
              for (final o in BolFields.freightChargeOptions)
                ButtonSegment<String>(
                  value: o.$1,
                  label: Text(o.$2),
                ),
            ],
            selected: _selectedFreightCharges(),
            onSelectionChanged: (selection) {
              _setField(
                BolFields.freightCharges,
                selection.isEmpty ? '' : selection.first,
              );
              setState(() {});
            },
            style: ButtonStyle(
              textStyle: WidgetStatePropertyAll(
                TextStyle(
                  fontFamily: 'Oswald',
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logos = widget.storage.listLogos();
    final presetNames = widget.storage.presetDisplayNamesFor(_kind);
    final groups = switch (_kind) {
      LabelKind.receiving => _receivingGroups,
      LabelKind.bol => _bolGroupsBeforeLines,
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
                    setState(() {
                      _kind = s.first;
                      _presetName = null;
                      if (_kind == LabelKind.bol) {
                        _bolLineCount = _detectBolLineCount();
                        _syncSignaturesQuietly();
                      } else {
                        _bolLineCount = 1;
                      }
                    });
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
                      'Straight Bill of Lading. Choose which copies to print below. Document number SW-#### is assigned from the shared company counter on Generate (needs network).',
                    LabelKind.shipping =>
                      'Pre-fill the label → Generate PDF. You’ll be asked how many pallet/crate and box labels to print.',
                  },
                  style: TextStyle(
                    color: SwiftColors.muted,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
                if (_kind == LabelKind.bol) ...[
                  const SizedBox(height: 10),
                  _Card(
                    title: 'Copies to generate',
                    hint: 'Only selected pages are included in the PDF',
                    child: Column(
                      children: [
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('Store Copy'),
                          value: _bolStoreCopy,
                          onChanged: (v) =>
                              setState(() => _bolStoreCopy = v ?? false),
                        ),
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('Driver Copy'),
                          value: _bolDriverCopy,
                          onChanged: (v) =>
                              setState(() => _bolDriverCopy = v ?? false),
                        ),
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('Customer Copy'),
                          value: _bolCustomerCopy,
                          onChanged: (v) =>
                              setState(() => _bolCustomerCopy = v ?? false),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _Card(
                  title: 'Customer preset',
                  hint:
                      'Shared across all devices — per document type; shipment fields stay per job',
                  child: Column(
                    children: [
                      DropdownButtonFormField<String?>(
                        key: ValueKey('preset-$_kind-${presetNames.length}'),
                        value: _presetName != null &&
                                presetNames.contains(_presetName)
                            ? _presetName
                            : null,
                        hint: const Text('Select preset'),
                        decoration: const InputDecoration(
                          labelText: 'PRESET',
                        ),
                        isExpanded: true,
                        items: [
                          for (final n in presetNames)
                            DropdownMenuItem<String?>(
                              value: n,
                              child: Text(n),
                            ),
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
                        for (final key in group.$3)
                          _buildFormField(key),
                        if (_kind == LabelKind.bol &&
                            group.$1 == 'Billing & freight')
                          _buildFreightChargesSelector(),
                      ],
                    ),
                  ),
                if (_kind == LabelKind.bol) ...[
                  for (var lineNum = 1; lineNum <= _bolLineCount; lineNum++)
                    _Card(
                      title: 'Line $lineNum',
                      hint: _bolLineHint(lineNum),
                      trailing: lineNum > 1
                          ? IconButton(
                              tooltip: 'Remove line',
                              onPressed: () => _removeBolLine(lineNum),
                              icon: const Icon(Icons.delete_outline, size: 20),
                            )
                          : null,
                      child: Column(
                        children: [
                          for (final key in _bolLineFieldKeys(lineNum))
                            _buildFormField(key),
                        ],
                      ),
                    ),
                  if (_bolLineCount < _bolMaxLines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton.filledTonal(
                          tooltip: 'Add line',
                          onPressed: _addBolLine,
                          icon: const Icon(Icons.add),
                        ),
                      ),
                    ),
                  _Card(
                    title: _bolSignaturesGroup.$1,
                    hint: _bolSignaturesGroup.$2,
                    child: Column(
                      children: [
                        _buildShipperSignatureRow(),
                        for (final key in _bolSignaturesGroup.$3)
                          _buildFormField(key),
                      ],
                    ),
                  ),
                ],
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
    this.trailing,
  });

  final String title;
  final String hint;
  final Widget child;
  final Widget? trailing;

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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
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
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
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
