import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import 'app_snack.dart';
import 'app_storage.dart';
import 'app_theme_scope.dart';
import 'bol_document_number.dart';
import 'bol_item_type.dart';
import 'brand_assets.dart';
import 'bulk/bulk_label_models.dart';
import 'bulk/order_ack_pdf_text.dart';
import 'circle_selector.dart';
import 'employee_autocomplete_field.dart';
import 'employee_directory.dart';
import 'feedback_forms.dart';
import 'form_scroll_text_field.dart';
import 'label_data.dart';
import 'logo_finder.dart';
import 'logo_import_options.dart';
import 'pdf/bol_label_pdf.dart';
import 'pdf/bulk_label_docx.dart';
import 'pdf/bulk_label_pdf.dart';
import 'pdf/shipping_label_pdf.dart';
import 'pdf_render_options.dart';
import 'platform_io.dart';
import 'preset_sync.dart';
import 'signature_pad.dart';
import 'signature_sync.dart';
import 'theme.dart';
import 'update_sheet.dart';
import 'windows_menu_bar.dart';

String swiftUiFont(BuildContext context) {
  try {
    return AppThemeScope.of(context).value.uiFontFamily;
  } catch (_) {
    return Theme.of(context).textTheme.bodyMedium?.fontFamily ?? 'Helvetica';
  }
}


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
      LabelFields.salesOrder,
      LabelFields.swiftContact,
    ],
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
  /// Box-sized (1/4 page) shipping/receiving labels. Disabled for BOL.
  bool _boxSizedLabel = false;
  /// Parsed Order Acknowledgement for Bulk Labels mode.
  OrderAckParseResult? _bulkParse;
  String? _bulkSourcePath;
  bool _bulkParsing = false;
  final EmployeeDirectory _employeeDirectory = EmployeeDirectory();
  List<String> _rosterNames = const [];
  List<String> _swiftContactNames = const [];
  bool _swiftContactsLoading = false;
  /// Focus nodes for employee-name autocomplete fields (one per key).
  final Map<String, FocusNode> _employeeFocusNodes = {
    LabelFields.swiftContact: FocusNode(),
    LabelFields.receivedBy: FocusNode(),
    BolFields.shipperCertName: FocusNode(),
  };
  /// Desktop form column — shared with [Scrollbar] so wheel works over fields.
  final ScrollController _desktopFormScroll = ScrollController();
  /// Desktop workspace pane list.
  final ScrollController _desktopWorkspaceScroll = ScrollController();

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
    _loadSwiftContacts();
  }

  Future<void> _loadSwiftContacts({bool forceRefresh = false}) async {
    if (_swiftContactsLoading) return;
    setState(() => _swiftContactsLoading = true);
    try {
      final roster =
          await _employeeDirectory.fetchNames(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _rosterNames = roster;
        _swiftContactNames = widget.storage.contactSuggestions(roster: roster);
        _swiftContactsLoading = false;
      });
    } catch (e) {
      debugPrint('[SwiftContact] load failed: $e');
      if (!mounted) return;
      // Still surface locally remembered names when the roster is offline.
      setState(() {
        _swiftContactNames =
            widget.storage.contactSuggestions(roster: _rosterNames);
        _swiftContactsLoading = false;
      });
    }
  }

  void _refreshContactSuggestions() {
    setState(() {
      _swiftContactNames =
          widget.storage.contactSuggestions(roster: _rosterNames);
    });
  }

  Future<void> _rememberContactNames(Iterable<String> rawNames) async {
    var changed = false;
    for (final raw in rawNames) {
      if (await widget.storage.rememberContact(raw)) changed = true;
    }
    if (changed && mounted) _refreshContactSuggestions();
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
        showAppSnack(context, 'Preset sync: ${e.message}');
      }
    } catch (_) {
      if (mounted) {
        showAppSnack(context, 'Preset sync failed — using local presets.');
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
        showAppSnack(context, 'Signature sync: ${e.message}');
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
        showAppSnack(context, 'Cloud sync: ${e.message}');
      }
    } catch (_) {
      if (mounted) {
        showAppSnack(context, 'Cloud sync failed — saved locally.');
      }
    }
  }

  Future<void> _deletePresetQuietly(LabelKind kind, String displayName) async {
    try {
      await _presetSync.deletePreset(kind, displayName);
    } on PresetSyncException catch (e) {
      if (mounted) {
        showAppSnack(context, 'Cloud sync: ${e.message}');
      }
    } catch (_) {
      if (mounted) {
        showAppSnack(context, 'Cloud sync failed — deleted locally only.');
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final n in _employeeFocusNodes.values) {
      n.dispose();
    }
    _desktopFormScroll.dispose();
    _desktopWorkspaceScroll.dispose();
    _employeeDirectory.dispose();
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
      showAppSnack(context, 'Saved preset “$displayName”.');
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
          showAppSnack(context, 'Recreate finished — logo cleaned.');
        } else {
          final detail = (result.recreateError ?? 'unknown error').trim();
          final short = detail.length > 140
              ? '${detail.substring(0, 140)}…'
              : detail;
          showAppSnack(
            context,
            'Recreate failed — imported original instead. $short',
            duration: const Duration(seconds: 6),
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
      showAppSnack(context, 'No logos in storage yet — use Browse.');
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
                            child: Scrollbar(
                              thumbVisibility: true,
                              interactive: true,
                              child: ListView(
                                shrinkWrap: true,
                                primary: true,
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
                                          showAppSnack(ctx, 
                                                'Could not delete “$name”.',
                                              );
                                          return;
                                        }
                                        setState(() {
                                          _logoPaths.remove(f.path);
                                        });
                                        setDialogState(() {});
                                        if (!ctx.mounted) return;
                                        showAppSnack(ctx, 'Deleted “$name”.');
                                      },
                                    ),
                                  ),
                              ],
                              ),
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
      showAppSnack(context, 'Already have 2 logos. Remove one to find another.');
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
    // Wait for Tools MenuBar overlay to dismiss before presenting.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    // MenuItemButton sets an inherited anchor near the menu (bottom-right).
    // Force the dialog anchor to the window center so DisplayFeatureSubScreen
    // cannot pin the card off-screen.
    final viewSize = MediaQuery.sizeOf(context);
    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss find logo',
      barrierColor: Colors.transparent,
      useRootNavigator: true,
      anchorPoint: Offset(viewSize.width / 2, viewSize.height / 2),
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        // SizedBox.expand + Center (no MediaQuery math). A Positioned-only
        // Stack collapses to bottom-right on Windows; MediaQuery width can
        // also exceed the window and push the card off-screen.
        return SizedBox.expand(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.pop(ctx, false),
                  child: const ColoredBox(color: Color(0x8A000000)),
                ),
              ),
              Center(
                child: Material(
                  color: Theme.of(ctx).dialogTheme.backgroundColor ??
                      Theme.of(ctx).colorScheme.surface,
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Find logo on the web',
                            style: Theme.of(ctx).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Search Google, Bing, Clearbit, Brands of the World, and other '
                            'sources. A website domain improves accuracy.',
                            style: TextStyle(
                              fontSize: 13,
                              color: SwiftColors.muted,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'CUSTOMER / COMPANY',
                            ),
                            autofocus: true,
                            onSubmitted: (_) => Navigator.pop(ctx, true),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: domainCtrl,
                            decoration: const InputDecoration(
                              labelText: 'WEBSITE DOMAIN (OPTIONAL)',
                              hintText: 'e.g. conocophillips.com',
                            ),
                            onSubmitted: (_) => Navigator.pop(ctx, true),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Source: ${selectedEngine.label}  (Tools → Logo search engine…)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: SwiftColors.muted,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Search'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
        showAppSnack(context, 
              'No logo found across Google, Bing, Brands of the World, and other sources. '
              'Try a website domain or upload manually.',
            );
        setState(() => _findingLogo = false);
        return;
      }

      final picked = await showDialog<LogoDownloadedCandidate>(
        context: context,
        builder: (ctx) {
          final mq = MediaQuery.of(ctx);
          final maxW = (mq.size.width - 32).clamp(280.0, 560.0);
          final maxH = (mq.size.height -
                  mq.padding.vertical -
                  mq.viewInsets.bottom -
                  96)
              .clamp(220.0, mq.size.height);
          // Leave room for title + actions inside the dialog.
          final gridH = (maxH * 0.72).clamp(160.0, 520.0);
          return AlertDialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            title: const Text('Choose a logo'),
            content: SizedBox(
              width: maxW,
              height: gridH + 36,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Top ${candidates.length} of up to ${LogoFinder.pickerMaxResults} '
                    'result${candidates.length == 1 ? '' : 's'} — tap a thumbnail',
                    style:
                        const TextStyle(fontSize: 13, color: SwiftColors.muted),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Scrollbar(
                      thumbVisibility: true,
                      interactive: true,
                      child: SingleChildScrollView(
                        primary: true,
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
                                    border:
                                        Border.all(color: SwiftColors.muted),
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
          );
        },
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
      showAppSnack(context, 'Logo from ${chosen.source}.$hint');
    } catch (e) {
      if (mounted) {
        showAppSnack(context, 'Web find failed: $e. Try Upload manually.');
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
    if (_kind == LabelKind.bulk) {
      _loadBulkSample();
      return;
    }
    final s = switch (_kind) {
      LabelKind.receiving => ShippingLabelData.receivingSample,
      LabelKind.bol => ShippingLabelData.bolSample,
      LabelKind.shipping => ShippingLabelData.sample,
      LabelKind.bulk => ShippingLabelData.sample,
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

  Future<void> _loadBulkSample() async {
    setState(() => _bulkParsing = true);
    try {
      final fixture = File(
        p.join(
          Directory.current.path,
          'test',
          'fixtures',
          'propak_order_ack_sample.pdf',
        ),
      );
      if (await fixture.exists()) {
        await _parseBulkPdf(fixture.path);
        return;
      }
      if (!mounted) return;
      setState(() => _bulkParsing = false);
      showAppSnack(context, 
            'Sample OA not found — upload an Order Acknowledgement PDF.',
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _bulkParsing = false);
      showAppSnack(context, 'Sample load failed: $e');
    }
  }

  Future<void> _pickBulkPdf() async {
    final path = await pickPdfPath();
    if (path == null) return;
    await _parseBulkPdf(path);
  }

  Future<void> _parseBulkPdf(String path) async {
    setState(() => _bulkParsing = true);
    try {
      final bytes = await File(path).readAsBytes();
      var parsed = await parseOrderAckPdf(
        Uint8List.fromList(bytes),
        sourceFileName: p.basename(path),
      );
      if (!mounted) return;

      if (parsed.hasIncompleteLines) {
        setState(() => _bulkParsing = false);
        final action = await _promptBulkMissingIdentity(parsed);
        if (!mounted) return;
        if (action == null || action == BulkMissingIdAction.cancel) {
          setState(() {
            _bulkParse = null;
            _bulkSourcePath = null;
          });
          showAppSnack(context, 'Bulk label upload cancelled.');
          return;
        }
        parsed = parsed.applyingMissingIdAction(action);
      }

      setState(() {
        _bulkParse = parsed;
        _bulkSourcePath = path;
        _bulkParsing = false;
      });
      if (parsed.lines.isEmpty && mounted) {
        showAppSnack(context, 
              parsed.warnings.isEmpty
                  ? 'No label lines found in that PDF.'
                  : parsed.warnings.first,
            );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bulkParsing = false;
        _bulkParse = null;
      });
      showAppSnack(context, 'Could not read Order Acknowledgement: $e');
    }
  }

  /// Ask what to do with OA lines that have CPO but no TAG# / PART#.
  Future<BulkMissingIdAction?> _promptBulkMissingIdentity(
    OrderAckParseResult parsed,
  ) async {
    final incomplete = parsed.incompleteLines;
    final cpoList = incomplete.map((l) => '#${l.cpo}').join(', ');
    final lineSummary = incomplete.length == 1
        ? 'Line CPO $cpoList is missing a TAG# or PART# on the Order '
            'Acknowledgement.'
        : '${incomplete.length} lines are missing a TAG# or PART# on the '
            'Order Acknowledgement (CPO $cpoList).';

    return showDialog<BulkMissingIdAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final chrome = SwiftChromeColors.of(ctx);
        return AlertDialog(
          title: const Text('Missing TAG# / PART#'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lineSummary,
                  style: TextStyle(
                    fontFamily: swiftUiFont(ctx),
                    fontSize: 14,
                    height: 1.35,
                    color: chrome.ink,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Please check with the PM before deciding. You can still '
                  'proceed with blank identity fields (edit them in Word), '
                  'skip these lines, or cancel the upload.',
                  style: TextStyle(
                    fontFamily: swiftUiFont(ctx),
                    fontSize: 13,
                    height: 1.35,
                    color: chrome.muted,
                  ),
                ),
                if (incomplete.length <= 8) ...[
                  const SizedBox(height: 12),
                  for (final inc in incomplete)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• CPO #${inc.cpo}  ·  qty ${inc.quantity}  ·  '
                        '${inc.reason}',
                        style: TextStyle(
                          fontFamily: swiftUiFont(ctx),
                          fontSize: 12,
                          color: SwiftColors.accent,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(BulkMissingIdAction.cancel),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(BulkMissingIdAction.skip),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(BulkMissingIdAction.proceed),
              child: const Text('Proceed'),
            ),
          ],
        );
      },
    );
  }

  void _clearBulkParse() {
    setState(() {
      _bulkParse = null;
      _bulkSourcePath = null;
    });
  }

  void _clearShipment() {
    final clear = switch (_kind) {
      LabelKind.receiving => {
          LabelFields.poNum,
          LabelFields.project,
          LabelFields.salesOrder,
          LabelFields.swiftContact,
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
      LabelKind.bulk => <String>{},
    };
    for (final key in clear) {
      _controllers[key]?.clear();
    }
    if (_kind == LabelKind.bol) {
      _bolLineCount = 1;
      _setField(BolFields.freightCharges, BolFields.freightPrepaid);
    }
    if (_kind == LabelKind.bulk) {
      _bulkParse = null;
      _bulkSourcePath = null;
    }
    setState(() {});
  }

  void _clearAll() {
    for (final c in _controllers.values) {
      c.clear();
    }
    _logoPaths.clear();
    _presetName = null;
    _shipperSignatureBytes = null;
    _selectedSavedSignature = null;
    _bolLineCount = 1;
    _setField(BolFields.freightCharges, BolFields.freightPrepaid);
    _bulkParse = null;
    _bulkSourcePath = null;
    setState(() {});
  }

  Future<void> _generateAndShare() async {
    if (_busy) return;

    if (_kind == LabelKind.bulk) {
      await _generateBulkLabels();
      return;
    }

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
        showAppSnack(context, 'Select at least one BOL copy to generate.');
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
            options: _pdfOptionsForGenerate,
          );
        case LabelKind.bol:
          bytes = await BolLabelPdf(widget.pdf).build(
            data: data,
            customerLogoBytes: logoBytes,
            shipperSignatureBytes: _shipperSignatureBytes,
            copies: bolCopies,
            options: _pdfOptionsForGenerate,
          );
        case LabelKind.shipping:
          bytes = await widget.pdf.build(
            data: data,
            customerLogoBytes: logoBytes,
            piecePlan: piecePlan!,
            options: _pdfOptionsForGenerate,
          );
        case LabelKind.bulk:
          throw StateError('Bulk labels use _generateBulkLabels');
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

      // Local contact memory — free-text names used on generate stick for autocomplete.
      await _rememberContactNames([
        data.get(LabelFields.swiftContact),
        data.get(LabelFields.receivedBy),
        data.get(BolFields.shipperCertName),
      ]);

      if (_uiSettings.autoOpenPdf) {
        await shareOrOpenFile(file: file);
      }

      if (mounted) {
        final pages = switch (_kind) {
          LabelKind.shipping => ' (${piecePlan!.totalPages} pages)',
          LabelKind.bol =>
            ' (${bolCopies.length} ${bolCopies.length == 1 ? 'copy' : 'copies'} · ${data.get(BolFields.documentNumber)})',
          LabelKind.receiving => '',
          LabelKind.bulk => '',
        };
        final openHint = _uiSettings.autoOpenPdf ? '' : ' (auto-open off)';
        showAppSnack(context, 'Saved$pages$openHint:\n${file.path}');
      }
    } catch (e) {
      if (mounted) {
        showAppSnack(context, 'PDF failed: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generateBulkLabels() async {
    final parsed = _bulkParse;
    if (parsed == null || parsed.totalLabels < 1) {
      if (!mounted) return;
      showAppSnack(context, 'Upload an Order Acknowledgement PDF first.');
      return;
    }
    if (parsed.poNumber.trim().isEmpty) {
      if (!mounted) return;
      showAppSnack(context, 'PO Number missing — check the uploaded OA PDF.');
      return;
    }

    setState(() => _busy = true);
    try {
      final labels = parsed.expand();
      final outDir = widget.storage.pdfOutputDir(_uiSettings);
      final name = widget.storage.labelPdfBaseName(
        kind: LabelKind.bulk,
        customer: 'Propak',
        salesOrder: parsed.poNumber,
      );

      final pdf = await BulkLabelPdf.load();
      final pdfBytes = await pdf.build(labels);
      final pdfFile = await widget.storage.writePdf(
        name,
        pdfBytes,
        outputDir: outDir,
      );

      final docxBytes = await BulkLabelDocx.build(labels);
      final docxFile = await widget.storage.writeDocx(
        name,
        docxBytes,
        outputDir: outDir,
      );

      // Same as other docs: Generate saves, then opens the primary file when
      // auto-open is on. For Bulk Labels the editable Word doc is primary.
      if (_uiSettings.autoOpenPdf) {
        await shareOrOpenFile(
          file: docxFile,
          mime:
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          subject: 'Propak Bulk Labels',
        );
      }
      if (mounted) {
        final openHint = _uiSettings.autoOpenPdf ? '' : ' (auto-open off)';
        showAppSnack(
          context,
          'Saved ${labels.length} Propak labels on ${parsed.sheetCount} '
          'sheet${parsed.sheetCount == 1 ? '' : 's'}$openHint:\n'
          '${docxFile.path}\n(PDF also saved: ${p.basename(pdfFile.path)})',
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnack(context, 'Bulk label generate failed: $e');
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
        showAppSnack(context, 'Saved signature “${saved.name}”.');
      }
    } on SignatureSyncException catch (e) {
      if (mounted) {
        showAppSnack(context, 'Could not save signature: ${e.message}');
      }
    }
  }

  Future<void> _pickSavedSignature() async {
    final sigs = _signatureSync.localSignatures;
    if (sigs.isEmpty) {
      if (mounted) {
        showAppSnack(context, 'No saved signatures yet.');
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
      showAppSnack(context, 'Could not load signature.');
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
              fontFamily: swiftUiFont(context),
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
    if (key == LabelFields.swiftContact ||
        key == LabelFields.receivedBy ||
        key == BolFields.shipperCertName) {
      return _buildEmployeeNameField(key);
    }
    final m = _meta(key);
    final isDeliveryAddress = key == LabelFields.location ||
        key == BolFields.consigneeAddress;
    final lines = !m.$3
        ? 1
        : isDeliveryAddress
            ? 3 // Shipping + BOL delivery address entry height.
            : key == LabelFields.specialInstructions
                ? 2 // Shorter SI entry; PDF band absorbs PO/Project growth.
                : 3;
    final minLines = isDeliveryAddress ? 3 : (lines <= 1 ? 1 : 1);
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
              minLines: minLines,
              maxLines: lines,
              decoration: InputDecoration(
                labelText: m.$2.toUpperCase(),
              ),
            ),
    );
  }

  FocusNode _employeeFocusFor(String key) {
    return _employeeFocusNodes.putIfAbsent(key, FocusNode.new);
  }

  Widget _buildEmployeeNameField(String key) {
    final ctrl = _controllers[key]!;
    final meta = _meta(key);
    // Receiving form: Swift Contact field is the PM (duplicate PM field removed).
    final label = (key == LabelFields.swiftContact && _kind == LabelKind.receiving)
        ? 'PM'
        : meta.$2.toUpperCase();
    final hint = switch (key) {
      LabelFields.swiftContact when _kind == LabelKind.receiving =>
        'Type PM name or pick from directory',
      LabelFields.swiftContact => 'Type a name or pick from directory',
      LabelFields.receivedBy => 'Type who received or pick from directory',
      BolFields.shipperCertName => 'Type shipper name or pick from directory',
      _ => 'Type a name or pick from directory',
    };
    final remembered = {
      for (final n in widget.storage.rememberedContacts) n.toLowerCase(),
    };
    return EmployeeAutocompleteField(
      controller: ctrl,
      focusNode: _employeeFocusFor(key),
      names: _swiftContactNames,
      rememberedNames: remembered,
      labelText: label,
      hintText: hint,
      loading: _swiftContactsLoading,
      onRequestRefresh: () => _loadSwiftContacts(forceRefresh: true),
      onNameCommitted: (name) => _rememberContactNames([name]),
      onForgetRemembered: _forgetRememberedContact,
    );
  }

  Future<void> _forgetRememberedContact(String name) async {
    final removed = await widget.storage.forgetContact(name);
    if (!removed || !mounted) return;
    _refreshContactSuggestions();
    showAppSnack(context, 'Removed “$name” from saved memory.');
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
    final selected = _selectedFreightCharges().isEmpty
        ? BolFields.freightPrepaid
        : _selectedFreightCharges().first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'FREIGHT CHARGES',
            style: TextStyle(
              fontFamily: swiftUiFont(context),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: SwiftColors.muted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final o in BolFields.freightChargeOptions)
                SwiftCircleRadio<String>(
                  value: o.$1,
                  groupValue: selected,
                  label: o.$2,
                  dense: true,
                  onChanged: (v) {
                    if (v == null) return;
                    _setField(BolFields.freightCharges, v);
                    setState(() {});
                  },
                ),
            ],
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
        // Box-sized quarter-page labels are Shipping/Receiving only.
        _boxSizedLabel = false;
      } else if (_kind == LabelKind.bulk) {
        _boxSizedLabel = false;
        _bolLineCount = 1;
      } else {
        _bolLineCount = 1;
      }
    });
  }

  bool get _boxSizedAllowed =>
      _kind == LabelKind.shipping || _kind == LabelKind.receiving;

  PdfRenderOptions get _pdfOptionsForGenerate => _uiSettings.pdfOptions.copyWith(
        isBoxSized: _boxSizedAllowed && _boxSizedLabel,
      );

  /// Generate button + Box Label checkbox (desktop workspace / form / mobile).
  Widget _buildGenerateControls({
    required bool dense,
    bool stackVertically = false,
    double buttonHeight = 40,
  }) {
    final boxToggle = Tooltip(
      message: _boxSizedAllowed
          ? 'Print the label at 50% scale in the top-left quarter of a '
              'landscape Letter page (5.5″ × 4.25″).'
          : 'Box-sized labels are only available for Shipping and Receiving labels.',
      child: SwiftCircleCheckbox(
        value: _boxSizedAllowed && _boxSizedLabel,
        enabled: _boxSizedAllowed && !_busy,
        dense: true,
        label: 'Box Label (1/4 Page)',
        onChanged: !_boxSizedAllowed || _busy
            ? null
            : (v) => setState(() => _boxSizedLabel = v ?? false),
      ),
    );
    final generateLabel = _kind == LabelKind.bulk ? 'Generate' : 'Generate PDF';
    final generateIcon = _kind == LabelKind.bulk
        ? Icons.description_outlined
        : Icons.picture_as_pdf_outlined;
    final button = SizedBox(
      width: stackVertically ? double.infinity : null,
      height: buttonHeight,
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
            : Icon(generateIcon, size: 18),
        label: Text(_busy ? 'Generating…' : generateLabel),
      ),
    );
    if (stackVertically) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          boxToggle,
          SizedBox(height: dense ? 8 : 10),
          button,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: boxToggle),
        const SizedBox(width: 12),
        button,
      ],
    );
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
        LabelKind.bulk => 'Bulk Labels',
      };

  String get _kindHint => switch (_kind) {
        LabelKind.receiving =>
          'Pre-fill the receiving / staging label → Generate PDF. Special Instructions stay two lines.',
        LabelKind.bol =>
          'Straight Bill of Lading. Choose which copies to print. Document number SW-#### is assigned from the shared company counter on Generate (needs network).',
        LabelKind.shipping =>
          'Pre-fill the label → Generate PDF. You’ll be asked how many pallet/crate and box labels to print.',
        LabelKind.bulk =>
          'Upload a Swift Order Acknowledgement PDF. Avery 5163 Propak stickers are built from PO#, CPO LINE #, and TAG# or PART# (whichever the OA line notes use). Quantity = label count. Outputs Word + PDF.',
      };

  List<(String, String, List<String>)> get _activeGroups => switch (_kind) {
        LabelKind.receiving => _receivingGroups,
        LabelKind.bol => _bolGroupsBeforeLines,
        LabelKind.shipping => _shippingGroups,
        LabelKind.bulk => const [],
      };

  int get _kindRailIndex => switch (_kind) {
        LabelKind.shipping => 0,
        LabelKind.receiving => 1,
        LabelKind.bol => 2,
        LabelKind.bulk => 3,
      };

  Widget _buildMobileKindSelector() {
    final portrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    // Portrait phones are too narrow for icon + check + label in each segment
    // (labels wrap mid-word). Use single-line labels only; landscape keeps icons.
    Text label(String text) => Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
        );
    return SegmentedButton<LabelKind>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: LabelKind.shipping,
          label: label('Ship'),
          icon: portrait
              ? null
              : const Icon(Icons.local_shipping_outlined, size: 18),
        ),
        ButtonSegment(
          value: LabelKind.receiving,
          label: label('Recv'),
          icon: portrait
              ? null
              : const Icon(Icons.inventory_2_outlined, size: 18),
        ),
        ButtonSegment(
          value: LabelKind.bol,
          label: label('BOL'),
          icon: portrait
              ? null
              : const Icon(Icons.description_outlined, size: 18),
        ),
        ButtonSegment(
          value: LabelKind.bulk,
          label: label('Bulk'),
          icon: portrait
              ? null
              : const Icon(Icons.grid_view_outlined, size: 18),
        ),
      ],
      selected: {_kind},
      onSelectionChanged: (s) => _selectKind(s.first),
      style: ButtonStyle(
        visualDensity:
            portrait ? VisualDensity.compact : VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(
            horizontal: portrait ? 6 : 12,
            vertical: portrait ? 8 : 10,
          ),
        ),
        textStyle: WidgetStatePropertyAll(
          TextStyle(
            fontFamily: swiftUiFont(context),
            fontWeight: FontWeight.w600,
            fontSize: portrait ? 13 : 12,
            letterSpacing: 0.2,
            height: 1.0,
          ),
        ),
      ),
    );
  }

  Widget _buildBolCopiesCard({bool compact = false}) {
    return _Card(
      title: 'Copies to generate',
      hint: 'Only selected pages are included in the PDF',
      dense: compact,
      child: Column(
        children: [
          SwiftCircleCheckbox(
            dense: compact,
            label: 'Store Copy',
            value: _bolStoreCopy,
            onChanged: (v) => setState(() => _bolStoreCopy = v ?? false),
          ),
          SwiftCircleCheckbox(
            dense: compact,
            label: 'Driver Copy',
            value: _bolDriverCopy,
            onChanged: (v) => setState(() => _bolDriverCopy = v ?? false),
          ),
          SwiftCircleCheckbox(
            dense: compact,
            label: 'Customer Copy',
            value: _bolCustomerCopy,
            onChanged: (v) => setState(() => _bolCustomerCopy = v ?? false),
          ),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _logoPaths.length >= maxCustomerLogos ||
                        _recreatingLogo
                    ? null
                    : _showUploadManuallyMenu,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text(
                  'Upload manually',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                  label: const Text(
                    'Upload manually',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
                          style: TextStyle(
                            fontFamily: swiftUiFont(context),
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

  Widget _buildBulkLabelsPanel({bool dense = false}) {
    final parsed = _bulkParse;
    final chrome = SwiftChromeColors.of(context);
    return _Card(
      title: 'Order Acknowledgement',
      hint:
          'Upload a Swift OA PDF (Propak / Avery 5163). No manual fields — lines come from the document.',
      dense: dense,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy || _bulkParsing ? null : _pickBulkPdf,
                icon: _bulkParsing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_outlined, size: 18),
                label: Text(_bulkParsing ? 'Reading…' : 'Upload OA PDF'),
              ),
              if (parsed != null)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _clearBulkParse,
                  icon: const Icon(Icons.clear, size: 18),
                  label: const Text('Clear'),
                ),
            ],
          ),
          if (_bulkSourcePath != null) ...[
            const SizedBox(height: 10),
            Text(
              _bulkSourcePath == 'sample'
                  ? 'Source: sample fixture'
                  : 'Source: ${p.basename(_bulkSourcePath!)}',
              style: TextStyle(
                fontFamily: swiftUiFont(context),
                fontSize: 12,
                color: chrome.muted,
              ),
            ),
          ],
          if (parsed != null) ...[
            const SizedBox(height: 12),
            Text(
              'PO# ${parsed.poNumber.isEmpty ? '—' : parsed.poNumber}'
              '${parsed.orderNumber.isEmpty ? '' : '  ·  Order ${parsed.orderNumber}'}'
              '\n${parsed.lines.length} lines → ${parsed.totalLabels} labels'
              ' on ${parsed.sheetCount} Avery 5163 sheet'
              '${parsed.sheetCount == 1 ? '' : 's'}',
              style: TextStyle(
                fontFamily: swiftUiFont(context),
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: chrome.ink,
              ),
            ),
            if (parsed.warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...parsed.warnings.take(5).map(
                    (w) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '• $w',
                        style: TextStyle(
                          fontFamily: swiftUiFont(context),
                          fontSize: 12,
                          color: SwiftColors.accent,
                        ),
                      ),
                    ),
                  ),
            ],
            const SizedBox(height: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: chrome.border),
                borderRadius: BorderRadius.circular(8),
                color: chrome.surface,
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 36,
                  dataRowMinHeight: 32,
                  dataRowMaxHeight: 40,
                  columns: const [
                    DataColumn(label: Text('Line')),
                    DataColumn(label: Text('CPO')),
                    DataColumn(label: Text('Kind')),
                    DataColumn(label: Text('Identity')),
                    DataColumn(label: Text('Qty'), numeric: true),
                    DataColumn(label: Text('Labels'), numeric: true),
                  ],
                  rows: [
                    for (final line in parsed.lines)
                      DataRow(
                        cells: [
                          DataCell(Text('${line.lineNo}')),
                          DataCell(Text(line.cpo)),
                          DataCell(Text(
                            line.missingIdentity ? 'TAG#*' : line.idKind.fieldLabel,
                          )),
                          DataCell(
                            SizedBox(
                              width: 160,
                              child: Text(
                                line.missingIdentity
                                    ? '(blank — check PM)'
                                    : line.tagOrPart,
                                overflow: TextOverflow.ellipsis,
                                style: line.missingIdentity
                                    ? TextStyle(
                                        fontStyle: FontStyle.italic,
                                        color: SwiftColors.accent,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          DataCell(Text('${line.quantity}')),
                          DataCell(Text('${line.labelCount}')),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              'Each sticker prints the Propak logo with PO#, CPO LINE #, and '
              'TAG# (valves) or PART# (when the OA has no tag). '
              'Quantity on each OA line controls how many identical stickers '
              'are made. Press Generate to save Word (.docx) + PDF and open '
              'the editable Word labels (same as other documents).',
              style: TextStyle(
                fontFamily: swiftUiFont(context),
                fontSize: 13,
                color: chrome.muted,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildDocumentFormCards({required bool dualColumn}) {
    if (_kind == LabelKind.bulk) {
      return [_buildBulkLabelsPanel(dense: dualColumn)];
    }

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
      controller: _desktopFormScroll,
      primary: false,
      padding: EdgeInsets.fromLTRB(dense ? 16 : 24, 8, dense ? 16 : 24, 28),
      children: [
        if (!sideWorkspace) ...[
          if (_kind == LabelKind.bol) ...[
            _buildBolCopiesCard(compact: true),
            const SizedBox(height: 4),
          ],
          if (_kind != LabelKind.bulk) ...[
            _buildPresetCard(dense: true),
            _buildLogosCard(dense: true, stackActions: true),
          ],
        ],
        ..._buildDocumentFormCards(dualColumn: dualColumn),
        const SizedBox(height: 4),
        _buildUtilityActions(toolbarStyle: true),
        // When the workspace pane is hidden (narrow window / user toggle),
        // keep Generate visible in the form column — menu/Ctrl+Enter still work.
        if (!showWorkspace) ...[
          const SizedBox(height: 12),
          _buildGenerateControls(dense: dense, stackVertically: true),
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
                fontFamily: swiftUiFont(context),
                fontWeight: FontWeight.w600,
                fontSize: 14,
                letterSpacing: 0.4,
                color: chrome.ink,
              ),
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: _desktopWorkspaceScroll,
              thumbVisibility: true,
              interactive: true,
              child: ListView(
                controller: _desktopWorkspaceScroll,
                primary: false,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  if (_kind != LabelKind.bulk) ...[
                    _buildPresetCard(dense: true),
                    _buildLogosCard(dense: true, stackActions: true),
                  ],
                  if (_kind == LabelKind.bol) _buildBolCopiesCard(compact: true),
                  if (_kind == LabelKind.bulk)
                    Text(
                      'Avery 5163 · Propak template',
                      style: TextStyle(
                        fontFamily: swiftUiFont(context),
                        fontSize: 12,
                        color: chrome.muted,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: _buildGenerateControls(dense: true),
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
        onBulk: () => _selectKind(LabelKind.bulk),
        onSavePreset: _savePreset,
        onClearShipment: _clearShipment,
        onNewShipping: () => _newDocument(LabelKind.shipping),
        onCheckUpdates: () => showUpdateFlow(context),
        onErrorCapture: _openErrorCapture,
        onToggleDark: _toggleDarkMode,
        onFindLogo: _findLogoOnWeb,
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
                          3 => LabelKind.bulk,
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
                        NavigationRailDestination(
                          icon: Icon(Icons.grid_view_outlined),
                          selectedIcon: Icon(Icons.grid_view),
                          label: Text('Bulk'),
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
                                    fontFamily: swiftUiFont(context),
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
                                        child: PrimaryScrollController(
                                          controller: _desktopFormScroll,
                                          child: Scrollbar(
                                            controller: _desktopFormScroll,
                                            thumbVisibility: true,
                                            interactive: true,
                                            child: formList,
                                          ),
                                        ),
                                      ),
                                      const Divider(height: 1),
                                      SizedBox(height: 280, child: workspacePane),
                                    ],
                                  )
                                : PrimaryScrollController(
                                    controller: _desktopFormScroll,
                                    child: Scrollbar(
                                      controller: _desktopFormScroll,
                                      thumbVisibility: true,
                                      interactive: true,
                                      child: formList,
                                    ),
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
                                  maxLines: portrait ? 4 : 3,
                                  overflow: TextOverflow.ellipsis,
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
                    if (_kind != LabelKind.bulk) ...[
                      _buildPresetCard(),
                      _buildLogosCard(stackActions: true),
                    ],
                    ..._buildDocumentFormCards(dualColumn: false),
                    _buildUtilityActions(),
                  ],
                ),
              ),
            ),
            RepaintBoundary(
              child: _BottomBar(
                busy: _busy,
                boxSizedLabel: _boxSizedAllowed && _boxSizedLabel,
                boxSizedEnabled: _boxSizedAllowed && !_busy,
                onBoxSizedChanged: (v) =>
                    setState(() => _boxSizedLabel = v ?? false),
                onGenerate: _generateAndShare,
                generateLabel:
                    _kind == LabelKind.bulk ? 'Generate' : 'Generate PDF',
                generateIcon: _kind == LabelKind.bulk
                    ? Icons.description_outlined
                    : Icons.picture_as_pdf_outlined,
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
              fontFamily: swiftUiFont(context),
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
              style: TextStyle(
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
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
                        fontFamily: swiftUiFont(context),
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
    final narrow = MediaQuery.sizeOf(context).width < 420;
    return Material(
      color: chrome.surface,
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14, 10, narrow ? 6 : 10, 10),
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
                        narrow
                            ? 'Swift Document Gen'
                            : 'Swift Document Generator',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: swiftUiFont(context),
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
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily:
                                Theme.of(context).textTheme.bodyMedium?.fontFamily,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            letterSpacing: 0.3,
                            height: 1.1,
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
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      isDark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      color: chrome.ink,
                    ),
                  ),
                  if (narrow)
                    IconButton(
                      tooltip: 'Update',
                      onPressed: () => showUpdateFlow(context),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.system_update_alt,
                        color: chrome.ink,
                        size: 20,
                      ),
                    )
                  else
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
  const _BottomBar({
    required this.busy,
    required this.boxSizedLabel,
    required this.boxSizedEnabled,
    required this.onBoxSizedChanged,
    required this.onGenerate,
    this.generateLabel = 'Generate PDF',
    this.generateIcon = Icons.picture_as_pdf_outlined,
  });

  final bool busy;
  final bool boxSizedLabel;
  final bool boxSizedEnabled;
  final ValueChanged<bool?> onBoxSizedChanged;
  final VoidCallback onGenerate;
  final String generateLabel;
  final IconData generateIcon;

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Tooltip(
                message: boxSizedEnabled
                    ? 'Print the label at 50% scale in the top-left quarter of a '
                        'landscape Letter page (5.5″ × 4.25″).'
                    : 'Box-sized labels are only available for Shipping and Receiving labels.',
                child: SwiftCircleCheckbox(
                  value: boxSizedLabel,
                  enabled: boxSizedEnabled,
                  dense: true,
                  label: 'Box Label (1/4 Page)',
                  onChanged: boxSizedEnabled ? onBoxSizedChanged : null,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
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
                      : Icon(generateIcon, size: 20),
                  label: Text(busy ? 'Generating…' : generateLabel),
                ),
              ),
            ],
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
                            fontFamily: swiftUiFont(context),
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
    return Tooltip(
      message: 'Vectorize and clean the next logo before saving.',
      child: busy
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Recreate (vectorize & clean background)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: SwiftChromeColors.of(context).ink,
                    ),
                  ),
                ),
              ],
            )
          : SwiftCircleCheckbox(
              value: value,
              onChanged: disabled ? null : onChanged,
              enabled: !disabled,
              label: 'Recreate (vectorize & clean background)',
              subtitle: subtitle,
            ),
    );
  }
}
