import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/delivery.dart';
import '../../data/models/lead.dart';
import '../../data/providers.dart';
import '../../data/repositories/company_repository.dart';
import '../../widgets/auto_refresh.dart';
import '../../widgets/download.dart';
import '../../data/api/api_client.dart';
import '../../widgets/motion.dart';
import '../admins/admins_screen.dart';
import '../announcements/announcements_screen.dart';
import '../attendance/attendance_screen.dart';
import '../audit/audit_screen.dart';
import '../auth/auth_state.dart';
import '../config/config_screen.dart';
import '../customers/customers_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../dashboard/design_tokens.dart';
import '../deliveries/deliveries_screen.dart';
import '../leads/leads_screen.dart';
import '../reports/reports_screen.dart';
import '../reps/reps_screen.dart';
import '../targets/targets_screen.dart';
import '../visits/visits_screen.dart';

/// Set by any screen that wants to jump somewhere - the dashboard's
/// "View all", the sidebar search. The shell listens.
final ValueNotifier<NavSection?> openSection = ValueNotifier<NavSection?>(null);

/// The sections of the console, in sidebar order.
enum NavSection {
  dashboard('Dashboard', Icons.grid_view_rounded, NavGroup.overview),
  admins('Admins', Icons.shield_outlined, NavGroup.people),
  reps('Sales reps', Icons.people_outline, NavGroup.people),
  leads('Leads', Icons.bolt_outlined, NavGroup.pipeline),
  customers('Customers', Icons.storefront_outlined, NavGroup.pipeline),
  deliveries('Handovers', Icons.flag_outlined, NavGroup.pipeline),
  visits('Visits', Icons.route_outlined, NavGroup.pipeline),
  attendance('Attendance', Icons.schedule_outlined, NavGroup.people),
  targets('Targets & incentives', Icons.track_changes_outlined, NavGroup.insight),
  reports('Reports', Icons.show_chart, NavGroup.insight),
  audit('Audit log', Icons.receipt_long_outlined, NavGroup.insight),
  announcements('Announcements', Icons.campaign_outlined, NavGroup.insight),
  config('Configuration', Icons.tune_rounded, NavGroup.system);

  const NavSection(this.label, this.icon, this.group);

  final String label;
  final IconData icon;
  final NavGroup group;
}

/// The sidebar's section headings (RECORDS in the design).
enum NavGroup {
  overview('Overview'),
  people('People'),
  pipeline('Pipeline'),
  insight('Insight'),
  system('System');

  const NavGroup(this.label);

  final String label;

  List<NavSection> get sections =>
      NavSection.values.where((NavSection s) => s.group == this).toList();
}

/// Persistent chrome, laid out like the "Modern CRM Dashboard" design: a
/// white 256px sidebar (brand, quick search, grouped links, account at the
/// bottom), a 64px header (page title, period, alerts, refresh, avatar),
/// and the page body on a near-white plane.
class ConsoleShell extends StatefulWidget {
  const ConsoleShell({super.key});

  @override
  State<ConsoleShell> createState() => _ConsoleShellState();
}

class _ConsoleShellState extends State<ConsoleShell> {
  NavSection _section = NavSection.dashboard;

  /// Collapsed to an icon rail - by the chevron, or automatically on a
  /// narrow window.
  bool _collapsed = false;

  // Bumped on every switch so the page fades and rises in; the IndexedStack
  // underneath still keeps each page's state.
  int _switches = 0;

  @override
  void initState() {
    super.initState();
    openSection.addListener(_onOpenSection);
  }

  @override
  void dispose() {
    openSection.removeListener(_onOpenSection);
    super.dispose();
  }

  void _onOpenSection() {
    final NavSection? target = openSection.value;
    if (target == null) return;
    openSection.value = null;
    _select(target);
  }

  void _select(NavSection section) {
    if (section == _section) return;
    setState(() {
      _section = section;
      _switches++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final LayoutSize size = Responsive.of(context);
    final bool collapsed = _collapsed || size.isCompact;

    return Scaffold(
      backgroundColor: Ds.page,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Sidebar(
              active: _section,
              collapsed: collapsed,
              onSelect: _select,
              onToggle: () => setState(() => _collapsed = !_collapsed),
            ),
            Expanded(
              child: Column(
                children: <Widget>[
                  _TopBar(section: _section, onSelect: _select),
                  Expanded(
                    // IndexedStack keeps each page's scroll position and
                    // filter selections alive across section switches.
                    child: Reveal(
                      key: ValueKey<int>(_switches),
                      duration: const Duration(milliseconds: 240),
                      // p-6 top: the design's content area starts a beat
                      // below the header, not against it.
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: IndexedStack(
                        index: _section.index,
                        children: const <Widget>[
                          DashboardScreen(),
                          AdminsScreen(),
                          RepsScreen(),
                          LeadsScreen(),
                          CustomersScreen(),
                          DeliveriesScreen(),
                          VisitsScreen(),
                          AttendanceScreen(),
                          TargetsScreen(),
                          ReportsScreen(),
                          AuditScreen(),
                          AnnouncementsScreen(),
                          ConfigScreen(),
                        ],
                      ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Sidebar ---------------------------------------------------------------
// <aside class="w-64 bg-white border-r border-slate-200/80 flex flex-col">

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.active,
    required this.collapsed,
    required this.onSelect,
    required this.onToggle,
  });

  final NavSection active;
  final bool collapsed;
  final ValueChanged<NavSection> onSelect;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: collapsed ? AppSpacing.sidebarCollapsed : 256,
      decoration: BoxDecoration(
        color: Ds.sidebar,
        border: Border(right: BorderSide(color: Ds.border.withValues(alpha: 0.8))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Brand(collapsed: collapsed, onToggle: onToggle),
          if (!collapsed) const _QuickSearch(),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: collapsed ? 8 : 12,
                vertical: 8,
              ),
              children: <Widget>[
                for (final NavGroup g in NavGroup.values)
                  if (g != NavGroup.system) ...<Widget>[
                    if (g != NavGroup.overview)
                      _GroupHeading(label: g.label, collapsed: collapsed),
                    for (final NavSection s in g.sections)
                      _NavLink(
                        section: s,
                        selected: s == active,
                        collapsed: collapsed,
                        onTap: () => onSelect(s),
                      ),
                  ],
              ],
            ),
          ),
          _SidebarFooter(
            collapsed: collapsed,
            configSelected: active == NavSection.config,
            onConfig: () => onSelect(NavSection.config),
          ),
        ],
      ),
    );
  }
}

/// px-5 py-4 border-b: emerald square logo, workspace name, collapse chevron.
class _Brand extends StatelessWidget {
  const _Brand({required this.collapsed, required this.onToggle});

  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 12 : 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ds.borderSoft)),
      ),
      child: Row(
        children: <Widget>[
          // The company mark, on white so its black-and-blue reads.
          Container(
            width: 32,
            height: 32,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Ds.border),
              boxShadow: Ds.shadow2xs,
            ),
            child: Image.asset('assets/logo.png', fit: BoxFit.contain),
          ),
          if (!collapsed) ...<Widget>[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'SalesHub',
                overflow: TextOverflow.ellipsis,
                style: Ds.t(14, Ds.slate800, w: 600, spacing: -0.2),
              ),
            ),
          ],
          if (!collapsed)
            IconButton(
              tooltip: 'Collapse menu',
              onPressed: onToggle,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.keyboard_double_arrow_left, size: 18, color: Ds.slate400),
            ),
        ],
      ),
    );
  }
}

/// The design's "Quick actions ⌘K" box: here it is the lead search, which
/// jumps to Leads with the term applied.
class _QuickSearch extends ConsumerStatefulWidget {
  const _QuickSearch();

  @override
  ConsumerState<_QuickSearch> createState() => _QuickSearchState();
}

class _QuickSearchState extends ConsumerState<_QuickSearch> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go() {
    final String term = _controller.text.trim();
    if (term.isEmpty) return;
    ref.read(globalSearchProvider.notifier).state = term;
    _controller.clear();
    openSection.value = NavSection.leads;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        height: 34,
        padding: const EdgeInsets.only(left: 10, right: 8),
        decoration: BoxDecoration(
          color: Ds.control,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Ds.border),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.search, size: 15, color: Ds.slate400),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                onSubmitted: (_) => _go(),
                decoration: InputDecoration(
                  hintText: 'Find a lead',
                  hintStyle: Ds.t12(Ds.slate400),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                style: Ds.t12(Ds.slate700),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Ds.border),
              ),
              child: Text('↵', style: Ds.t10(Ds.slate400, w: 500)),
            ),
          ],
        ),
      ),
    );
  }
}

/// text-[11px] font-semibold text-slate-400 uppercase tracking-wider
class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.label, required this.collapsed});

  final String label;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Divider(height: 1, color: Ds.borderSoft),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
      child: Text(
        label.toUpperCase(),
        style: Ds.t11(Ds.slate400, w: 600).copyWith(letterSpacing: 0.8),
      ),
    );
  }
}

/// px-3 py-2 text-xs font-medium text-slate-600 rounded-lg; active:
/// font-semibold text-emerald-700 bg-emerald-50.
class _NavLink extends StatelessWidget {
  const _NavLink({
    required this.section,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final NavSection section;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color fg = selected ? Ds.brand700 : Ds.slate600;
    final Widget link = Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: Ds.control,
        child: Container(
          height: 34,
          padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12),
          alignment: collapsed ? Alignment.center : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: selected ? Ds.brand50 : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: collapsed ? MainAxisSize.min : MainAxisSize.max,
            children: <Widget>[
              Icon(section.icon, size: 16, color: selected ? Ds.brand600 : Ds.slate400),
              if (!collapsed) ...<Widget>[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    section.label,
                    overflow: TextOverflow.ellipsis,
                    style: Ds.t12(fg, w: selected ? 600 : 500),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return collapsed ? Tooltip(message: section.label, child: link) : link;
  }
}

/// p-3 border-t: configuration, theme, and the signed-in account with a
/// sign-out button - in the slot the design uses for its trial widget.
class _SidebarFooter extends ConsumerWidget {
  const _SidebarFooter({
    required this.collapsed,
    required this.configSelected,
    required this.onConfig,
  });

  final bool collapsed;
  final bool configSelected;
  final VoidCallback onConfig;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SignedInUser? me = ref.watch(currentUserProvider).valueOrNull;
    final String name = me?.name ?? '-';
    final String role = me?.roleLabel ?? '';

    return Container(
      padding: EdgeInsets.all(collapsed ? 8 : 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Ds.borderSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _NavLink(
            section: NavSection.config,
            selected: configSelected,
            collapsed: collapsed,
            onTap: onConfig,
          ),
          const SizedBox(height: 4),
          if (collapsed) ...<Widget>[
            const Center(child: ThemeToggle()),
            const SizedBox(height: 4),
            Center(
              child: IconButton(
                tooltip: 'Sign out',
                onPressed: signOut,
                icon: const Icon(Icons.logout, size: 16, color: Ds.slate500),
              ),
            ),
          ] else
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Ds.control,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Ds.border.withValues(alpha: 0.7)),
              ),
              child: Row(
                children: <Widget>[
                  const LiveDot(color: Ds.brand500, size: 8),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: Ds.t12(Ds.slate700, w: 600),
                        ),
                        Text(
                          role,
                          overflow: TextOverflow.ellipsis,
                          style: Ds.t11(Ds.slate500),
                        ),
                      ],
                    ),
                  ),
                  const ThemeToggle(),
                  const SizedBox(width: 2),
                  Tooltip(
                    message: 'Sign out',
                    child: InkWell(
                      onTap: signOut,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Ds.border),
                          boxShadow: Ds.shadow2xs,
                        ),
                        child: Text('Sign out', style: Ds.t11(Ds.slate700, w: 500)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// --- Top bar ---------------------------------------------------------------
// <header class="h-16 px-6 bg-white border-b"> title | period ... alerts,
// refresh, avatar.

class _TopBar extends StatelessWidget {
  const _TopBar({required this.section, required this.onSelect});

  final NavSection section;
  final ValueChanged<NavSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final bool compact = Responsive.of(context).isCompact;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Ds.border.withValues(alpha: 0.8))),
      ),
      child: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              section.label,
              style: Ds.h1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (section == NavSection.dashboard) ...<Widget>[
            const SizedBox(width: 16),
            Container(width: 1, height: 16, color: Ds.border),
            const SizedBox(width: 16),
            const _PeriodPicker(),
          ],
          const Spacer(),
          // Below 900px the labels go and the controls become icons, so
          // the header never wraps or clips.
          _AlertsPill(onTap: () => onSelect(NavSection.leads), compact: compact),
          const SizedBox(width: 8),
          _ExportButton(compact: compact),
          const SizedBox(width: 8),
          const RefreshButton(),
          const SizedBox(width: 8),
          Container(width: 1, height: 24, color: Ds.border),
          const SizedBox(width: 12),
          const _Avatar(),
        ],
      ),
    );
  }
}

/// The design's "Last 30 Days": drives the dashboard's window.
class _PeriodPicker extends ConsumerWidget {
  const _PeriodPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int days = ref.watch(dashboardDaysProvider);
    return PopupMenuButton<int>(
      tooltip: 'Period',
      position: PopupMenuPosition.under,
      onSelected: (int d) => ref.read(dashboardDaysProvider.notifier).state = d,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Ds.border),
      ),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
        for (final int d in <int>[7, 14, 30, 90])
          PopupMenuItem<int>(
            value: d,
            height: 36,
            child: Text(
              'Last $d days',
              style: Ds.t12(d == days ? Ds.brand700 : Ds.slate700, w: d == days ? 600 : 500),
            ),
          ),
      ],
      child: DsControlButton(label: 'Last $days days'),
    );
  }
}

/// The design's "Export Report": one workbook - Leads, Customers,
/// Handovers - scoped to what this account may see. Managers and above.
class _ExportButton extends ConsumerStatefulWidget {
  const _ExportButton({this.compact = false});

  final bool compact;

  @override
  ConsumerState<_ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends ConsumerState<_ExportButton> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final (List<int> bytes, String name) =
          await ref.read(apiClientProvider).getBytes('/api/export/pipeline.xlsx');
      saveBytes(
        Uint8List.fromList(bytes),
        name,
        mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: ${e.message}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Download the pipeline as Excel: Leads, Customers, Handovers',
      child: DsControlButton(
        label: widget.compact ? '' : (_busy ? 'Preparing…' : 'Export Excel'),
        icon: _busy ? Icons.hourglass_top : Icons.download_outlined,
        trailing: null,
        white: true,
        onTap: _busy ? null : _export,
      ),
    );
  }
}

/// Overdue follow-ups plus blocked handovers: the number that needs a
/// manager today. Emerald dot when nothing is waiting.
class _AlertsPill extends ConsumerWidget {
  const _AlertsPill({required this.onTap, this.compact = false});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CompanySnapshot? co = ref.watch(companyProvider).valueOrNull;
    final DateTime now = DateTime.now();
    final int count = co == null
        ? 0
        : co.deliveries
                  .where((Delivery d) => d.status == DeliveryStatus.notDelivered)
                  .length +
              co.leads
                  .where(
                    (Lead l) =>
                        l.isOpen &&
                        l.nextActionAt != null &&
                        l.nextActionAt!.isBefore(now),
                  )
                  .length;

    return Tooltip(
      message: 'Overdue follow-ups and blocked handovers',
      child: DsControlButton(
        label: compact
            ? (count == 0 ? '' : '$count')
            : (count == 0 ? 'All clear' : '$count need${count == 1 ? 's' : ''} attention'),
        icon: count == 0 ? Icons.check_circle_outline : Icons.notifications_none,
        trailing: null,
        white: true,
        onTap: onTap,
      ),
    );
  }
}

/// w-8 h-8 rounded-full bg-slate-200 ring-2 ring-emerald-500/20 initials.
class _Avatar extends ConsumerWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SignedInUser? me = ref.watch(currentUserProvider).valueOrNull;
    final String name = me?.name ?? '-';
    return Tooltip(
      message: '$name${me?.username.isNotEmpty == true ? ' · @${me!.username}' : ''}',
      child: DsAvatar(initials: Fmt.initials(name)),
    );
  }
}

/// Light / dark switch. The design is light; dark stays available.
class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isDark = appThemeMode.value == ThemeMode.dark;
    return Tooltip(
      message: isDark ? 'Switch to light' : 'Switch to dark',
      child: IconButton(
        onPressed: () =>
            appThemeMode.value = isDark ? ThemeMode.light : ThemeMode.dark,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        icon: Icon(
          isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          size: 15,
          color: Ds.slate400,
        ),
      ),
    );
  }
}
