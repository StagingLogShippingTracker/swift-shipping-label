import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'label_data.dart';
import 'pdf/bol_label_pdf.dart';
import 'pdf/shipping_label_pdf.dart';
import 'pdf_download_stub.dart'
    if (dart.library.html) 'pdf_download_web.dart' as pdf_out;
import 'pdf_render_options.dart';
import 'swift_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final pdf = await ShippingLabelPdf.load();
  runApp(SdgWebDemoApp(pdf: pdf));
}

class SdgWebDemoApp extends StatefulWidget {
  const SdgWebDemoApp({super.key, required this.pdf});

  final ShippingLabelPdf pdf;

  @override
  State<SdgWebDemoApp> createState() => _SdgWebDemoAppState();
}

class _SdgWebDemoAppState extends State<SdgWebDemoApp> {
  bool _dark = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Swift Document Generator',
      debugShowCheckedModeBanner: false,
      theme: buildSwiftTheme(dark: false),
      darkTheme: buildSwiftTheme(dark: true),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      home: DemoHome(
        pdf: widget.pdf,
        isDark: _dark,
        onToggleDark: () => setState(() => _dark = !_dark),
      ),
    );
  }
}

class DemoHome extends StatefulWidget {
  const DemoHome({
    super.key,
    required this.pdf,
    required this.isDark,
    required this.onToggleDark,
  });

  final ShippingLabelPdf pdf;
  final bool isDark;
  final VoidCallback onToggleDark;

  @override
  State<DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<DemoHome> {
  LabelKind _kind = LabelKind.shipping;
  late ShippingLabelData _shipping;
  late ShippingLabelData _receiving;
  late ShippingLabelData _bol;
  late ShippingLabelData _bulk;
  bool _busy = false;
  bool _boxSized = false;
  bool _bolStore = true;
  bool _bolDriver = true;
  bool _bolCustomer = true;
  int _pallets = 2;
  int _boxes = 1;
  String? _status;
  String _presetName = 'Pacific Canbriam (sample)';
  Uint8List? _customerLogo;

  final _presets = const [
    'Pacific Canbriam (sample)',
    'ConocoPhillips (receiving sample)',
    'Blank document',
  ];

  @override
  void initState() {
    super.initState();
    _shipping = ShippingLabelData.sample.copy();
    _receiving = ShippingLabelData.receivingSample.copy();
    _bol = ShippingLabelData.bolSample.copy();
    _bulk = ShippingLabelData.sample.copy();
    _loadCustomerLogo();
  }

  Future<void> _loadCustomerLogo() async {
    try {
      final data = await rootBundle.load('assets/images/propak_logo.png');
      setState(() => _customerLogo = data.buffer.asUint8List());
    } catch (_) {
      try {
        final data =
            await rootBundle.load('assets/images/sample_customer_logo.png');
        setState(() => _customerLogo = data.buffer.asUint8List());
      } catch (_) {}
    }
  }

  ShippingLabelData get _data => switch (_kind) {
        LabelKind.shipping => _shipping,
        LabelKind.receiving => _receiving,
        LabelKind.bol => _bol,
        LabelKind.bulk => _bulk,
      };

  String get _kindTitle => switch (_kind) {
        LabelKind.shipping => 'Shipping Label',
        LabelKind.receiving => 'Receiving Label',
        LabelKind.bol => 'Bill of Lading',
        LabelKind.bulk => 'Bulk Labels',
      };

  int get _railIndex => switch (_kind) {
        LabelKind.shipping => 0,
        LabelKind.receiving => 1,
        LabelKind.bol => 2,
        LabelKind.bulk => 3,
      };

  void _selectKind(LabelKind kind) => setState(() => _kind = kind);

  void _loadPreset(String name) {
    setState(() {
      _presetName = name;
      if (name.startsWith('Pacific')) {
        _shipping = ShippingLabelData.sample.copy();
        _bol = ShippingLabelData.bolSample.copy();
        _kind = LabelKind.shipping;
      } else if (name.startsWith('Conoco')) {
        _receiving = ShippingLabelData.receivingSample.copy();
        _kind = LabelKind.receiving;
      } else {
        _shipping = ShippingLabelData();
        _receiving = ShippingLabelData();
        _bol = ShippingLabelData();
      }
      _status = 'Loaded preset: $name';
    });
  }

  Future<void> _generate() async {
    if (_kind == LabelKind.bulk) {
      setState(() => _status =
          'Bulk Avery 5163 generation is available in the Windows/Android apps. Use Shipping / Receiving / BOL here.');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Generating PDF…';
    });
    try {
      final logos =
          _customerLogo == null ? <Uint8List>[] : <Uint8List>[_customerLogo!];
      final options = PdfRenderOptions.defaults.copyWith(isBoxSized: _boxSized);
      late final Uint8List bytes;
      switch (_kind) {
        case LabelKind.receiving:
          bytes = await widget.pdf.buildReceiving(
            data: _receiving,
            customerLogoBytes: logos,
            options: options,
          );
        case LabelKind.bol:
          bytes = await BolLabelPdf(widget.pdf).build(
            data: _bol,
            customerLogoBytes: logos,
            options: PdfRenderOptions.defaults,
          );
        case LabelKind.shipping:
          bytes = await widget.pdf.build(
            data: _shipping,
            customerLogoBytes: logos,
            piecePlan: PieceCountPlan(palletCrates: _pallets, boxes: _boxes),
            options: options,
          );
        case LabelKind.bulk:
          return;
      }
      pdf_out.openPdfInBrowser(bytes);
      setState(() => _status =
          'Opened $_kindTitle PDF in a new tab (same engine as Windows/Android).');
    } catch (e) {
      setState(() => _status = 'Generate failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  List<(String, String, bool)> get _fields {
    switch (_kind) {
      case LabelKind.receiving:
        return const [
          (LabelFields.customer, 'Customer', false),
          (LabelFields.project, 'Project', true),
          (LabelFields.poNum, 'PO No.', true),
          (LabelFields.salesOrder, 'Sales Order', false),
          (LabelFields.swiftContact, 'Swift Contact', false),
          (LabelFields.dateReceived, 'Date Received', false),
          (LabelFields.receivedBy, 'Received By', false),
          (LabelFields.specialInstructions, 'Special Instructions', true),
        ];
      case LabelKind.bol:
        return BolFields.formDefs.take(18).toList();
      case LabelKind.bulk:
        return const [
          (LabelFields.customer, 'Customer', false),
          (LabelFields.poNum, 'PO No.', true),
          (LabelFields.salesOrder, 'Sales Order', false),
          (LabelFields.carrier, 'Carrier', false),
        ];
      case LabelKind.shipping:
        return const [
          (LabelFields.customer, 'Customer', false),
          (LabelFields.shipTo, 'Ship To Name', false),
          (LabelFields.poNum, 'PO No.', true),
          (LabelFields.location, 'Delivery Address', true),
          (LabelFields.project, 'Project', true),
          (LabelFields.carrier, 'Carrier', false),
          (BolFields.freightCharges, 'Freight Charges', false),
          (BolFields.thirdPartyBilling, '3rd Party Billing', true),
          (LabelFields.specialInstructions, 'Special Instructions', true),
          (LabelFields.attn, 'ATTN', false),
          (LabelFields.packingSlip, 'Packing Slip', false),
          (LabelFields.salesOrder, 'Sales Order', false),
          (LabelFields.swiftContact, 'Swift Contact', false),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 900;
    return desktop ? _buildDesktop(context) : _buildMobile(context);
  }

  Widget _buildDesktop(BuildContext context) {
    final chrome = SwiftChrome.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 1180;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _generate,
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
            _selectKind(LabelKind.shipping),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
            _selectKind(LabelKind.receiving),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
            _selectKind(LabelKind.bol),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: chrome.bg,
          body: Column(
            children: [
              _DesktopChrome(
                kindTitle: _kindTitle,
                isDark: widget.isDark,
                onToggleDark: widget.onToggleDark,
                onGenerate: _busy ? null : _generate,
                onLoadSample: () => _loadPreset(_presets.first),
              ),
              Material(
                color: const Color(0xFFFFF3E0),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.science_outlined,
                          color: SwiftColors.accent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Portfolio demo — layout matches the Windows app (rail + workspace). '
                          'Sample data only; cloud sync / updates / logo recreate are disabled.',
                          style: TextStyle(color: chrome.ink, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    NavigationRail(
                      extended: wide,
                      minExtendedWidth: 168,
                      backgroundColor: chrome.panel,
                      selectedIndex: _railIndex,
                      labelType: wide
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      onDestinationSelected: (i) => _selectKind(switch (i) {
                        1 => LabelKind.receiving,
                        2 => LabelKind.bol,
                        3 => LabelKind.bulk,
                        _ => LabelKind.shipping,
                      }),
                      leading: Padding(
                        padding: EdgeInsets.only(
                            top: 10, bottom: wide ? 16 : 10),
                        child: Container(
                          width: wide ? 40 : 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: chrome.accentSoft,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color:
                                  SwiftColors.accent.withValues(alpha: 0.22),
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
                    VerticalDivider(width: 1, color: chrome.border),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                            child: Text(
                              _kindTitle,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: chrome.ink,
                              ),
                            ),
                          ),
                          Expanded(child: _buildFormList(dense: true)),
                          if (_status != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                              child: Text(_status!,
                                  style: TextStyle(
                                      color: chrome.muted, fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                    if (wide) ...[
                      VerticalDivider(width: 1, color: chrome.border),
                      SizedBox(
                        width: 300,
                        child: Material(
                          color: chrome.panel,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                child: Text(
                                  'Workspace',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    letterSpacing: 0.4,
                                    color: chrome.ink,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: ListView(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                  children: [
                                    _buildPresetCard(),
                                    const SizedBox(height: 8),
                                    _buildLogosCard(),
                                    if (_kind == LabelKind.bol) ...[
                                      const SizedBox(height: 8),
                                      _buildBolCopiesCard(),
                                    ],
                                    if (_kind == LabelKind.shipping) ...[
                                      const SizedBox(height: 8),
                                      _buildPiecePlanCard(),
                                    ],
                                    if (_kind == LabelKind.bulk)
                                      Text(
                                        'Avery 5163 · Propak template',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: chrome.muted,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 0, 12, 16),
                                child: _buildGenerateControls(
                                    stackVertically: true),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!wide)
                Material(
                  color: chrome.surface,
                  elevation: 6,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: _buildGenerateControls(stackVertically: false),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobile(BuildContext context) {
    final chrome = SwiftChrome.of(context);
    return Scaffold(
      backgroundColor: chrome.bg,
      appBar: AppBar(
        backgroundColor: chrome.surface,
        foregroundColor: chrome.ink,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_kindTitle,
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: chrome.ink)),
            Text('Swift Document Generator',
                style: TextStyle(fontSize: 11, color: chrome.muted)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Toggle dark mode',
            onPressed: widget.onToggleDark,
            icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: SegmentedButton<LabelKind>(
              segments: const [
                ButtonSegment(value: LabelKind.shipping, label: Text('Ship')),
                ButtonSegment(value: LabelKind.receiving, label: Text('Recv')),
                ButtonSegment(value: LabelKind.bol, label: Text('BOL')),
                ButtonSegment(value: LabelKind.bulk, label: Text('Bulk')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => _selectKind(s.first),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Material(
            color: const Color(0xFFFFF3E0),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                'Mobile layout mirrors Android portrait chrome. Generate uses the production PDF engine.',
                style: TextStyle(color: chrome.ink, fontSize: 12),
              ),
            ),
          ),
          Expanded(child: _buildFormList(dense: false)),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_status!,
                  style: TextStyle(color: chrome.muted, fontSize: 12)),
            ),
        ],
      ),
      bottomNavigationBar: Material(
        color: chrome.surface,
        elevation: 8,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: _buildGenerateControls(stackVertically: true),
          ),
        ),
      ),
    );
  }

  Widget _buildFormList({required bool dense}) {
    final chrome = SwiftChrome.of(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(dense ? 16 : 16, 8, dense ? 16 : 16, 28),
      children: [
        if (!dense || MediaQuery.sizeOf(context).width < 1180) ...[
          _buildPresetCard(),
          const SizedBox(height: 8),
          _buildLogosCard(),
          if (_kind == LabelKind.bol) ...[
            const SizedBox(height: 8),
            _buildBolCopiesCard(),
          ],
          if (_kind == LabelKind.shipping) ...[
            const SizedBox(height: 8),
            _buildPiecePlanCard(),
          ],
          const SizedBox(height: 8),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Document fields',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: chrome.ink,
                  ),
                ),
                const SizedBox(height: 12),
                for (final f in _fields) ...[
                  _Field(
                    data: _data,
                    fieldKey: f.$1,
                    label: f.$2,
                    multiline: f.$3,
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Customer / template',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _presetName,
              items: [
                for (final p in _presets)
                  DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                if (v != null) _loadPreset(v);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogosCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: SwiftColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: _customerLogo == null
                  ? const Icon(Icons.image_outlined, color: SwiftColors.muted)
                  : Image.memory(_customerLogo!, fit: BoxFit.contain),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Customer logo (sample)\nFind / Recreate available on Windows & Android',
                style: TextStyle(fontSize: 12, color: SwiftColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBolCopiesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('BOL copies',
                style: TextStyle(fontWeight: FontWeight.w600)),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _bolStore,
              onChanged: (v) => setState(() => _bolStore = v ?? true),
              title: const Text('STORE'),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _bolDriver,
              onChanged: (v) => setState(() => _bolDriver = v ?? true),
              title: const Text('DRIVER'),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _bolCustomer,
              onChanged: (v) => setState(() => _bolCustomer = v ?? true),
              title: const Text('CUSTOMER'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPiecePlanCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Piece count (pages)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: '$_pallets',
                    decoration: const InputDecoration(labelText: 'Pallets/Crates'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) =>
                        setState(() => _pallets = int.tryParse(v) ?? 1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: '$_boxes',
                    decoration: const InputDecoration(labelText: 'Boxes'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) =>
                        setState(() => _boxes = int.tryParse(v) ?? 0),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenerateControls({required bool stackVertically}) {
    final boxToggle = CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: _boxSized &&
          (_kind == LabelKind.shipping || _kind == LabelKind.receiving),
      enabled: _kind == LabelKind.shipping || _kind == LabelKind.receiving,
      onChanged: (_kind == LabelKind.shipping || _kind == LabelKind.receiving)
          ? (v) => setState(() => _boxSized = v ?? false)
          : null,
      title: const Text('Box Label (1/4 Page)', style: TextStyle(fontSize: 13)),
      controlAffinity: ListTileControlAffinity.leading,
    );
    final button = SizedBox(
      width: stackVertically ? double.infinity : null,
      height: 40,
      child: FilledButton.icon(
        onPressed: _busy ? null : _generate,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Icon(
                _kind == LabelKind.bulk
                    ? Icons.description_outlined
                    : Icons.picture_as_pdf_outlined,
                size: 18,
              ),
        label: Text(_busy
            ? 'Generating…'
            : (_kind == LabelKind.bulk ? 'Generate' : 'Generate PDF')),
      ),
    );
    if (stackVertically) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [boxToggle, const SizedBox(height: 8), button],
      );
    }
    return Row(
      children: [
        Expanded(child: boxToggle),
        const SizedBox(width: 12),
        button,
      ],
    );
  }
}

class _DesktopChrome extends StatelessWidget {
  const _DesktopChrome({
    required this.kindTitle,
    required this.isDark,
    required this.onToggleDark,
    required this.onGenerate,
    required this.onLoadSample,
  });

  final String kindTitle;
  final bool isDark;
  final VoidCallback onToggleDark;
  final VoidCallback? onGenerate;
  final VoidCallback onLoadSample;

  @override
  Widget build(BuildContext context) {
    final chrome = SwiftChrome.of(context);
    return Material(
      color: chrome.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Lightweight stand-in for WindowsAppMenuBar
          SizedBox(
            height: 28,
            child: Row(
              children: [
                const SizedBox(width: 8),
                _MenuLabel('File'),
                _MenuLabel('Edit'),
                _MenuLabel('Document'),
                _MenuLabel('View'),
                _MenuLabel('Help'),
                const Spacer(),
                Text('Demo',
                    style: TextStyle(fontSize: 11, color: chrome.muted)),
                const SizedBox(width: 12),
              ],
            ),
          ),
          Divider(height: 1, color: chrome.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/swift_supply_logo_orange.png',
                  height: 26,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.local_shipping,
                    color: SwiftColors.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  kindTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: chrome.ink,
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton(
                  onPressed: onLoadSample,
                  child: const Text('Load sample'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Toggle dark mode',
                  onPressed: onToggleDark,
                  icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode_outlined),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: onGenerate,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Generate PDF'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(text,
          style: TextStyle(
            fontSize: 12,
            color: SwiftChrome.of(context).ink,
          )),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.data,
    required this.fieldKey,
    required this.label,
    required this.multiline,
    required this.onChanged,
  });

  final ShippingLabelData data;
  final String fieldKey;
  final String label;
  final bool multiline;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    if (fieldKey == BolFields.freightCharges) {
      final current = data.get(fieldKey);
      return InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: BolFields.freightChargeOptions
                    .any((o) => o.$1 == current)
                ? current
                : BolFields.freightPrepaid,
            items: [
              for (final o in BolFields.freightChargeOptions)
                DropdownMenuItem(value: o.$1, child: Text(o.$2)),
            ],
            onChanged: (v) {
              if (v != null) {
                data.set(fieldKey, v);
                onChanged();
              }
            },
          ),
        ),
      );
    }
    return TextFormField(
      key: ValueKey('$fieldKey-${data.get(fieldKey)}'),
      initialValue: data.get(fieldKey),
      maxLines: multiline ? 3 : 1,
      decoration: InputDecoration(labelText: label),
      onChanged: (v) {
        data.set(fieldKey, v);
        onChanged();
      },
    );
  }
}
