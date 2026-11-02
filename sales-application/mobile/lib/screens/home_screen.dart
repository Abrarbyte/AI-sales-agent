import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../theme.dart';
import '../updates.dart';
import '../widgets/form_sheet.dart';
import '../widgets/motion.dart';
import '../widgets/offline_banner.dart';
import '../widgets/update_widgets.dart';
import 'add_lead_sheet.dart';
import 'attendance_sheet.dart';
import 'followups_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import '../reminders.dart';
import 'customers_screen.dart';
import 'leads_screen.dart';

/// SalesHub's home screen, built section-for-section from the Stitch design
/// "SalesHub Dashboard - Ambient Neo UI": header, check-in card, the Sales
/// Overview pill strip, four metric tiles, and the curved bottom dock with
/// its floating Add Lead capsule.
///
/// Every figure is one the API actually returns. Where the design shows a
/// placeholder ("6 tasks active", "Review overdue client callbacks") the real
/// count or a real prompt stands in.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _me;
  Map<String, dynamic>? _today;
  List<Map<String, dynamic>> _visitsToday = const [];
  List<Map<String, dynamic>> _leads = const [];
  int _unread = 0;
  Map<String, dynamic>? _attendance;
  bool _loading = true;
  String? _error;

  /// Drives the clock. The design shows a time, and a time that never moves
  /// looks broken.
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
    // Once per app start: is there a newer build on the server? (#94)
    Updates.check().then((_) {
      if (mounted) setState(() {});
    });
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final paths = [
      '/api/auth/me/',
      // Today's visits only, for the Visits today card (#92).
      '/api/visits/?from=$today&to=$today',
      '/api/crm/leads/',
      '/api/notifications/unread-count/',
      '/api/analytics/dashboard/me/',
      // Narrowed to today: the endpoint returns a history, and the card only
      // ever asks about now.
      '/api/attendance/me/?from=$today&to=$today',
      // Pending follow-ups, so the meeting alarms are set from the moment
      // the app opens - not only after visiting the list.
      '/api/visits/followups/?status=pending',
    ];
    // First open: the last saved copy straight away, then the server (#90).
    if (_me == null) {
      final saved = await Api.instance.cachedAll(paths);
      if (saved != null && mounted) _apply(saved);
    }
    if (!mounted) return;
    setState(() {
      _loading = _me == null;
      _error = null;
    });
    try {
      // Independent requests, so fetch them together rather than in sequence.
      final results = await Future.wait(paths.map(Api.instance.get));
      if (!mounted) return;
      Reminders.sync((results[6] as List).cast<Map<String, dynamic>>());
      _apply(results);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Cannot reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Future<void> _openLeads() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LeadsScreen()),
    );
    if (mounted) _load();
  }

  Future<void> _openCustomers() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CustomersScreen()),
    );
    if (mounted) _load();
  }

  Future<void> _addLead() async {
    final lead = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddLeadSheet(),
    );
    if (lead == null || !mounted) return;
    _toast('Lead added.');
    _load();
  }

  Future<void> _attendanceAction() async {
    final checkedIn = _attendance != null;
    final checkedOut = _attendance?['check_out_at'] != null;
    if (checkedOut) {
      _toast('Day already closed. See you tomorrow.');
      return;
    }
    final result = await showFormSheet(
        context, AttendanceSheet(checkingIn: !checkedIn));
    if (result != null && mounted) {
      _toast(checkedIn ? 'Checked out.' : 'Checked in. Have a good day.');
      _load();
    }
  }

  Future<void> _openFollowUps({List<String>? kinds}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FollowUpsScreen(kinds: kinds)),
    );
    if (mounted) _load();
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    if (mounted) _load();
  }

  void _apply(List<dynamic> results) {
    setState(() {
      _me = results[0] as Map<String, dynamic>;
      _visitsToday = (results[1] as List).cast<Map<String, dynamic>>();
      _leads = (results[2] as List).cast<Map<String, dynamic>>();
      _unread = ((results[3] as Map)['unread'] as int?) ?? 0;
      _today = results[4] as Map<String, dynamic>;
      final attendance = (results[5] as List).cast<Map<String, dynamic>>();
      _attendance = attendance.isEmpty ? null : attendance.first;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final update = Updates.available.value;
    // A release that fixes something serious: update before carrying on.
    if (update != null && Updates.need.value == UpdateNeed.required) {
      return UpdateRequiredScreen(release: update);
    }
    final followups = _today?['followups'] as Map<String, dynamic>? ?? {};

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: AmbientBackground(
        child: SafeArea(
          bottom: false,
          child: OfflineAware(
            child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _errorView(scheme)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        // main: pt-2 px-5 pb-28
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 112),
                        children: [
                          if (update != null && !Updates.dismissed)
                            UpdateBanner(
                              release: update,
                              onLater: () =>
                                  setState(() => Updates.dismissed = true),
                            ),
                          Reveal(index: 0, child: _header()),
                          Reveal(index: 1, child: _checkInCard()),
                          const SizedBox(height: 16), // mb-4
                          Reveal(index: 2, child: _overview()),
                          const SizedBox(height: 16),
                          Reveal(index: 3, child: _metricsGrid(followups)),
                        ],
                      ),
                    ),
          ),
        ),
      ),
      bottomNavigationBar: _dock(),
    );
  }

  // ------------------------------------------------------------- header
  // <header class="pt-3 pb-3 flex items-center justify-between">

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          // w-11 h-11 rounded-2xl bg-white shadow-neo-flat-sm p-1 border-white/60
          Container(
            width: 44,
            height: 44,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
              boxShadow: AppTheme.neoFlatSm,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Image.asset('assets/images/logo.png',
                    fit: BoxFit.contain),
              ),
            ),
          ),
          const SizedBox(width: 12), // space-x-3
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // text-[11px] font-semibold text-slate-400 uppercase tracking-wider
                Text(_partOfDay().toUpperCase(),
                    style: _tw(11, 600, Tw.slate400, spacing: 0.55)),
                // text-base font-bold text-slate-800 leading-tight
                Text(_displayName(),
                    style: _tw(16, 700, Tw.slate800, height: 1.25),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          _roundButton(Icons.sync, 'Sync data', _loading ? null : _load),
          const SizedBox(width: 10), // space-x-2.5
          _roundButton(
            Icons.notifications_none_outlined,
            'Notifications',
            _openNotifications,
            dot: _unread > 0,
          ),
        ],
      ),
    );
  }

  // w-10 h-10 rounded-full bg-white shadow-neo-flat-sm text-slate-600
  Widget _roundButton(IconData icon, String tooltip, VoidCallback? onTap,
      {bool dot = false}) {
    return Tooltip(
      message: tooltip,
      child: PressScale(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: AppTheme.neoFlatSm,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(icon, size: 18, color: Tw.slate600),
                  if (dot)
                    Positioned(
                      // top-2.5 right-2.5 w-2 h-2 bg-red-500 border-white
                      top: 10,
                      right: 10,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Tw.red500,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------ check-in card
  // <section class="mt-2 mb-4 bg-white/90 rounded-3xl p-5 shadow-neo-flat
  //   border border-white/80 relative overflow-hidden">

  // The server already narrowed the list to today.
  int get _todayCount => _visitsToday.length;

  Widget _checkInCard() {
    final visits = _todayCount;
    final att = _attendance;
    final checkedIn = att != null;
    final checkedOut = att?['check_out_at'] != null;
    final inAt = DateTime.tryParse(att?['check_in_at']?.toString() ?? '');
    final outAt = DateTime.tryParse(att?['check_out_at']?.toString() ?? '');
    String hm(DateTime? d) =>
        d == null ? '' : DateFormat('hh:mm a').format(d.toLocal());
    final sites = visits == 0
        ? 'No sites marked yet.'
        : '$visits site${visits == 1 ? '' : 's'} marked so far.';
    final statusLine = !checkedIn
        ? 'TODAY: Not checked in yet. Start your day below, then mark each '
            'client site you reach.'
        : checkedOut
            ? 'TODAY: Checked in ${hm(inAt)} - out ${hm(outAt)}. $sites'
            : 'TODAY: Checked in ${hm(inAt)} (${att['kind']}). $sites';
    final dutyLabel = checkedIn && !checkedOut
        ? 'On duty'
        : checkedOut
            ? 'Day closed'
            : 'Off duty';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
        boxShadow: AppTheme.neoFlat,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // absolute -top-10 -right-10 w-36 h-36 bg-sky-100/60 blur-2xl
            // blur-2xl on a 144px circle: painted as a radial fade so there
            // is no hard edge, only the soft pool of light the design has.
            Positioned(
              top: -70,
              right: -70,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Tw.sky100.withValues(alpha: 0.75),
                      Tw.sky100.withValues(alpha: 0.0),
                    ],
                    stops: const [0.25, 1.0],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20), // p-5
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // bg-slate-100/80 px-3 py-1 rounded-full text-xs font-medium text-slate-600
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Tw.slate100.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const LiveDot(color: Tw.emerald500, size: 8),
                            const SizedBox(width: 8),
                            Text(
                              '${DateFormat('hh:mm a').format(_now)} • '
                              '${DateFormat('MMM d, yyyy').format(_now).toUpperCase()}',
                              style: _tw(12, 500, Tw.slate600),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // text-xs text-sky-700 font-semibold bg-sky-50 px-2.5 py-1 border-sky-100/80
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Tw.sky50,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: Tw.sky100.withValues(alpha: 0.8)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                                checkedIn && !checkedOut
                                    ? Icons.location_on_outlined
                                    : Icons.location_off_outlined,
                                size: 12,
                                color: Tw.sky700),
                            const SizedBox(width: 4),
                            Text(dutyLabel, style: _tw(12, 600, Tw.sky700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14), // mt-3.5
                  Text('Field Check-in Status',
                      style: _tw(14, 600, Tw.slate800)),
                  const SizedBox(height: 2),
                  Text(statusLine,
                      style: _tw(12, 400, Tw.slate500, height: 1.625)),
                  const SizedBox(height: 16), // mb-4
                  const SizedBox(height: 4), // pt-1
                  // w-full h-12 rounded-2xl gradient shadow-neo-glow
                  if (!checkedIn)
                    NeoButton(
                      label: 'Check-in for the day',
                      icon: Icons.login,
                      height: 48,
                      onTap: _attendanceAction,
                    )
                  else if (!checkedOut)
                    NeoButton(
                      label: 'Check out',
                      icon: Icons.logout,
                      height: 48,
                      onTap: _attendanceAction,
                    )
                  else
                    Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Tw.slate100,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child:
                          Text('Day closed', style: _tw(14, 600, Tw.slate500)),
                    ),
                  const SizedBox(height: 14), // mt-3.5
                  const SizedBox(height: 4), // pt-1
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _dot(6, Tw.slate300),
                      const SizedBox(width: 6),
                      _dot(6, Tw.sky800, width: 20),
                      const SizedBox(width: 6),
                      _dot(6, Tw.slate300),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(double size, Color color, {double? width}) => Container(
        width: width ?? size,
        height: size,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(999)),
      );

  // ------------------------------------------------- sales overview row
  // <section class="mb-4"> header + pills

  Widget _overview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2), // px-0.5
          child: Row(
            children: [
              Text('Sales Overview',
                  style: _tw(16, 700, Tw.slate800, spacing: -0.4)),
              const SizedBox(width: 8),
              // bg-rose-500 text-white text-[11px] font-bold px-2 py-0.5
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Tw.rose500,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(_leads.length.toString().padLeft(2, '0'),
                    style: _tw(11, 700, Colors.white)),
              ),
              const Spacer(),
              InkWell(
                onTap: _openLeads,
                child: Row(
                  children: [
                    Text('View all', style: _tw(12, 600, Tw.sky700)),
                    const Icon(Icons.chevron_right,
                        size: 14, color: Tw.sky700),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8), // mb-2
        SizedBox(
          height: 44, // py-1 around a py-2 pill
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              _pill('📋', 'All Leads', 'all', active: true),
              const SizedBox(width: 8),
              _pill('🤝', 'Meetings', 'meetings'),
              const SizedBox(width: 8),
              _pill('💼', 'Deals', 'negotiation'),
              const SizedBox(width: 8),
              _pill('📄', 'Proposals', 'proposal'),
              const SizedBox(width: 8),
              _pill('📞', 'Follow-ups', 'followups'),
            ],
          ),
        ),
      ],
    );
  }

  // px-4 py-2 rounded-2xl; active: bg-white shadow-neo-flat-sm text-slate-800
  // semibold border-white; inactive: bg-slate-200/50 text-slate-600 medium
  Widget _pill(String emoji, String label, String filter,
      {bool active = false}) {
    return PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openLeadsFiltered(filter),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: active
                  ? Colors.white
                  : Tw.slate200.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: active ? Border.all(color: Colors.white) : null,
              boxShadow: active ? AppTheme.neoFlatSm : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 6), // space-x-1.5
                Text(label,
                    style: _tw(12, active ? 600 : 500,
                        active ? Tw.slate800 : Tw.slate600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openLeadsFiltered(String filter) async {
    // "Meetings" and "Follow-ups" open the follow-up list, not a lead filter.
    if (filter == 'meetings') {
      return _openFollowUps(kinds: const ['meeting', 'visit']);
    }
    if (filter == 'followups') return _openFollowUps();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LeadsScreen(initialFilter: filter)),
    );
    if (mounted) _load();
  }

  // ------------------------------------------------------- metrics grid
  // <section class="grid grid-cols-2 gap-3.5"> four rounded-3xl p-4 cards

  Widget _metricsGrid(Map<String, dynamic> followups) {
    final overdue = (followups['overdue'] as int?) ?? 0;
    final dueToday = (followups['due_today'] as num?)?.toInt() ?? 0;
    final open = _leads
        .where((l) => const {'new', 'demo', 'negotiation', 'proposal'}
            .contains(l['status']))
        .length;

    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _visitsTodayCard()),
              const SizedBox(width: 14),
              Expanded(child: _myLeadsCard(open)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _dueTodayCard(dueToday)),
              const SizedBox(width: 14),
              Expanded(child: _overdueCard(overdue)),
            ],
          ),
        ),
      ],
    );
  }

  // Card 1 - gradient-to-b #0A4B6E -> #06354F, shadow-neo-glow, border cyan-700/30
  // Today's visits - the stops that count toward travel allowance (#92).
  Widget _visitsTodayCard() {
    return _metricShell(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppTheme.neoBlue, AppTheme.neoBlueDeep],
      ),
      border: Tw.cyan700.withValues(alpha: 0.3),
      shadow: AppTheme.neoGlow,
      top: Row(
        children: [
          // w-9 h-9 rounded-xl bg-white/10 border-white/20
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: const Icon(Icons.storefront_outlined,
                size: 18, color: Colors.white),
          ),
          const Spacer(),
          // text-[10px] uppercase bold tracking-wider bg-cyan-950/60 text-cyan-200 border-cyan-800
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Tw.cyan950.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Tw.cyan800),
            ),
            child: Text('TODAY', style: _tw(10, 700, Tw.cyan200, spacing: 0.5)),
          ),
        ],
      ),
      title: Text('VISITS TODAY',
          style: _tw(12, 700, Colors.white, spacing: 0.3)),
      subtitle: Text('Logged visits',
          style: _tw(10, 400, Tw.cyan200.withValues(alpha: 0.8))),
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              CountUp(
                value: _todayCount.toDouble(),
                format: (v) => '${v.round()}',
                style: _tw(24, 900, Colors.white, spacing: -0.5),
              ),
              const SizedBox(width: 4),
              Text(_todayCount == 1 ? 'visit' : 'visits',
                  style: _tw(12, 400, Tw.cyan200)),
            ],
          ),
          const SizedBox(height: 6),
          Opacity(
            opacity: 0.8,
            child: Row(
              children: [
                _dot(8, Tw.cyan400),
                const SizedBox(width: 6),
                _dot(8, Tw.cyan400.withValues(alpha: 0.4)),
                const SizedBox(width: 6),
                _dot(8, Tw.cyan400.withValues(alpha: 0.4)),
                const SizedBox(width: 6),
                _dot(8, Tw.cyan400.withValues(alpha: 0.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Card 2 - My Leads
  Widget _myLeadsCard(int open) {
    return _metricShell(
      onTap: _openLeads,
      top: Row(
        children: [
          _iconWell(Icons.groups_outlined, Tw.sky50, Tw.sky800),
          const Spacer(),
          _tag('Pipeline', Tw.amber700, Tw.amber50,
              Tw.amber200.withValues(alpha: 0.6)),
        ],
      ),
      title: Text('MY LEADS', style: _tw(12, 700, Tw.slate800, spacing: 0.3)),
      subtitle: Text('$open tasks active', style: _tw(10, 400, Tw.slate400)),
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CountUp(
            value: _leads.length.toDouble(),
            format: (v) => '${v.round()}',
            style: _tw(24, 700, Tw.slate800),
          ),
          const SizedBox(height: 8),
          // w-full py-1.5 rounded-xl bg-slate-100 text-slate-700 semibold 11px
          PressScale(
            child: Material(
              color: Tw.slate100,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _addLead,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  alignment: Alignment.center,
                  child: Text('+ Add Lead', style: _tw(11, 600, Tw.slate700)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Card 3 - Due Today
  Widget _dueTodayCard(int dueToday) {
    return _metricShell(
      onTap: _openFollowUps,
      top: Row(
        children: [
          _iconWell(Icons.event_note_outlined, Tw.sky50, Tw.sky800),
          const Spacer(),
          _tag('Scheduled', Tw.sky700, Tw.sky50, Tw.sky100),
        ],
      ),
      title: Text('DUE TODAY', style: _tw(12, 700, Tw.slate800, spacing: 0.3)),
      subtitle:
          Text('Follow-ups & Meetings', style: _tw(10, 400, Tw.slate400)),
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              CountUp(
                value: dueToday.toDouble(),
                format: (v) => v.round().toString().padLeft(2, '0'),
                style: _tw(24, 700, Tw.slate800),
              ),
              const SizedBox(width: 4),
              Text('calls/visits', style: _tw(11, 400, Tw.slate400)),
            ],
          ),
          const SizedBox(height: 8),
          // h-2 rounded-full bg-slate-100 p-0.5 border-slate-200/50, 3/4 gradient sky-400 -> teal-400
          Container(
            height: 8,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Tw.slate100,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Tw.slate200.withValues(alpha: 0.5)),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: dueToday == 0 ? 0.0 : 0.75,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Tw.sky400, Tw.teal400]),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Card 4 - Overdue
  Widget _overdueCard(int overdue) {
    return _metricShell(
      onTap: _openFollowUps,
      top: Row(
        children: [
          _iconWell(Icons.warning_amber_rounded, Tw.rose50, Tw.rose600),
          const Spacer(),
          _tag(overdue > 0 ? 'Urgent' : 'Clear', Tw.rose600, Tw.rose50,
              Tw.rose100,
              bold: true),
        ],
      ),
      title: Text('OVERDUE', style: _tw(12, 700, Tw.slate800, spacing: 0.3)),
      subtitle: Text('Pending Actions', style: _tw(10, 400, Tw.slate400)),
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              CountUp(
                value: overdue.toDouble(),
                format: (v) => v.round().toString().padLeft(2, '0'),
                style: _tw(24, 700, Tw.rose600),
              ),
              const SizedBox(width: 4),
              Text('tasks', style: _tw(12, 400, Tw.slate400)),
            ],
          ),
          const SizedBox(height: 4),
          // text-[10px] text-slate-500 bg-rose-50/70 p-1.5 rounded-lg border-rose-100/50
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Tw.rose50.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Tw.rose100.withValues(alpha: 0.5)),
            ),
            child: Text(
              overdue > 0
                  ? 'Review overdue client callbacks'
                  : 'Nothing overdue right now',
              style: _tw(10, 400, Tw.slate500, height: 1.25),
            ),
          ),
        ],
      ),
    );
  }

  // rounded-3xl p-4 bg-white/95 shadow-neo-flat border-white min-h-[178px]
  // flex flex-col justify-between
  Widget _metricShell({
    required Widget top,
    required Widget title,
    required Widget subtitle,
    required Widget bottom,
    VoidCallback? onTap,
    Gradient? gradient,
    Color? border,
    List<BoxShadow>? shadow,
  }) {
    return PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            constraints: const BoxConstraints(minHeight: 178),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: gradient == null
                  ? Colors.white.withValues(alpha: 0.95)
                  : null,
              gradient: gradient,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: border ?? Colors.white),
              boxShadow: shadow ?? AppTheme.neoFlat,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                top,
                const SizedBox(height: 12), // mb-3
                title,
                subtitle,
                const Spacer(),
                const SizedBox(height: 12),
                bottom,
              ],
            ),
          ),
        ),
      ),
    );
  }

  // w-9 h-9 rounded-xl bg-sky-50 shadow-neo-pressed text-sky-800
  Widget _iconWell(IconData icon, Color bg, Color fg) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        // The inset "pressed" shadow: a light top-left edge, a dark
        // bottom-right one, painted as borders since Flutter has no inset.
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
          left: BorderSide(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
          bottom: BorderSide(
              color: const Color(0xFFA6B9CE).withValues(alpha: 0.35), width: 1.5),
          right: BorderSide(
              color: const Color(0xFFA6B9CE).withValues(alpha: 0.35), width: 1.5),
        ),
      ),
      child: Icon(icon, size: 18, color: fg),
    );
  }

  // text-[10px] font-semibold px-2 py-0.5 rounded-full border
  Widget _tag(String text, Color fg, Color bg, Color border,
      {bool bold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(text, style: _tw(10, bold ? 700 : 600, fg)),
    );
  }

  // ---------------------------------------------------------------- dock
  // Floating capsule (Add Lead | target) overlapping a white/95 rounded-t-3xl
  // bar with four tabs and the iOS home indicator.

  Widget _dock() {
    final bottom = MediaQuery.paddingOf(context).bottom;
    // The capsule (48 tall) overlaps the dock's top edge by 20px (-mb-5).
    return SizedBox(
      height: 98 + 28 + bottom,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  padding: EdgeInsets.fromLTRB(32, 16, 32, 8 + bottom),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    border: Border(
                        top: BorderSide(
                            color: Tw.slate200.withValues(alpha: 0.8))),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x0F0F172A),
                          offset: Offset(0, -4),
                          blurRadius: 24),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _tab(Icons.home_rounded, 'Home', true, () {}),
                          _tab(Icons.groups_outlined, 'Leads', false,
                              _openLeads),
                          _tab(Icons.storefront_outlined, 'Customers', false,
                              _openCustomers),
                          _tab(Icons.settings_outlined, 'Settings', false,
                              _openSettings),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // w-32 h-1 bg-slate-300 rounded-full
                      Container(
                        width: 128,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: Tw.slate300,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // The capsule: p-1.5 white/90 pill around a 135deg gradient pill.
          Positioned(
            top: 0,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x2E0A4B6E),
                      offset: Offset(0, 8),
                      blurRadius: 20),
                ],
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.neoBlue, AppTheme.neoTeal],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: AppTheme.neoGlow,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PressScale(
                      child: InkWell(
                        onTap: _addLead,
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person_add_alt_1,
                                  size: 16, color: Colors.white),
                              const SizedBox(width: 6),
                              Text('Add Lead',
                                  style: _tw(13, 600, Colors.white,
                                      spacing: 0.2)),
                            ],
                          ),
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
    );
  }

  // active: w-9 h-8 rounded-2xl bg-sky-100/70 text-[#0A4B6E]; label 10px bold
  Widget _tab(IconData icon, String label, bool active, VoidCallback onTap) {
    final color = active ? AppTheme.neoBlue : Tw.slate500;
    return PressScale(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active
                      ? Tw.sky100.withValues(alpha: 0.7)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(height: 4),
              Text(label,
                  style: _tw(10, active ? 700 : 500, color,
                      spacing: active ? -0.2 : 0)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsScreen(me: _me)),
    );
    if (mounted && Api.instance.isLoggedIn) _load();
  }

  /// A Tailwind-flavoured text style: size, weight, colour, optional
  /// letter-spacing and line-height multiplier.
  TextStyle _tw(double size, int weight, Color color,
      {double spacing = 0, double height = 1.3}) {
    return TextStyle(
      fontFamily: 'HankenGrotesk',
      fontSize: size,
      fontWeight: FontWeight.values[(weight ~/ 100) - 1],
      fontVariations: [FontVariation('wght', weight.toDouble())],
      letterSpacing: spacing,
      height: height,
      color: color,
    );
  }

  Widget _errorView(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 36, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: AppTheme.bodyMd.copyWith(color: scheme.onSurface)),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }

  String _displayName() {
    if (_me == null) return 'there';
    final first = (_me!['first_name'] as String?)?.trim() ?? '';
    return first.isNotEmpty ? first : _me!['username'] as String;
  }

  String _partOfDay() {
    final hour = _now.hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }
}
