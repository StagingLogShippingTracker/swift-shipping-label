import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'app_storage.dart';
import 'bol_document_number.dart';
import 'bol_item_type.dart';
import 'brand_assets.dart';
import 'preset_sync.dart';
import 'signature_pad.dart';
import 'signature_sync.dart';
import 'label_data.dart';
import 'logo_finder.dart';
import 'logo_import_options.dart';
import 'form_scroll_text_field.dart';
import 'pdf/bol_label_pdf.dart';
import 'pdf/shipping_label_pdf.dart';
import 'platform_io.dart';
import 'theme.dart';
import 'update_sheet.dart';
import 'windows_menu_bar.dart';
import 'feedback_forms.dart';
import 'app_theme_scope.dart';
import 'pdf_render_options.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _shippingGroups = <(String title, String hint, List<String> keys)>[
  (
    'Customer & job',
    'Who the shipment is for',
    [
      LabelFields.customer,
      LabelFields.poNum,
      LabelFields.project,
      LabelFields.attn,
      LabelFields.specialInstructions,
    ],
  ),
  (
    'Ship to',
    'Destination the warehouse reads first',
    [LabelFields.shipTo, LabelFields.location],
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

const _bolMaxLines = 10;

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
  /// When true, next logo import runs through the premium Recreate pipeline
  /// (Windows: Python → Fly → Rust; Android: Fly → Rust). Default false.
  bool _recreateLogo = false;
  bool _recreatingLogo = false;
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
  AppUiSettings _uiSettings = AppUiSettings.defaults;
  /// Portrait Android: full header + kind selector collapse while scrolling.
  bool _mobileChromeExpanded = true;

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
    _loadUiSettings();
    _syncPresetsOnLaunch();
  }

  Future<void> _loadUiSettings() async {
    try {
      final s = await widget.storage.loadUiSettings();
      if (!mounted) return;
      setState(() => _uiSettings = s);
      _syncAppTheme(s);
    } catch (_) {}
  }

  void _applyUiSettings(AppUiSettings s) {
    setState(() => _uiSettings = s);
    _syncAppTheme(s);
  }

  void _syncAppTheme(AppUiSettings s) {
    try {
      AppThemeScope.of(context).value = s;
    } catch (_) {}
  }

  Future<void> _openErrorCapture() async {
    PackageInfo? info;
    try {
      info = await PackageInfo.fromPlatform();
    } catch (_) {}
    if (!mounted) return;
    await openErrorCaptureForm(
      context,
      installedVersion: info == null
          ? 'unknown'
          : '${info.version}+${info.buildNumber}',
    );
  }

  Future<void> _toggleDarkMode() async {
    final next = _uiSettings.copyWith(
      themePreference: _uiSettings.isDark
          ? UiThemePreference.light
          : UiThemePreference.dark,
    );
    await widget.storage.saveUiSettings(next);
    _applyUiSettings(next);
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
    return {v.isEmpty ? BolFields.freightPrepaid : v};
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
        logoNames.add(p.basename(imported.file.path));
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
    try {
      return await showDialog<String>(
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
    } finally {
      ctrl.dispose();
    }
  }

  Future<List<String>> _pickImages({required bool multiple}) =>
      pickImagePaths(multiple: multiple);

  Future<void> _importBytesWithPrompt(
    Uint8List bytes, {
    required String preferredName,
    void Function(String path)? onImported,
  }) async {
    if (!mounted) return;
    final options = await showLogoImportEditDialog(
      context,
      previewBytes: bytes,
      recreate: _recreateLogo,
    );
    if (options == null || !mounted) return;

    final recreate = _recreateLogo;
    if (recreate) setState(() => _recreatingLogo = true);
    try {
      final result = await widget.storage.importLogoBytes(
        bytes,
        preferredName: preferredName,
        recreate: recreate,
        options: options,
        onLog: (line) => debugPrint('[recreate] $line'),
      );
      if (!mounted) return;
      final file = result.file;
      if (onImported != null) {
        onImported(file.path);
      } else {
        setState(() {
          if (_logoPaths.length < maxCustomerLogos &&
              !_logoPaths.contains(file.path)) {
            _logoPaths.add(file.path);
          }
        });
      }
      if (recreate && mounted) {
        if (result.recreateSucceeded == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recreate finished — logo cleaned.')),
          );
        } else {
          final detail = (result.recreateError ?? 'unknown error').trim();
          final short = detail.length > 140
              ? '${detail.substring(0, 140)}…'
              : detail;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Recreate failed — imported original instead. $short',
              ),
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
    } finally {
      if (recreate && mounted) setState(() => _recreatingLogo = false);
    }
  }

  Future<void> _browseAndImportLogo() async {
    if (_logoPaths.length >= maxCustomerLogos) return;
    final paths = await _pickImages(multiple: false);
    if (paths.isEmpty || !mounted) return;
    final source = File(paths.first);
    final bytes = await source.readAsBytes();
    await _importBytesWithPrompt(
      bytes,
      preferredName: p.basename(source.path),
    );
  }

  Future<void> _addFromStorageAndImport() async {
    if (!mounted) return;
    var logos = widget.storage.listLogos();
    if (logos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No logos in storage yet — use Browse.')),
      );
      return;
    }

    final atLogoLimit = _logoPaths.length >= maxCustomerLogos;
    final picked = await showDialog<File>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          logos = widget.storage.listLogos();
          return AlertDialog(
            title: const Text('Add from storage'),
            content: SizedBox(
              width: 420,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: logos.isEmpty
                    ? const Text('No logos in storage.')
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (atLogoLimit)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                'Logo slots full — delete below or remove a '
                                'selected logo to import another.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: SwiftColors.muted.withValues(alpha: 0.9),
                                ),
                              ),
                            ),
                          Flexible(
                            child: ListView(
                              shrinkWrap: true,
                              children: [
                                for (final f in logos)
                                  ListTile(
                                    leading: Image.file(
                                      f,
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.image_outlined),
                                    ),
                                    title: Text(p.basename(f.path)),
                                    subtitle: _logoPaths.contains(f.path)
                                        ? const Text(
                                            'Selected on this label',
                                            style: TextStyle(fontSize: 11),
                                          )
                                        : null,
                                    enabled: !atLogoLimit &&
                                        !_logoPaths.contains(f.path),
                                    onTap: !atLogoLimit &&
                                            !_logoPaths.contains(f.path)
                                        ? () => Navigator.pop(ctx, f)
                                        : null,
                                    trailing: IconButton(
                                      tooltip: 'Delete from storage',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () async {
                                        final name = p.basename(f.path);
                                        final ok = await showDialog<bool>(
                                          context: ctx,
                                          builder: (confirmCtx) => AlertDialog(
                                            title: const Text('Delete logo'),
                                            content: Text(
                                              'Delete “$name” from storage? '
                                              'Presets that used this logo will '
                                              'skip it on next load.',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(confirmCtx, false),
                                                child: const Text('Cancel'),
                                              ),
                                              FilledButton(
                                                onPressed: () =>
                                                    Navigator.pop(confirmCtx, true),
                                                child: const Text('Delete'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (ok != true || !ctx.mounted) return;
                                        final deleted =
                                            await widget.storage.deleteStoredLogo(f);
                                        if (!ctx.mounted) return;
                                        if (!deleted) {
                                          ScaffoldMessenger.of(ctx).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Could not delete “$name”.',
                                              ),
                                            ),
                                          );
                                          return;
                                        }
                                        setState(() {
                                          _logoPaths.remove(f.path);
                                        });
                                        setDialogState(() {});
                                        if (!ctx.mounted) return;
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          SnackBar(
                                            content: Text('Deleted “$name”.')),
                                        );
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
    if (picked == null || !mounted) return;

    // Attach an existing stored logo without re-importing a duplicate file.
    // When Recreate is on, re-run the edit/vectorize pipeline on a fresh copy.
    if (!_recreateLogo) {
      setState(() {
        if (_logoPaths.length < maxCustomerLogos &&
            !_logoPaths.contains(picked.path)) {
          _logoPaths.add(picked.path);
        }
      });
      return;
    }

    final bytes = await picked.readAsBytes();
    await _importBytesWithPrompt(
      bytes,
      preferredName: p.basename(picked.path),
    );
  }

  Future<void> _showUploadManuallyMenu() async {
    if (_recreatingLogo) return;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Upload manually'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'storage'),
            child: const ListTile(
              leading: Icon(Icons.folder_open),
              title: Text('Add from Storage'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'browse'),
            child: const ListTile(
              leading: Icon(Icons.folder_outlined),
              title: Text('Browse'),
            ),
          ),
        ],
      ),
    );
    if (action == 'storage') {
      await _addFromStorageAndImport();
    } else if (action == 'browse') {
      await _browseAndImportLogo();
    }
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
        builder: (ctx, setDialogState) {
          final media = MediaQuery.of(ctx);
          final viewInsets = media.viewInsets;
          final padding = media.padding;
          final screenHeight = media.size.height;
          const horizontalInset = 24.0;
          const verticalInset = 24.0;
          final topInset = padding.top + verticalInset;
          final bottomInset = viewInsets.bottom + verticalInset;
          final maxDialogHeight = (screenHeight - topInset - bottomInset)
              .clamp(200.0, screenHeight);
          final maxContentHeight = (maxDialogHeight - 140)
              .clamp(120.0, screenHeight * 0.55);
          return MediaQuery.removeViewInsets(
            removeBottom: true,
            context: ctx,
            child: AlertDialog(
              insetPadding: EdgeInsets.fromLTRB(
                horizontalInset,
                topInset,
                horizontalInset,
                bottomInset,
              ),
              title: const Text('Find logo on the web'),
              content: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxContentHeight),
                child: SingleChildScrollView(
                  child: Column(
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
                ),
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
        },
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
        setState(() => _findingLogo = false);
        return;
      }

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
                                    errorBuilder: (_, __, ___) => const Icon(
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
      final chosen = picked;

      final base = widget.storage.safeCustomerName(
        nameCtrl.text.trim().isEmpty ? 'logo' : nameCtrl.text.trim(),
      );
      final ext = LogoFinder.extensionForBytes(chosen.bytes);
      await _importBytesWithPrompt(
        chosen.bytes,
        preferredName: '$base$ext',
      );
      if (!mounted) return;
      final hint = chosen.hint.isEmpty ? '' : '\n${chosen.hint}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logo from ${chosen.source}.$hint')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Web find failed: $e. Try Upload manually.'),
          ),
        );
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
    final source = File(paths.first);
    final bytes = await source.readAsBytes();
    await _importBytesWithPrompt(
      bytes,
      preferredName: p.basename(source.path),
      onImported: (path) {
        setState(() {
          if (index >= 0 && index < _logoPaths.length) {
            _logoPaths[index] = path;
          }
        });
      },
    );
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
      _setField(BolFields.freightCharges, BolFields.freightPrepaid);
    }
    setState(() {});
  }

  void _clearAll() {
    for (final c in _controllers.values) {
      c.clear();
    }
    _bolLineCount = 1;
    _setField(BolFields.freightCharges, BolFields.freightPrepaid);
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
            options: _uiSettings.pdfOptions,
          );
        case LabelKind.bol:
          bytes = await BolLabelPdf(widget.pdf).build(
            data: data,
            customerLogoBytes: logoBytes,
            shipperSignatureBytes: _shipperSignatureBytes,
            copies: bolCopies,
            options: _uiSettings.pdfOptions,
          );
        case LabelKind.shipping:
          bytes = await widget.pdf.build(
            data: data,
            customerLogoBytes: logoBytes,
            piecePlan: piecePlan!,
            options: _uiSettings.pdfOptions,
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

      final file = await widget.storage.writePdf(
        name,
        bytes,
        outputDir: widget.storage.pdfOutputDir(_uiSettings),
      );

      if (_uiSettings.autoOpenPdf) {
        await shareOrOpenFile(file: file);
      }

      if (mounted) {
        final pages = switch (_kind) {
          LabelKind.shipping => ' (${piecePlan!.totalPages} pages)',
          LabelKind.bol =>
            ' (${bolCopies.length} ${bolCopies.length == 1 ? 'copy' : 'copies'} · ${data.get(BolFields.documentNumber)})',
          LabelKind.receiving => '',
        };
        final openHint = _uiSettings.autoOpenPdf ? '' : ' (auto-open off)';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved$pages$openHint:\n${file.path}')),
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
    // Never mutate controllers during build — schedule a post-frame write.
    if (normalized != raw && normalized.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ctrl = _controllers[key];
        if (ctrl != null && ctrl.text != normalized) {
          ctrl.text = normalized;
        }
      });
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
        : key == LabelFields.location && _kind == LabelKind.shipping
            ? 6 // Matches doubled Location band on the shipping PDF.
            : key == LabelFields.specialInstructions
                ? 2 // Shorter SI entry; PDF band absorbs PO/Project growth.
                : 3;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: lines <= 1
          ? TextField(
              controller: _controllers[key],
              maxLines: 1,
              decoration: InputDecoration(
                labelText: m.$2.toUpperCase(),
              ),
            )
          : FormScrollTextField(
              controller: _controllers[key]!,
              minLines: 1,
              maxLines: lines,
              decoration: InputDecoration(
                labelText: m.$2.toUpperCase(),
              ),
            ),
    );
  }

  /// On Windows, pair single-line fields into two columns for denser forms.
  Widget _buildFieldsBlock(List<String> keys, {bool dualColumn = false}) {
    if (!dualColumn) {
      return Column(
        children: [for (final key in keys) _buildFormField(key)],
      );
    }

    final out = <Widget>[];
    final pending = <String>[];

    void flushPending() {
      for (var i = 0; i < pending.length; i += 2) {
        if (i + 1 < pending.length) {
          out.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildFormField(pending[i])),
                const SizedBox(width: 12),
                Expanded(child: _buildFormField(pending[i + 1])),
              ],
            ),
          );
        } else {
          out.add(_buildFormField(pending[i]));
        }
      }
      pending.clear();
    }

    for (final key in keys) {
      final multiline = _meta(key).$3;
      if (multiline) {
        flushPending();
        out.add(_buildFormField(key));
      } else {
        pending.add(key);
      }
    }
    flushPending();
    return Column(children: out);
  }

  Widget _buildFreightChargesSelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
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
            emptySelectionAllowed: false,
            showSelectedIcon: false,
            segments: [
              for (final o in BolFields.freightChargeOptions)
                ButtonSegment<String>(
                  value: o.$1,
                  label: Text(o.$2, textAlign: TextAlign.center),
                ),
            ],
            selected: _selectedFreightCharges().isEmpty
                ? {BolFields.freightPrepaid}
                : _selectedFreightCharges(),
            onSelectionChanged: (selection) {
              _setField(
                BolFields.freightCharges,
                selection.isEmpty
                    ? BolFields.freightPrepaid
                    : selection.first,
              );
              setState(() {});
            },
            style: const ButtonStyle(
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

  void _selectKind(LabelKind kind) {
    setState(() {
      _kind = kind;
      _presetName = null;
      if (_kind == LabelKind.bol) {
        _bolLineCount = _detectBolLineCount();
        _syncSignaturesQuietly();
      } else {
        _bolLineCount = 1;
      }
    });
  }

  void _newDocument(LabelKind kind) {
    _clearAll();
    _selectKind(kind);
  }

  void _onBolCopyChanged({bool? store, bool? driver, bool? customer}) {
    setState(() {
      if (store != null) _bolStoreCopy = store;
      if (driver != null) _bolDriverCopy = driver;
      if (customer != null) _bolCustomerCopy = customer;
    });
  }

  String get _kindTitle => switch (_kind) {
        LabelKind.shipping => 'Shipping Label',
        LabelKind.receiving => 'Receiving Label',
        LabelKind.bol => 'Bill of Lading',
      };

  String get _kindHint => switch (_kind) {
        LabelKind.receiving =>
          'Pre-fill the receiving / staging label → Generate PDF. Special Instructions stay two lines.',
        LabelKind.bol =>
          'Straight Bill of Lading. Choose which copies to print. Document number SW-#### is assigned from the shared company counter on Generate (needs network).',
        LabelKind.shipping =>
          'Pre-fill the label → Generate PDF. You’ll be asked how many pallet/crate and box labels to print.',
      };

  List<(String, String, List<String>)> get _activeGroups => switch (_kind) {
        LabelKind.receiving => _receivingGroups,
        LabelKind.bol => _bolGroupsBeforeLines,
        LabelKind.shipping => _shippingGroups,
      };

  int get _kindRailIndex => switch (_kind) {
        LabelKind.shipping => 0,
        LabelKind.receiving => 1,
        LabelKind.bol => 2,
      };

  Widget _buildMobileKindSelector() {
    return SegmentedButton<LabelKind>(
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
      onSelectionChanged: (s) => _selectKind(s.first),
      style: const ButtonStyle(
        textStyle: WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'Oswald',
            fontWeight: FontWeight.w600,
            fontSize: 12,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  Widget _buildBolCopiesCard({bool compact = false}) {
    Widget copyTile(String title, bool value, ValueChanged<bool?> onChanged) {
      return CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(title, style: TextStyle(fontSize: compact ? 13 : 14)),
        value: value,
        onChanged: onChanged,
      );
    }

    return _Card(
      title: 'Copies to generate',
      hint: 'Only selected pages are included in the PDF',
      dense: compact,
      child: Column(
        children: [
          copyTile('Store Copy', _bolStoreCopy,
              (v) => setState(() => _bolStoreCopy = v ?? false)),
          copyTile('Driver Copy', _bolDriverCopy,
              (v) => setState(() => _bolDriverCopy = v ?? false)),
          copyTile('Customer Copy', _bolCustomerCopy,
              (v) => setState(() => _bolCustomerCopy = v ?? false)),
        ],
      ),
    );
  }

  Widget _buildPresetCard({bool dense = false}) {
    final presetNames = widget.storage.presetDisplayNamesFor(_kind);
    return _Card(
      title: 'Customer preset',
      hint: dense
          ? 'Shared cloud presets — per document type'
          : 'Shared across all devices — per document type; shipment fields stay per job',
      dense: dense,
      child: Column(
        children: [
          DropdownButtonFormField<String?>(
            key: ValueKey('preset-$_kind-${presetNames.length}'),
            value: _presetName != null && presetNames.contains(_presetName)
                ? _presetName
                : null,
            hint: const Text('Select preset'),
            decoration: const InputDecoration(labelText: 'PRESET'),
            isExpanded: true,
            items: [
              for (final n in presetNames)
                DropdownMenuItem<String?>(value: n, child: Text(n)),
            ],
            onChanged: (v) {
              if (v != null) _applyPreset(v);
            },
          ),
          SizedBox(height: dense ? 8 : 10),
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
                  onPressed: _presetName == null ? null : _deletePreset,
                  child: const Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogosCard({bool dense = false, bool stackActions = false}) {
    final logoButtons = stackActions
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.tonalIcon(
                onPressed: (_findingLogo ||
                        _recreatingLogo ||
                        _logoPaths.length >= maxCustomerLogos)
                    ? null
                    : _findLogoOnWeb,
                icon: _findingLogo
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.travel_explore, size: 18),
                label: Text(
                  _findingLogo ? 'Searching…' : 'Find logo on the web',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _logoPaths.length >= maxCustomerLogos ||
                        _recreatingLogo
                    ? null
                    : _showUploadManuallyMenu,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Upload manually'),
              ),
            ],
          )
        : Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: (_findingLogo ||
                          _recreatingLogo ||
                          _logoPaths.length >= maxCustomerLogos)
                      ? null
                      : _findLogoOnWeb,
                  icon: _findingLogo
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.travel_explore, size: 18),
                  label: Text(
                    _findingLogo ? 'Searching…' : 'Find logo on the web',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _logoPaths.length >= maxCustomerLogos ||
                          _recreatingLogo
                      ? null
                      : _showUploadManuallyMenu,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('Upload manually'),
                ),
              ),
            ],
          );

    return _Card(
      title: 'Customer logos',
      hint: 'Up to $maxCustomerLogos per label — second logo is C/O',
      dense: dense,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _logoPaths.length; i++) ...[
            if (i > 0) SizedBox(height: dense ? 6 : 8),
            Container(
              padding: EdgeInsets.all(dense ? 8 : 10),
              decoration: BoxDecoration(
                color: SwiftColors.bg,
                borderRadius: BorderRadius.circular(dense ? 6 : 10),
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
                            height: dense ? 36 : 44,
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
          if (_logoPaths.isNotEmpty) SizedBox(height: dense ? 10 : 12),
          _RecreateCheckbox(
            value: _recreateLogo,
            busy: _recreatingLogo,
            onChanged: (v) => setState(() => _recreateLogo = v ?? false),
          ),
          SizedBox(height: dense ? 6 : 8),
          logoButtons,
        ],
      ),
    );
  }

  List<Widget> _buildDocumentFormCards({required bool dualColumn}) {
    final cards = <Widget>[
      for (final group in _activeGroups)
        _Card(
          title: group.$1,
          hint: group.$2,
          dense: dualColumn,
          child: Column(
            children: [
              _buildFieldsBlock(group.$3, dualColumn: dualColumn),
              if (_kind == LabelKind.bol && group.$1 == 'Billing & freight')
                _buildFreightChargesSelector(),
            ],
          ),
        ),
    ];

    if (_kind == LabelKind.bol) {
      for (var lineNum = 1; lineNum <= _bolLineCount; lineNum++) {
        cards.add(
          _Card(
            title: 'Line $lineNum',
            hint: _bolLineHint(lineNum),
            dense: dualColumn,
            trailing: lineNum > 1
                ? IconButton(
                    tooltip: 'Remove line',
                    onPressed: () => _removeBolLine(lineNum),
                    icon: const Icon(Icons.delete_outline, size: 20),
                  )
                : null,
            child: _buildFieldsBlock(
              _bolLineFieldKeys(lineNum),
              dualColumn: dualColumn,
            ),
          ),
        );
      }
      if (_bolLineCount < _bolMaxLines) {
        cards.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: dualColumn
                  ? OutlinedButton.icon(
                      onPressed: _addBolLine,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add line'),
                    )
                  : IconButton.filledTonal(
                      tooltip: 'Add line',
                      onPressed: _addBolLine,
                      icon: const Icon(Icons.add),
                    ),
            ),
          ),
        );
      }
      cards.add(
        _Card(
          title: _bolSignaturesGroup.$1,
          hint: _bolSignaturesGroup.$2,
          dense: dualColumn,
          child: Column(
            children: [
              _buildShipperSignatureRow(),
              _buildFieldsBlock(
                _bolSignaturesGroup.$3,
                dualColumn: dualColumn,
              ),
            ],
          ),
        ),
      );
    }

    return cards;
  }

  Widget _buildUtilityActions({bool toolbarStyle = false}) {
    if (toolbarStyle) {
      return Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          TextButton.icon(
            onPressed: _loadSample,
            icon: const Icon(Icons.science_outlined, size: 16),
            label: const Text('Load sample'),
          ),
          TextButton.icon(
            onPressed: _clearShipment,
            icon: const Icon(Icons.clear_all, size: 16),
            label: const Text('Clear shipment'),
          ),
          TextButton.icon(
            onPressed: _clearAll,
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Clear all'),
          ),
        ],
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        TextButton(onPressed: _loadSample, child: const Text('Load sample')),
        TextButton(
          onPressed: _clearShipment,
          child: const Text('Clear shipment'),
        ),
        TextButton(onPressed: _clearAll, child: const Text('Clear all')),
      ],
    );
  }

  Widget _buildWindowsScaffold(BuildContext context) {
    final chrome = SwiftChromeColors.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final preset = _uiSettings.layoutPreset;
    final wide = switch (preset) {
      UiLayoutPreset.widescreen => width >= 1000,
      UiLayoutPreset.compact => width >= 1400,
      UiLayoutPreset.stacked => false,
      UiLayoutPreset.classic => width >= 1180,
    };
    final showWorkspace = _uiSettings.showWorkspacePane &&
        (preset == UiLayoutPreset.stacked || wide);
    final stacked = preset == UiLayoutPreset.stacked && showWorkspace;
    final sideWorkspace = showWorkspace && !stacked;
    final railExtended = _uiSettings.preferExtendedRail
        ? width >= (preset == UiLayoutPreset.compact ? 1280 : 1100)
        : false;
    final dense = _uiSettings.denseForms || preset == UiLayoutPreset.compact;
    final dualColumn = _uiSettings.formColumns >= 2;

    final menuActions = WindowsMenuActions(
      storage: widget.storage,
      settings: _uiSettings,
      kind: _kind,
      busy: _busy,
      recreateLogo: _recreateLogo,
      bolStoreCopy: _bolStoreCopy,
      bolDriverCopy: _bolDriverCopy,
      bolCustomerCopy: _bolCustomerCopy,
      onNewDocument: _newDocument,
      onGenerate: _generateAndShare,
      onClearShipment: _clearShipment,
      onClearAll: _clearAll,
      onSavePreset: _savePreset,
      onDeletePreset: _deletePreset,
      onToggleRecreate: (v) => setState(() => _recreateLogo = v),
      onSelectKind: _selectKind,
      onBolCopyChanged: _onBolCopyChanged,
      onSettingsChanged: _applyUiSettings,
      onFindLogo: _findLogoOnWeb,
      onBrowseLogo: _browseAndImportLogo,
      onAddFromStorage: _addFromStorageAndImport,
      onLoadSample: _loadSample,
    );

    final formList = ListView(
      primary: true,
      padding: EdgeInsets.fromLTRB(dense ? 16 : 24, 8, dense ? 16 : 24, 28),
      children: [
        if (!sideWorkspace) ...[
          if (_kind == LabelKind.bol) ...[
            _buildBolCopiesCard(compact: true),
            const SizedBox(height: 4),
          ],
          _buildPresetCard(dense: true),
          _buildLogosCard(dense: true, stackActions: true),
        ],
        ..._buildDocumentFormCards(dualColumn: dualColumn),
        const SizedBox(height: 4),
        _buildUtilityActions(toolbarStyle: true),
        // When the workspace pane is hidden (narrow window / user toggle),
        // keep Generate visible in the form column — menu/Ctrl+Enter still work.
        if (!showWorkspace) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _generateAndShare,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: Text(_busy ? 'Generating…' : 'Generate PDF'),
          ),
        ],
      ],
    );

    final workspacePane = Material(
      color: chrome.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Workspace',
              style: TextStyle(
                fontFamily: 'Oswald',
                fontWeight: FontWeight.w600,
                fontSize: 14,
                letterSpacing: 0.4,
                color: chrome.ink,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              primary: false,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                _buildPresetCard(dense: true),
                _buildLogosCard(dense: true, stackActions: true),
                if (_kind == LabelKind.bol) _buildBolCopiesCard(compact: true),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: FilledButton.icon(
              onPressed: _busy ? null : _generateAndShare,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text(_busy ? 'Generating…' : 'Generate PDF'),
            ),
          ),
        ],
      ),
    );

    return CallbackShortcuts(
      bindings: windowsShortcutMap(
        onGenerate: _generateAndShare,
        onShipping: () => _selectKind(LabelKind.shipping),
        onReceiving: () => _selectKind(LabelKind.receiving),
        onBol: () => _selectKind(LabelKind.bol),
        onSavePreset: _savePreset,
        onClearShipment: _clearShipment,
        onNewShipping: () => _newDocument(LabelKind.shipping),
        onCheckUpdates: () => showUpdateFlow(context),
        onErrorCapture: _openErrorCapture,
        onToggleDark: _toggleDarkMode,
      ),
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: chrome.bg,
          body: Column(
            children: [
              Material(
                color: chrome.surface,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    WindowsAppMenuBar(actions: menuActions),
                    const Divider(height: 1),
                    RepaintBoundary(
                      child: _DesktopToolbar(
                        busy: _busy,
                        kindTitle: _kindTitle,
                        showUpdate: _uiSettings.showToolbarUpdate,
                        onUpdate: () => showUpdateFlow(context),
                        onToggleDark: _toggleDarkMode,
                        isDark: _uiSettings.isDark,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    NavigationRail(
                      extended: railExtended,
                      minExtendedWidth: 168,
                      backgroundColor: chrome.panel,
                      selectedIndex: _kindRailIndex,
                      labelType: railExtended
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      onDestinationSelected: (i) {
                        _selectKind(switch (i) {
                          1 => LabelKind.receiving,
                          2 => LabelKind.bol,
                          _ => LabelKind.shipping,
                        });
                      },
                      leading: Padding(
                        padding: EdgeInsets.only(
                          top: 10,
                          bottom: railExtended ? 16 : 10,
                        ),
                        child: Container(
                          width: railExtended ? 40 : 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: chrome.accentSoft,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: SwiftColors.accent.withValues(alpha: 0.22),
                            ),
                          ),
                          child: const Icon(
                            Icons.description_outlined,
                            color: SwiftColors.accent,
                            size: 20,
                          ),
                        ),
                      ),
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.local_shipping_outlined),
                          selectedIcon: Icon(Icons.local_shipping),
                          label: Text('Shipping'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.inventory_2_outlined),
                          selectedIcon: Icon(Icons.inventory_2),
                          label: Text('Receiving'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.receipt_long_outlined),
                          selectedIcon: Icon(Icons.receipt_long),
                          label: Text('BOL'),
                        ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              dense ? 16 : 24,
                              16,
                              dense ? 16 : 24,
                              4,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _kindTitle,
                                  style: TextStyle(
                                    fontFamily: 'Oswald',
                                    fontWeight: FontWeight.w600,
                                    fontSize: dense ? 20 : 22,
                                    color: chrome.ink,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _kindHint,
                                  style: TextStyle(
                                    color: chrome.muted,
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: stacked
                                ? Column(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Scrollbar(
                                          thumbVisibility: true,
                                          child: formList,
                                        ),
                                      ),
                                      const Divider(height: 1),
                                      SizedBox(height: 280, child: workspacePane),
                                    ],
                                  )
                                : Scrollbar(
                                    thumbVisibility: true,
                                    child: formList,
                                  ),
                          ),
                        ],
                      ),
                    ),
                    if (sideWorkspace) ...[
                      const VerticalDivider(width: 1),
                      SizedBox(width: 340, child: workspacePane),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileScaffold() {
    final chrome = SwiftChromeColors.of(context);
    final portrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    // Landscape keeps the full chrome; portrait collapses on scroll-down.
    final showFullChrome = !portrait || _mobileChromeExpanded;

    return Scaffold(
      backgroundColor: chrome.bg,
      body: SafeArea(
        child: Column(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: showFullChrome
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RepaintBoundary(
                          child: _Header(
                            busy: _busy,
                            isDark: _uiSettings.isDark,
                            kindTitle: _kindTitle,
                            onToggleDark: _toggleDarkMode,
                          ),
                        ),
                        Material(
                          color: chrome.surface,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildMobileKindSelector(),
                                const SizedBox(height: 8),
                                Text(
                                  _kindHint,
                                  style: TextStyle(
                                    color: chrome.muted,
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Divider(height: 1, color: chrome.border),
                      ],
                    )
                  : _MobileChromeCollapsed(
                      kindTitle: _kindTitle,
                      isDark: _uiSettings.isDark,
                      onExpand: () =>
                          setState(() => _mobileChromeExpanded = true),
                    ),
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _onMobileFormScroll,
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    if (_kind == LabelKind.bol) ...[
                      _buildBolCopiesCard(),
                      const SizedBox(height: 10),
                    ],
                    _buildPresetCard(),
                    _buildLogosCard(),
                    ..._buildDocumentFormCards(dualColumn: false),
                    _buildUtilityActions(),
                  ],
                ),
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
      ),
    );
  }

  /// Collapse portrait chrome when the user scrolls down the form.
  /// Scrolling back up near the top (or settling at the top) restores it.
  bool _onMobileFormScroll(ScrollNotification notification) {
    if (Platform.isWindows) return false;
    if (MediaQuery.orientationOf(context) != Orientation.portrait) {
      if (!_mobileChromeExpanded) {
        setState(() => _mobileChromeExpanded = true);
      }
      return false;
    }
    if (notification.metrics.axis != Axis.vertical) return false;
    final pixels = notification.metrics.pixels;

    // Fling/settle at the absolute top should always restore chrome.
    if (!_mobileChromeExpanded &&
        notification is ScrollEndNotification &&
        pixels <= 24) {
      setState(() => _mobileChromeExpanded = true);
      return false;
    }

    if (notification is! ScrollUpdateNotification) return false;
    final delta = notification.scrollDelta ?? 0;
    if (delta > 6 && pixels > 28 && _mobileChromeExpanded) {
      setState(() => _mobileChromeExpanded = false);
    } else if (!_mobileChromeExpanded &&
        delta < 0 &&
        pixels <= 24) {
      // Near the top while scrolling up — restore chrome automatically.
      setState(() => _mobileChromeExpanded = true);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows) {
      return _buildWindowsScaffold(context);
    }
    return _buildMobileScaffold();
  }
}


/// Compact Windows title strip — brand left, document context, optional Update.
/// Generate PDF lives in Workspace / menu only (not duplicated here).
class _DesktopToolbar extends StatelessWidget {
  const _DesktopToolbar({
    required this.busy,
    required this.kindTitle,
    required this.showUpdate,
    required this.onUpdate,
    required this.onToggleDark,
    required this.isDark,
  });

  final bool busy;
  final String kindTitle;
  final bool showUpdate;
  final VoidCallback onUpdate;
  final VoidCallback onToggleDark;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final chrome = SwiftChromeColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 28,
            decoration: BoxDecoration(
              color: SwiftColors.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Image.asset(
            SwiftBrandAssets.chromeLogo(dark: isDark),
            height: 26,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
          const SizedBox(width: 12),
          Text(
            'Swift Document Generator',
            style: TextStyle(
              fontFamily: 'Oswald',
              fontWeight: FontWeight.w600,
              fontSize: 15,
              letterSpacing: 0.3,
              color: chrome.ink,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 1,
            height: 18,
            color: chrome.border,
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: chrome.accentSoft,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: SwiftColors.accent.withValues(alpha: 0.18),
              ),
            ),
            child: Text(
              kindTitle,
              style: const TextStyle(
                fontFamily: 'Oswald',
                fontWeight: FontWeight.w600,
                fontSize: 12,
                letterSpacing: 0.3,
                color: SwiftColors.accent,
              ),
            ),
          ),
          const Spacer(),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            tooltip: isDark
                ? 'Light mode (Ctrl+Shift+D)'
                : 'Dark mode (Ctrl+Shift+D)',
            onPressed: busy ? null : onToggleDark,
            icon: Icon(
              isDark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
          if (showUpdate) ...[
            const SizedBox(width: 4),
            OutlinedButton.icon(
              onPressed: busy ? null : onUpdate,
              icon: const Icon(Icons.system_update_alt, size: 16),
              label: const Text('Update'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Thin portrait strip shown after the Android header collapses on scroll.
class _MobileChromeCollapsed extends StatelessWidget {
  const _MobileChromeCollapsed({
    required this.kindTitle,
    required this.isDark,
    required this.onExpand,
  });

  final String kindTitle;
  final bool isDark;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final chrome = SwiftChromeColors.of(context);
    return Material(
      color: chrome.surface,
      elevation: 0,
      child: InkWell(
        onTap: onExpand,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 22,
                    decoration: BoxDecoration(
                      color: SwiftColors.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Image.asset(
                    SwiftBrandAssets.chromeLogo(dark: isDark),
                    height: 18,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      kindTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Oswald',
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        letterSpacing: 0.3,
                        color: chrome.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Show header',
                    onPressed: onExpand,
                    icon: Icon(
                      Icons.expand_more,
                      color: chrome.ink,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: chrome.border),
          ],
        ),
      ),
    );
  }
}

/// Android / mobile header — Windows-like surface chrome, compact layout.
class _Header extends StatelessWidget {
  const _Header({
    required this.busy,
    required this.isDark,
    required this.kindTitle,
    required this.onToggleDark,
  });

  final bool busy;
  final bool isDark;
  final String kindTitle;
  final VoidCallback onToggleDark;

  @override
  Widget build(BuildContext context) {
    final chrome = SwiftChromeColors.of(context);
    return Material(
      color: chrome.surface,
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 36,
                  decoration: BoxDecoration(
                    color: SwiftColors.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Image.asset(
                  SwiftBrandAssets.chromeLogo(dark: isDark),
                  height: 30,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Swift Document Generator',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Oswald',
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          letterSpacing: 0.3,
                          color: chrome.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: chrome.accentSoft,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: SwiftColors.accent.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Text(
                          kindTitle,
                          style: const TextStyle(
                            fontFamily: 'Oswald',
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            letterSpacing: 0.3,
                            color: SwiftColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  IconButton(
                    tooltip: isDark ? 'Light mode' : 'Dark mode',
                    onPressed: onToggleDark,
                    icon: Icon(
                      isDark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      color: chrome.ink,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => showUpdateFlow(context),
                    icon: const Icon(Icons.system_update_alt, size: 16),
                    label: const Text('Update'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: chrome.border),
        ],
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
    final chrome = SwiftChromeColors.of(context);
    return Material(
      color: chrome.surface,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: chrome.border),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(isDarkChrome(context) ? 0x66000000 : 0x14000000),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: busy ? null : onGenerate,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined, size: 20),
              label: Text(busy ? 'Generating…' : 'Generate PDF'),
            ),
          ),
        ),
      ),
    );
  }
}

bool isDarkChrome(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.hint,
    required this.child,
    this.trailing,
    this.dense = false,
  });

  final String title;
  final String hint;
  final Widget child;
  final Widget? trailing;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final chrome = SwiftChromeColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            dense ? 12 : 14,
            dense ? 10 : 12,
            dense ? 12 : 14,
            dense ? 10 : 12,
          ),
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
                          style: TextStyle(
                            fontFamily: 'Oswald',
                            fontWeight: FontWeight.w600,
                            fontSize: dense ? 14 : 15,
                            color: chrome.ink,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hint,
                          style: TextStyle(
                            fontSize: dense ? 11 : 12,
                            color: chrome.muted,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
              SizedBox(height: dense ? 8 : 10),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact "Recreate" toggle rendered above the logo action buttons.
///
/// When checked, the next logo import (web find OR manual upload) is
/// routed through the premium vectorizer, producing a bg-stripped
/// vector SVG + a crisp PNG. When unchecked, the raster is stored as-is
/// (with only the existing light `LogoImageProcessor` fast-trim applied).
///
/// The recreate pipeline runs on both Windows and Android:
///   - Windows: local Python if present; else Fly.io Python when online;
///     else on-device Rust; Supabase vtracer last resort.
///   - Android: Fly.io Python when online; else on-device Rust offline /
///     on Fly failure; Supabase vtracer last resort.
class _RecreateCheckbox extends StatelessWidget {
  const _RecreateCheckbox({
    required this.value,
    required this.busy,
    required this.onChanged,
  });

  final bool value;
  final bool busy;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final disabled = busy;
    final subtitle = Platform.isWindows
        ? 'Runs the premium tracer on the next logo you find or '
            'upload: strips background, rebuilds it as clean vectors, '
            'stores SVG + crisp PNG. Slower — ~5–30 s '
            '(local Python when available; else Fly cloud / Rust).'
        : 'Online: Fly.io Python cloud tracer. Offline: on-device Rust. '
            'Strips background, rebuilds clean vectors, stores SVG + '
            'crisp PNG. Slower — usually ~5–30 s (cold start may add a bit).';
    final chrome = SwiftChromeColors.of(context);
    return Tooltip(
      message: 'Vectorize and clean the next logo before saving.',
      child: InkWell(
        onTap: disabled ? null : () => onChanged(!value),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 20,
                width: 20,
                child: busy
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : Checkbox(
                        value: value,
                        onChanged: onChanged,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recreate (vectorize & clean background)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: chrome.ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: chrome.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
