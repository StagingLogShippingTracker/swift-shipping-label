import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Industrial Command Center palette (mirrors staging-tracker `IndustrialTheme`).
class Ind {
  static const darkBase = Color(0xFF090D16);
  static const darkSurface = Color(0xFF1F2937);
  static const darkHeader = Color(0xFF111827);
  static const border = Color(0xFF374151);
  static const textPrimary = Color(0xFFF9FAFB);
  static const textMuted = Color(0xFF9CA3AF);
  static const mint = Color(0xFF10B981);
  static const sky = Color(0xFF3B82F6);
  static const amber = Color(0xFFF59E0B);
  static const purple = Color(0xFF8B5CF6);
  static const danger = Color(0xFFEF4444);
  static const brand = Color(0xFFFF8A3D);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final contacts = await _loadContacts();
  runApp(SlstWebDemoApp(contacts: contacts));
}

Future<List<DemoContact>> _loadContacts() async {
  try {
    final raw = await rootBundle.loadString('assets/contacts.json');
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((m) => DemoContact(
                name: '${m['name'] ?? ''}'.trim(),
                designation: '${m['designation'] ?? ''}'.trim(),
                email: '${m['email'] ?? ''}'.trim(),
                branch: '${m['branch'] ?? ''}'.trim(),
              ))
          .where((c) => c.name.isNotEmpty)
          .toList();
    }
  } catch (_) {}
  return const [];
}

class DemoContact {
  const DemoContact({
    required this.name,
    required this.designation,
    required this.email,
    required this.branch,
  });
  final String name;
  final String designation;
  final String email;
  final String branch;
}

class StagingRow {
  StagingRow({
    required this.id,
    required this.so,
    required this.customer,
    required this.status,
    required this.location,
    required this.type,
    required this.qty,
    this.weight,
    this.stagedBy,
    this.comments,
    DateTime? entryDate,
  }) : entryDate = entryDate ?? DateTime.now();

  final String id;
  final String so;
  final String customer;
  String status;
  String location;
  final String type;
  final int qty;
  final String? weight;
  final String? stagedBy;
  final String? comments;
  final DateTime entryDate;
}

class ShippedRow {
  ShippedRow({
    required this.id,
    required this.so,
    required this.customer,
    required this.carrier,
    required this.location,
    required this.type,
    required this.qty,
    required this.shippedAt,
    this.shippedBy,
  });

  final String id;
  final String so;
  final String customer;
  final String carrier;
  final String location;
  final String type;
  final int qty;
  final DateTime shippedAt;
  final String? shippedBy;
}

class SlstWebDemoApp extends StatelessWidget {
  const SlstWebDemoApp({super.key, required this.contacts});
  final List<DemoContact> contacts;

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Ind.darkBase,
      colorScheme: const ColorScheme.dark(
        primary: Ind.sky,
        secondary: Ind.mint,
        surface: Ind.darkSurface,
        error: Ind.danger,
      ),
      cardTheme: CardThemeData(
        color: Ind.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Ind.border),
        ),
      ),
      dividerColor: Ind.border,
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Ind.darkHeader,
        isDense: true,
        border: OutlineInputBorder(),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Ind.darkHeader,
        selectedIconTheme: IconThemeData(color: Ind.sky),
        selectedLabelTextStyle: TextStyle(
          color: Ind.sky,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedIconTheme: IconThemeData(color: Ind.textMuted),
        unselectedLabelTextStyle: TextStyle(color: Ind.textMuted, fontSize: 12),
        indicatorColor: Color(0xFF1E3A5F),
      ),
    );
    return MaterialApp(
      title: 'SLST — Staging Tracker',
      debugShowCheckedModeBanner: false,
      theme: base,
      home: SlstShell(contacts: contacts),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.section, this.icon, this.selectedIcon);
  final String label;
  final String section;
  final IconData icon;
  final IconData selectedIcon;
}

const _nav = [
  _NavItem('Dashboard', 'Dashboard', Icons.space_dashboard_outlined,
      Icons.space_dashboard),
  _NavItem('Staging', 'Active Staging Entries Log', Icons.inventory_2_outlined,
      Icons.inventory_2),
  _NavItem('Shipped', 'Shipped Staging Entries Log',
      Icons.local_shipping_outlined, Icons.local_shipping),
  _NavItem('Reports', 'Reports & Analytics', Icons.insert_chart_outlined_rounded,
      Icons.insert_chart),
  _NavItem('Notifications', 'Notifications', Icons.notifications_outlined,
      Icons.notifications),
  _NavItem('Contacts', 'Contacts', Icons.contacts_outlined, Icons.contacts),
  _NavItem('Settings', 'Settings', Icons.settings_outlined, Icons.settings),
];

class SlstShell extends StatefulWidget {
  const SlstShell({super.key, required this.contacts});
  final List<DemoContact> contacts;

  @override
  State<SlstShell> createState() => _SlstShellState();
}

class _SlstShellState extends State<SlstShell> {
  int _index = 0;
  bool _railCollapsed = false;
  String _query = '';
  StagingRow? _selected;
  late List<StagingRow> _staging;
  late List<ShippedRow> _shipped;

  @override
  void initState() {
    super.initState();
    _staging = [
      StagingRow(
        id: '1',
        so: 'SO-88421',
        customer: 'Pacific Canbriam',
        status: 'Ship Today',
        location: 'Bay A-3',
        type: 'Pallet',
        qty: 4,
        weight: '1800 lb',
        stagedBy: 'J. Smith',
        comments: 'Call before delivery',
      ),
      StagingRow(
        id: '2',
        so: 'SO-88455',
        customer: 'ARC Resources',
        status: 'Partial',
        location: 'Bay B-1',
        type: 'Crate',
        qty: 2,
        weight: '920 lb',
        stagedBy: 'K. Blackman',
      ),
      StagingRow(
        id: '3',
        so: 'SO-88501',
        customer: 'ConocoPhillips',
        status: 'Awaiting',
        location: 'Dock 2',
        type: 'Box',
        qty: 6,
        stagedBy: 'C. Acorn',
        comments: 'Hold for PM confirm',
      ),
      StagingRow(
        id: '4',
        so: 'SO-88517',
        customer: 'Shell Canada',
        status: 'Ship Today',
        location: 'Bay C-4',
        type: 'Bundle',
        qty: 3,
        weight: '2400 lb',
        stagedBy: 'J. Smith',
      ),
      StagingRow(
        id: '5',
        so: 'SO-88540',
        customer: 'Propak',
        status: 'Awaiting',
        location: 'Overflow',
        type: 'Pallet',
        qty: 1,
        stagedBy: 'Yard',
      ),
      StagingRow(
        id: '6',
        so: 'SO-88562',
        customer: 'Mastec Purnell',
        status: 'Partial',
        location: 'Bay A-1',
        type: 'Pallet',
        qty: 2,
        weight: '1100 lb',
        stagedBy: 'J. Smith',
      ),
    ];
    _shipped = [
      ShippedRow(
        id: 's1',
        so: 'SO-88390',
        customer: 'Mastec',
        carrier: 'Willys',
        location: 'Bay A-1',
        type: 'Pallet',
        qty: 5,
        shippedAt: DateTime.now().subtract(const Duration(hours: 5)),
        shippedBy: 'J. Smith',
      ),
      ShippedRow(
        id: 's2',
        so: 'SO-88311',
        customer: 'Epcor',
        carrier: 'Fastenal Fleet',
        location: 'Dock 1',
        type: 'Crate',
        qty: 2,
        shippedAt: DateTime.now().subtract(const Duration(days: 1)),
        shippedBy: 'K. Blackman',
      ),
      ShippedRow(
        id: 's3',
        so: 'SO-88280',
        customer: 'Pacific Canbriam',
        carrier: 'Collect',
        location: 'Bay B-2',
        type: 'Box',
        qty: 8,
        shippedAt: DateTime.now().subtract(const Duration(days: 2)),
        shippedBy: 'C. Acorn',
      ),
      ShippedRow(
        id: 's4',
        so: 'SO-88201',
        customer: 'Worley Cord',
        carrier: 'Willys',
        location: 'Bay C-2',
        type: 'Pallet',
        qty: 3,
        shippedAt: DateTime.now().subtract(const Duration(days: 3)),
        shippedBy: 'Yard',
      ),
    ];
    _selected = _staging.first;
  }

  List<StagingRow> get _filteredStaging {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _staging;
    return _staging
        .where((r) =>
            r.so.toLowerCase().contains(q) ||
            r.customer.toLowerCase().contains(q) ||
            r.location.toLowerCase().contains(q) ||
            r.status.toLowerCase().contains(q))
        .toList();
  }

  List<ShippedRow> get _filteredShipped {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _shipped;
    return _shipped
        .where((r) =>
            r.so.toLowerCase().contains(q) ||
            r.customer.toLowerCase().contains(q) ||
            r.carrier.toLowerCase().contains(q))
        .toList();
  }

  void _ship(StagingRow row) {
    setState(() {
      _staging.removeWhere((r) => r.id == row.id);
      _shipped.insert(
        0,
        ShippedRow(
          id: 'ship-${row.id}-${DateTime.now().millisecondsSinceEpoch}',
          so: row.so,
          customer: row.customer,
          carrier: 'Demo Carrier',
          location: row.location,
          type: row.type,
          qty: row.qty,
          shippedAt: DateTime.now(),
          shippedBy: 'Demo User',
        ),
      );
      _selected = _staging.isEmpty ? null : _staging.first;
      _index = 2;
      _query = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Shipped ${row.so} (demo — local only)'),
        backgroundColor: Ind.mint,
      ),
    );
  }

  void _addStaging() {
    final id = '${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _staging.insert(
        0,
        StagingRow(
          id: id,
          so: 'SO-${88400 + _staging.length}',
          customer: 'New Demo Customer',
          status: 'Awaiting',
          location: 'Dock 1',
          type: 'Pallet',
          qty: 1,
          stagedBy: 'Demo User',
          comments: 'Created in portfolio demo',
        ),
      );
      _selected = _staging.first;
      _index = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final section = _nav[_index].section;
    final body = Column(
      children: [
        _DemoBanner(),
        _HeaderBar(
          sectionTitle: section,
          userLabel: 'Demo Operator',
        ),
        Expanded(child: _page()),
        _CommandDock(
          index: _index,
          onNewEntry: _addStaging,
          onGoStaging: () => setState(() => _index = 1),
          onGoShipped: () => setState(() => _index = 2),
          onShipSelected: _selected == null ? null : () => _ship(_selected!),
          onRefresh: () => setState(() {}),
        ),
      ],
    );

    if (!wide) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          backgroundColor: Ind.darkHeader,
          selectedIndex: _index > 3 ? 4 : (_index == 4 ? 3 : _index.clamp(0, 3)),
          onDestinationSelected: (i) {
            setState(() {
              // Map compact bar: Dashboard, Staging, Shipped, Reports, Settings
              _index = switch (i) {
                0 => 0,
                1 => 1,
                2 => 2,
                3 => 3,
                _ => 6,
              };
            });
          },
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.space_dashboard_outlined),
                selectedIcon: Icon(Icons.space_dashboard),
                label: 'Dashboard'),
            NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined),
                selectedIcon: Icon(Icons.inventory_2),
                label: 'Staging'),
            NavigationDestination(
                icon: Icon(Icons.local_shipping_outlined),
                selectedIcon: Icon(Icons.local_shipping),
                label: 'Shipped'),
            NavigationDestination(
                icon: Icon(Icons.insert_chart_outlined),
                selectedIcon: Icon(Icons.insert_chart),
                label: 'Reports'),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings'),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: !_railCollapsed,
            minExtendedWidth: 220,
            backgroundColor: Ind.darkHeader,
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            leading: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
              child: Column(
                children: [
                  Image.asset(
                    'assets/slst-app-icon.png',
                    width: 40,
                    height: 40,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.warehouse,
                      color: Ind.brand,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!_railCollapsed)
                    const Text('SLST',
                        style: TextStyle(
                            color: Ind.brand,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1)),
                  IconButton(
                    tooltip: _railCollapsed ? 'Expand rail' : 'Collapse rail',
                    onPressed: () =>
                        setState(() => _railCollapsed = !_railCollapsed),
                    icon: Icon(
                      _railCollapsed
                          ? Icons.chevron_right
                          : Icons.chevron_left,
                      color: Ind.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            labelType: _railCollapsed
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            destinations: [
              for (final d in _nav)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _page() {
    switch (_index) {
      case 0:
        return _DashboardPage(staging: _staging, shipped: _shipped);
      case 1:
        return _StagingPage(
          rows: _filteredStaging,
          selected: _selected,
          query: _query,
          onQuery: (v) => setState(() => _query = v),
          onSelect: (r) => setState(() => _selected = r),
          onShip: _ship,
        );
      case 2:
        return _ShippedPage(
          rows: _filteredShipped,
          query: _query,
          onQuery: (v) => setState(() => _query = v),
        );
      case 3:
        return _ReportsPage(staging: _staging, shipped: _shipped);
      case 4:
        return const _SimpleMessagePage(
          title: 'Notifications',
          body:
              'PM notify / email workflows run in the production SLST app. This demo focuses on staging & shipping ops UI.',
        );
      case 5:
        return _ContactsPage(contacts: widget.contacts);
      default:
        return const _SimpleMessagePage(
          title: 'Settings',
          body:
              'App updates, Wear pairing, and account settings are available in the Windows/Android builds. Demo mode uses seeded local data only.',
        );
    }
  }
}

class _DemoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2A2118),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.science_outlined, color: Ind.brand, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Portfolio demo — industrial shell matches SLST Windows/Android. Seeded yard data; no Supabase / OCR.',
                style: TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({required this.sectionTitle, required this.userLabel});
  final String sectionTitle;
  final String userLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Ind.darkHeader,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Ind.border)),
        ),
        child: Row(
          children: [
            Text(sectionTitle,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Ind.mint.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Ind.mint.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.circle, size: 8, color: Ind.mint),
                  SizedBox(width: 6),
                  Text('Demo signed in', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(userLabel,
                style: const TextStyle(color: Ind.textMuted, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _CommandDock extends StatelessWidget {
  const _CommandDock({
    required this.index,
    required this.onNewEntry,
    required this.onGoStaging,
    required this.onGoShipped,
    required this.onShipSelected,
    required this.onRefresh,
  });

  final int index;
  final VoidCallback onNewEntry;
  final VoidCallback onGoStaging;
  final VoidCallback onGoShipped;
  final VoidCallback? onShipSelected;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      _DockBtn(label: 'F1 New Entry', icon: Icons.add, onTap: onNewEntry),
      _DockBtn(label: 'F2 Refresh', icon: Icons.refresh, onTap: onRefresh),
      _DockBtn(
          label: 'F3 Staging', icon: Icons.inventory_2, onTap: onGoStaging),
      _DockBtn(
          label: 'F4 Shipped', icon: Icons.local_shipping, onTap: onGoShipped),
      _DockBtn(
        label: 'F5 Ship Selected',
        icon: Icons.outbox,
        onTap: onShipSelected,
        emphasis: true,
      ),
    ];
    return Material(
      color: Ind.darkHeader,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Ind.border)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final a in actions) ...[a, const SizedBox(width: 8)]
          ]),
        ),
      ),
    );
  }
}

class _DockBtn extends StatelessWidget {
  const _DockBtn({
    required this.label,
    required this.icon,
    required this.onTap,
    this.emphasis = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: emphasis ? Ind.sky.withValues(alpha: 0.25) : Ind.darkSurface,
        foregroundColor: Ind.textPrimary,
        side: BorderSide(color: emphasis ? Ind.sky : Ind.border),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _DashboardPage extends StatelessWidget {
  const _DashboardPage({required this.staging, required this.shipped});
  final List<StagingRow> staging;
  final List<ShippedRow> shipped;

  @override
  Widget build(BuildContext context) {
    int units(String status) => staging
        .where((r) => r.status == status)
        .fold<int>(0, (a, b) => a + b.qty);
    final shippedToday = shipped
        .where((r) => DateUtils.isSameDay(r.shippedAt, DateTime.now()))
        .fold<int>(0, (a, b) => a + b.qty);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Kpi('Ship Today', '${units('Ship Today')}', Ind.brand),
            _Kpi('Partial', '${units('Partial')}', Ind.amber),
            _Kpi('Awaiting', '${units('Awaiting')}', Ind.danger),
            _Kpi('Shipped today', '$shippedToday', Ind.mint),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Warehouse floor (demo locations)',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final loc in {
              for (final r in staging) r.location,
            })
              Chip(
                backgroundColor: Ind.darkSurface,
                side: const BorderSide(color: Ind.border),
                label: Text(
                  '$loc · ${staging.where((r) => r.location == loc).fold<int>(0, (a, b) => a + b.qty)} u',
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Active staging board',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        for (final r in staging)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _statusColor(r.status).withValues(alpha: 0.2),
                child: Icon(Icons.inventory_2,
                    color: _statusColor(r.status), size: 18),
              ),
              title: Text('${r.so}  ·  ${r.customer}'),
              subtitle:
                  Text('${r.status} · ${r.location} · ${r.qty} ${r.type}'),
              trailing: Text(r.stagedBy ?? '',
                  style: const TextStyle(color: Ind.textMuted, fontSize: 12)),
            ),
          ),
      ],
    );
  }
}

class _StagingPage extends StatelessWidget {
  const _StagingPage({
    required this.rows,
    required this.selected,
    required this.query,
    required this.onQuery,
    required this.onSelect,
    required this.onShip,
  });

  final List<StagingRow> rows;
  final StagingRow? selected;
  final String query;
  final ValueChanged<String> onQuery;
  final ValueChanged<StagingRow> onSelect;
  final ValueChanged<StagingRow> onShip;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final list = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search SO, customer, bay, status…',
            ),
            onChanged: onQuery,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _MiniStat('Ship Today',
                  rows.where((r) => r.status == 'Ship Today').length, Ind.brand),
              const SizedBox(width: 8),
              _MiniStat('Partial',
                  rows.where((r) => r.status == 'Partial').length, Ind.amber),
              const SizedBox(width: 8),
              _MiniStat('Awaiting',
                  rows.where((r) => r.status == 'Awaiting').length, Ind.danger),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final r = rows[i];
              final sel = selected?.id == r.id;
              return Card(
                color: sel ? const Color(0xFF1E3A5F) : Ind.darkSurface,
                child: ListTile(
                  onTap: () => onSelect(r),
                  title: Text('${r.so} — ${r.customer}'),
                  subtitle: Text('${r.status} · ${r.location} · ${r.qty} ${r.type}'),
                  trailing: IconButton(
                    tooltip: 'Ship',
                    onPressed: () => onShip(r),
                    icon: const Icon(Icons.local_shipping, color: Ind.mint),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );

    if (!wide) return list;
    return Row(
      children: [
        Expanded(flex: 3, child: list),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 320,
          child: selected == null
              ? const Center(
                  child: Text('Select a staging entry',
                      style: TextStyle(color: Ind.textMuted)))
              : _Inspector(row: selected!, onShip: () => onShip(selected!)),
        ),
      ],
    );
  }
}

class _Inspector extends StatelessWidget {
  const _Inspector({required this.row, required this.onShip});
  final StagingRow row;
  final VoidCallback onShip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Ind.darkHeader,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Inspector',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 12),
          Text(row.so,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(row.customer, style: const TextStyle(color: Ind.textMuted)),
          const SizedBox(height: 16),
          _kv('Status', row.status),
          _kv('Location', row.location),
          _kv('Type / Qty', '${row.qty} × ${row.type}'),
          _kv('Weight', row.weight ?? '—'),
          _kv('Staged by', row.stagedBy ?? '—'),
          _kv('Comments', row.comments ?? '—'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onShip,
            icon: const Icon(Icons.local_shipping),
            label: const Text('Ship entry'),
            style: FilledButton.styleFrom(backgroundColor: Ind.mint),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k,
                style: const TextStyle(
                    color: Ind.textMuted, fontSize: 11, letterSpacing: 0.6)),
            Text(v, style: const TextStyle(fontSize: 14)),
          ],
        ),
      );
}

class _ShippedPage extends StatelessWidget {
  const _ShippedPage({
    required this.rows,
    required this.query,
    required this.onQuery,
  });
  final List<ShippedRow> rows;
  final String query;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, h:mm a');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search shipped SO / customer / carrier…',
            ),
            onChanged: onQuery,
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final r = rows[i];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle, color: Ind.mint),
                  title: Text('${r.so} — ${r.customer}'),
                  subtitle: Text(
                      '${r.carrier} · ${r.qty} ${r.type} · ${fmt.format(r.shippedAt)}'),
                  trailing: Text(r.shippedBy ?? '',
                      style: const TextStyle(color: Ind.textMuted, fontSize: 12)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ReportsPage extends StatelessWidget {
  const _ReportsPage({required this.staging, required this.shipped});
  final List<StagingRow> staging;
  final List<ShippedRow> shipped;

  @override
  Widget build(BuildContext context) {
    final totalStaging =
        staging.fold<int>(0, (a, b) => a + b.qty);
    final totalShipped =
        shipped.fold<int>(0, (a, b) => a + b.qty);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Reports & Analytics',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Kpi('Units in staging', '$totalStaging', Ind.sky),
            _Kpi('Units shipped (demo)', '$totalShipped', Ind.purple),
            _Kpi('Open SOs', '${staging.length}', Ind.amber),
            _Kpi('Carriers used',
                '${{for (final s in shipped) s.carrier}.length}', Ind.mint),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Verification audit CSV export and live Supabase metrics ship in the production app.',
          style: TextStyle(color: Ind.textMuted),
        ),
      ],
    );
  }
}

class _ContactsPage extends StatelessWidget {
  const _ContactsPage({required this.contacts});
  final List<DemoContact> contacts;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: contacts.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Contacts',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          );
        }
        final c = contacts[i - 1];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Ind.brand.withValues(alpha: 0.2),
              child: Text(c.name[0].toUpperCase(),
                  style: const TextStyle(color: Ind.brand)),
            ),
            title: Text(c.name),
            subtitle: Text([
              if (c.designation.isNotEmpty) c.designation,
              if (c.branch.isNotEmpty) c.branch,
              if (c.email.isNotEmpty) c.email,
            ].join(' · ')),
          ),
        );
      },
    );
  }
}

class _SimpleMessagePage extends StatelessWidget {
  const _SimpleMessagePage({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Text(body,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Ind.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(color: Ind.textMuted, fontSize: 12)),
              const SizedBox(height: 8),
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 28,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.count, this.color);
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text('$label · $count',
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
      ),
    );
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'Ship Today':
      return Ind.brand;
    case 'Partial':
      return Ind.amber;
    case 'Awaiting':
      return Ind.danger;
    default:
      return Ind.textMuted;
  }
}
