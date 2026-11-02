import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/activity.dart';
import '../../data/models/lead.dart';
import '../../data/models/common.dart';
import '../../data/providers.dart';
import '../../data/repositories/company_repository.dart';
import '../../widgets/async_gate.dart';
import '../../widgets/charts/earnings_chart.dart';
import '../../widgets/motion.dart';
import '../shell/console_shell.dart';
import 'dashboard_role_cards.dart';
import 'design_tokens.dart';

/// The dashboard, built card-for-card from the "Modern CRM Dashboard"
/// design with the sales data in its slots:
///
///   Total Revenue / Active Deals / Win Rate / Avg Deal Size
///       -> Revenue booked / Open leads / Win rate / Avg deal size
///   Earning Summary (this period vs the one before)
///       -> revenue closed per day, this window vs the previous window
///   Deal Sources   -> where this window's leads came from
///   Recent Deals   -> the latest conversions
///
/// Everything is computed from the leads already loaded, against the window
/// picked in the header, so the figures and their deltas are real
/// comparisons rather than server placeholders.
///
/// Each role gets its own dashboard ([DashboardRole]). The figures are always
/// the signed-in account's own - the server scopes every list to the people
/// they may see - but what is worth a glance differs: the Super Admin runs
/// the company, an Admin runs the branch's people, a Manager runs one team.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int days = ref.watch(dashboardDaysProvider);
    return AsyncGate<SignedInUser>(
      value: ref.watch(currentUserProvider),
      onRetry: () => ref.invalidate(currentUserProvider),
      loadingHeight: 480,
      data: (SignedInUser me) => AsyncGate<CompanySnapshot>(
        value: ref.watch(companyProvider),
        onRetry: () => ref.invalidate(companyProvider),
        loadingHeight: 480,
        data: (CompanySnapshot co) => _Dashboard(
          role: DashboardRole.of(me),
          co: co,
          stats: _Stats.compute(co, days: days),
          days: days,
        ),
      ),
    );
  }
}

/// Whose dashboard to show. Anyone else who reaches the console (it refuses
/// employees) is shown the Admin one.
enum DashboardRole {
  superAdmin('Company overview', 'Every team and branch, for the Super Admin.'),
  admin('Branch overview', "Your branch's reps and pipeline."),
  manager('My team', 'Your team only - their leads, visits and follow-ups.');

  const DashboardRole(this.title, this.subtitle);

  final String title;
  final String subtitle;

  static DashboardRole of(SignedInUser me) => me.isSuperAdmin
      ? DashboardRole.superAdmin
      : (me.isManager ? DashboardRole.manager : DashboardRole.admin);
}

/// One window of the pipeline, and the same-length window before it.
class _Stats {
  const _Stats({
    required this.revenue,
    required this.revenueBefore,
    required this.wonCount,
    required this.wonBefore,
    required this.newLeads,
    required this.newLeadsBefore,
    required this.openLeads,
    required this.winRate,
    required this.winRateBefore,
    required this.avgDeal,
    required this.avgDealBefore,
    required this.revenueByDay,
    required this.revenueByDayBefore,
    required this.sources,
    required this.recentWins,
    required this.wonInWindow,
  });

  final double revenue;
  final double revenueBefore;
  final int wonCount;
  final int wonBefore;
  final int newLeads;
  final int newLeadsBefore;
  final int openLeads;
  final double winRate;
  final double winRateBefore;
  final double avgDeal;
  final double avgDealBefore;
  final List<TrendPoint> revenueByDay;
  final List<TrendPoint> revenueByDayBefore;

  /// Source label -> share of this window's new leads, largest first.
  final List<(String, int)> sources;
  final List<Lead> recentWins;

  /// The leads won inside the window, for the per-rep and per-team cards.
  final List<Lead> wonInWindow;

  static _Stats compute(CompanySnapshot co, {required int days}) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime start = today.subtract(Duration(days: days - 1));
    final DateTime prevStart = start.subtract(Duration(days: days));

    bool inWindow(DateTime? d, DateTime from, DateTime toExclusive) =>
        d != null && !d.isBefore(from) && d.isBefore(toExclusive);

    final List<Lead> won = co.leads
        .where((Lead l) => l.stageKind == LeadStageKind.won)
        .toList();
    DateTime closedAt(Lead l) => l.convertedAt ?? l.updatedAt;

    final List<Lead> wonNow = won
        .where((Lead l) => inWindow(closedAt(l), start, today.add(const Duration(days: 1))))
        .toList();
    final List<Lead> wonBefore = won
        .where((Lead l) => inWindow(closedAt(l), prevStart, start))
        .toList();
    double sum(List<Lead> ls) => ls.fold<double>(0, (double s, Lead l) => s + l.value);

    final List<Lead> createdNow = co.leads
        .where((Lead l) => inWindow(l.createdAt, start, today.add(const Duration(days: 1))))
        .toList();
    final List<Lead> createdBefore = co.leads
        .where((Lead l) => inWindow(l.createdAt, prevStart, start))
        .toList();

    // Win rate: of leads that reached a decision in the window, how many
    // were won. Lost = closed stage; decided-at is the last update.
    double rate(DateTime from, DateTime toExcl) {
      final List<Lead> decided = co.leads
          .where(
            (Lead l) =>
                l.stageKind != LeadStageKind.open &&
                inWindow(l.stageKind == LeadStageKind.won ? closedAt(l) : l.updatedAt, from, toExcl),
          )
          .toList();
      if (decided.isEmpty) return 0;
      return decided.where((Lead l) => l.stageKind == LeadStageKind.won).length /
          decided.length;
    }

    List<TrendPoint> perDay(List<Lead> ls, DateTime from) => <TrendPoint>[
      for (int i = 0; i < days; i++)
        TrendPoint(
          date: from.add(Duration(days: i)),
          value: ls
              .where((Lead l) {
                final DateTime d = closedAt(l);
                final DateTime day = from.add(Duration(days: i));
                return d.year == day.year && d.month == day.month && d.day == day.day;
              })
              .fold<double>(0, (double s, Lead l) => s + l.value),
        ),
    ];

    final Map<String, int> bySource = <String, int>{};
    for (final Lead l in createdNow) {
      final String s = l.source.isEmpty ? 'Other' : l.source;
      bySource[s] = (bySource[s] ?? 0) + 1;
    }
    final List<(String, int)> sources = bySource.entries
        .map((MapEntry<String, int> e) => (e.key, e.value))
        .toList()
      ..sort(((String, int) a, (String, int) b) => b.$2.compareTo(a.$2));

    final List<Lead> recent = List<Lead>.of(won)
      ..sort((Lead a, Lead b) => closedAt(b).compareTo(closedAt(a)));

    return _Stats(
      revenue: sum(wonNow),
      revenueBefore: sum(wonBefore),
      wonCount: wonNow.length,
      wonBefore: wonBefore.length,
      newLeads: createdNow.length,
      newLeadsBefore: createdBefore.length,
      openLeads: co.leads.where((Lead l) => l.isOpen).length,
      winRate: rate(start, today.add(const Duration(days: 1))),
      winRateBefore: rate(prevStart, start),
      avgDeal: wonNow.isEmpty ? 0 : sum(wonNow) / wonNow.length,
      avgDealBefore: wonBefore.isEmpty ? 0 : sum(wonBefore) / wonBefore.length,
      revenueByDay: perDay(wonNow, start),
      revenueByDayBefore: perDay(wonBefore, prevStart),
      sources: sources.take(5).toList(),
      recentWins: recent.take(5).toList(),
      wonInWindow: wonNow,
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.role,
    required this.co,
    required this.stats,
    required this.days,
  });

  final DashboardRole role;
  final CompanySnapshot co;
  final _Stats stats;
  final int days;

  @override
  Widget build(BuildContext context) {
    final _Stats s = stats;
    final List<Widget> kpis = <Widget>[
      _Kpi(
        label: role == DashboardRole.manager ? 'Team revenue' : 'Revenue booked',
        icon: Icons.currency_rupee,
        value: s.revenue,
        format: Fmt.money,
        delta: _pctChange(s.revenue, s.revenueBefore),
        note: 'vs previous $days days',
      ),
      _Kpi(
        label: 'Open leads',
        icon: Icons.work_outline,
        value: s.openLeads.toDouble(),
        format: (double v) => Fmt.count(v.round()),
        delta: s.newLeads.toDouble(),
        deltaLabel: '+${s.newLeads}',
        note: 'new in $days days',
      ),
      _Kpi(
        label: 'Win rate',
        icon: Icons.pie_chart_outline,
        value: s.winRate * 100,
        format: (double v) => Fmt.pct(v, decimals: 0),
        delta: (s.winRate - s.winRateBefore) * 100,
        deltaLabel: _pts((s.winRate - s.winRateBefore) * 100),
        note: 'vs previous $days days',
      ),
      if (role == DashboardRole.manager)
        _overdueKpi()
      else
        _Kpi(
          label: 'Avg deal size',
          icon: Icons.trending_up,
          value: s.avgDeal,
          format: Fmt.money,
          delta: _pctChange(s.avgDeal, s.avgDealBefore),
          note: 'vs previous $days days',
        ),
    ];

    final Widget sources = _SourcesCard(stats: s, days: days);
    final Widget recent = _RecentDealsCard(stats: s);
    final Widget topReps = TopRepsCard(won: s.wonInWindow, days: days);
    final Widget today = TodayCard(co: co);

    final List<Widget> sections = switch (role) {
      DashboardRole.superAdmin => <Widget>[
          _EarningsCard(stats: s, days: days),
          TeamsCard(co: co, won: s.wonInWindow, days: days),
          _pair(sources, recent),
        ],
      DashboardRole.admin => <Widget>[
          _EarningsCard(stats: s, days: days),
          _pair(topReps, today),
          _pair(sources, recent),
        ],
      DashboardRole.manager => <Widget>[
          _pair(today, FollowUpsDueCard(co: co)),
          _pair(topReps, recent),
        ],
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24), // p-6
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280), // max-w-7xl
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(role.title, style: Ds.h1),
              const SizedBox(height: 4),
              Text(role.subtitle, style: Ds.t12(Ds.slate500)),
              const SizedBox(height: 20),
              // grid-cols-4 gap-4
              Reveal(
                index: 0,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) {
                    final int cols = c.maxWidth >= 1024 ? 4 : (c.maxWidth >= 640 ? 2 : 1);
                    final double w = (c.maxWidth - 16 * (cols - 1)) / cols;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: <Widget>[
                        for (final Widget k in kpis) SizedBox(width: w, child: k),
                      ],
                    );
                  },
                ),
              ),
              for (int i = 0; i < sections.length; i++) ...<Widget>[
                const SizedBox(height: 24), // space-y-6
                Reveal(index: i + 1, child: sections[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// A manager's fourth figure: follow-ups their team has let slip.
  _Kpi _overdueKpi() {
    final int overdue =
        co.followUps.where((FollowUp f) => f.isPending && f.isOverdue).length;
    return _Kpi(
      label: 'Overdue follow-ups',
      icon: Icons.alarm,
      value: overdue.toDouble(),
      format: (double v) => Fmt.count(v.round()),
      // Fewer is better, so any overdue shows as a red chip, never green.
      delta: -overdue.toDouble(),
      deltaLabel: overdue == 0 ? 'none' : '$overdue late',
      note: overdue == 0 ? 'all caught up' : 'past their due time',
    );
  }

  /// Two cards side by side, stacked when narrow.
  static Widget _pair(Widget a, Widget b) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          if (c.maxWidth < 900) {
            return Column(children: <Widget>[a, const SizedBox(height: 24), b]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: a),
              const SizedBox(width: 24),
              Expanded(child: b),
            ],
          );
        },
      );

  /// The change as a fraction (1.0 = doubled), or null when there is nothing
  /// to compare against. A fraction because that is what
  /// [Fmt.signedPercent] formats; this used to return a percentage, which
  /// it then multiplied by 100 again (#80).
  static double? _pctChange(double now, double before) {
    if (before == 0) return now == 0 ? 0 : null;
    return (now - before) / before;
  }

  static String _pts(double d) =>
      '${d >= 0 ? '+' : ''}${d.toStringAsFixed(1)} pts';
}

/// bg-white p-5 rounded-2xl: label + glyph, the figure, a delta chip and
/// its caption.
class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.label,
    required this.icon,
    required this.value,
    required this.format,
    required this.delta,
    required this.note,
    this.deltaLabel,
  });

  final String label;
  final IconData icon;
  final double value;
  final String Function(double) format;

  /// Signed change; null means "no earlier period to compare".
  final double? delta;
  final String? deltaLabel;
  final String note;

  @override
  Widget build(BuildContext context) {
    final double? d = delta;
    return DsCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(label, style: Ds.t12(Ds.slate500, w: 500))),
              Icon(icon, size: 16, color: Ds.slate400),
            ],
          ),
          const SizedBox(height: 12),
          CountUp(value: value, format: format, style: Ds.figure),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              if (d == null)
                DsDeltaChip(label: 'new', sign: 0)
              else
                DsDeltaChip(
                  label: deltaLabel ?? Fmt.signedPercent(d, decimals: 1),
                  sign: d > 0 ? 1 : (d < 0 ? -1 : 0),
                ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  d == null ? 'nothing in the previous period' : note,
                  overflow: TextOverflow.ellipsis,
                  style: Ds.t11(Ds.slate400),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Earning Summary": revenue closed per day, this window against the
/// window before it.
class _EarningsCard extends StatelessWidget {
  const _EarningsCard({required this.stats, required this.days});

  final _Stats stats;
  final int days;

  @override
  Widget build(BuildContext context) {
    final DateTime from = stats.revenueByDay.first.date;
    final DateTime to = stats.revenueByDay.last.date;
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('Earning summary', style: Ds.h3),
                  const SizedBox(width: 12),
                  Text(
                    '${Fmt.dateShort(from)} - ${Fmt.dateShort(to)}',
                    style: Ds.t12(Ds.slate500),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _LegendDot(color: Ds.brand500, label: 'Last $days days', strong: true),
                  const SizedBox(width: 20),
                  _LegendDot(color: Ds.slate300, label: 'Previous $days days'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          EarningsChart(
            current: stats.revenueByDay,
            previous: stats.revenueByDayBefore,
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label, this.strong = false});

  final Color color;
  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: Ds.t12(strong ? Ds.slate700 : Ds.slate500, w: 500)),
      ],
    );
  }
}

/// "Deal Sources": where this window's leads came from, as share bars.
class _SourcesCard extends StatelessWidget {
  const _SourcesCard({required this.stats, required this.days});

  final _Stats stats;
  final int days;

  static const List<Color> _ramp = <Color>[
    Ds.brand500,
    Ds.brand500,
    Ds.brand400,
    Ds.brand300,
    Ds.brand200,
  ];

  static IconData _iconFor(String source) => switch (source.toLowerCase()) {
    'our website' => Icons.language,
    'social media' => Icons.share_outlined,
    'referral' => Icons.people_outline,
    'existing client' => Icons.verified_outlined,
    'phone call' => Icons.call_outlined,
    'whatsapp' => Icons.chat_bubble_outline,
    'google' => Icons.search,
    'cold visit' => Icons.directions_walk,
    _ => Icons.circle_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final int total = stats.sources.fold<int>(0, (int s, (String, int) e) => s + e.$2);
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text('Lead sources', style: Ds.h3)),
              Text('last $days days', style: Ds.t11(Ds.slate400)),
            ],
          ),
          const SizedBox(height: 20),
          if (stats.sources.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No leads were added in this period.',
                style: Ds.t12(Ds.slate400),
              ),
            )
          else
            for (int i = 0; i < stats.sources.length; i++) ...<Widget>[
              _SourceRow(
                icon: _iconFor(stats.sources[i].$1),
                label: stats.sources[i].$1,
                share: total == 0 ? 0 : stats.sources[i].$2 / total,
                color: _ramp[i.clamp(0, _ramp.length - 1)],
              ),
              if (i < stats.sources.length - 1) const SizedBox(height: 16),
            ],
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.icon,
    required this.label,
    required this.share,
    required this.color,
  });

  final IconData icon;
  final String label;
  final double share;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 128,
          child: Row(
            children: <Widget>[
              Icon(icon, size: 15, color: Ds.slate400),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: Ds.t12(Ds.slate700, w: 500),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 8,
              color: Ds.track,
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: share),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (BuildContext context, double v, _) => FractionallySizedBox(
                  widthFactor: v.clamp(0, 1),
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 36,
          child: Text(
            Fmt.pct(share * 100, decimals: 0),
            textAlign: TextAlign.right,
            style: Ds.t12(Ds.slate600, w: 600),
          ),
        ),
      ],
    );
  }
}

/// "Recent Deals": the latest conversions, newest first.
class _RecentDealsCard extends StatelessWidget {
  const _RecentDealsCard({required this.stats});

  final _Stats stats;

  static const List<(Color, Color, Color)> _tiles = <(Color, Color, Color)>[
    (Ds.indigo50, Ds.indigo100, Ds.indigo600),
    (Ds.brand50, Ds.brand100, Ds.brand600),
    (Ds.amber50, Ds.amber100, Ds.amber600),
  ];

  static String _when(DateTime d) {
    final DateTime now = DateTime.now();
    final DateTime day = DateTime(d.year, d.month, d.day);
    final int diff = DateTime(now.year, now.month, now.day).difference(day).inDays;
    if (diff <= 0) return 'Closed today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '$diff days ago';
    return Fmt.date(d);
  }

  @override
  Widget build(BuildContext context) {
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text('Recent deals', style: Ds.h3)),
              InkWell(
                onTap: () => openSection.value = NavSection.customers,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text('View all', style: Ds.t12(Ds.brand600, w: 600)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (stats.recentWins.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('No deals closed yet.', style: Ds.t12(Ds.slate400)),
            )
          else
            for (int i = 0; i < stats.recentWins.length; i++)
              _DealRow(
                lead: stats.recentWins[i],
                tile: _tiles[i % _tiles.length],
                when: _when(stats.recentWins[i].convertedAt ?? stats.recentWins[i].updatedAt),
                first: i == 0,
              ),
        ],
      ),
    );
  }
}

class _DealRow extends StatelessWidget {
  const _DealRow({
    required this.lead,
    required this.tile,
    required this.when,
    required this.first,
  });

  final Lead lead;
  final (Color, Color, Color) tile;
  final String when;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final String name = lead.companyName.isEmpty ? lead.contactName : lead.companyName;
    return HoverRow(
      onTap: () => openSection.value = NavSection.customers,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          border: first
              ? null
              : const Border(top: BorderSide(color: Ds.borderSoft)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tile.$1,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: tile.$2),
              ),
              child: Text(
                name.isEmpty ? '?' : name[0].toUpperCase(),
                style: Ds.t12(tile.$3, w: 700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: Ds.t12(Ds.slate800, w: 600),
                  ),
                  Text(
                    '$when - ${lead.repName}',
                    overflow: TextOverflow.ellipsis,
                    style: Ds.t11(Ds.slate400),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(Fmt.money(lead.value), style: Ds.t12(Ds.slate800, w: 700)),
          ],
        ),
      ),
    );
  }
}

/// Kept so the header/other screens can still refer to the KPI layout's
/// spacing constants if they need to.
const double kDashboardGutter = AppSpacing.xl;
