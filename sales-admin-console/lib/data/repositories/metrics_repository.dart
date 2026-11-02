import '../../core/utils/formatters.dart';
import '../api/api_client.dart';
import '../models/analytics.dart';
import '../models/common.dart';
import '../models/lead.dart';
import '../models/ops.dart';
import '../api/mappers.dart';
import '../models/people.dart';
import 'company_repository.dart';

/// The dashboard's headline figures.
///
/// `GET /api/analytics/dashboard/` already computes most of this server-side,
/// so it is the source for the counts. What it does not carry is anything
/// historical: there are no period-over-period deltas and no daily series, both
/// of which the console's KPI tiles want. Deltas are reported as zero, and the
/// sparkline series are built from the one history the API does expose -
/// `GET /api/analytics/reports/`, the nightly DailyReport rows.
class MetricsRepository {
  MetricsRepository(this._api);

  final ApiClient _api;

  /// [snapshot] supplies the people counts, which the dashboard endpoint gives
  /// only as a team total - the console shows admins and reps separately.
  Future<KpiSnapshot> kpis(CompanySnapshot snapshot, {int days = 14}) async {
    final List<dynamic> responses = await Future.wait(<Future<dynamic>>[
      _api.get('/api/analytics/dashboard/', <String, dynamic>{'days': days}),
      _api.getList('/api/analytics/reports/', <String, dynamic>{
        'from': Fmt.apiDate(DateTime.now().subtract(Duration(days: days - 1))),
        'to': Fmt.apiDate(DateTime.now()),
      }),
    ]);

    final Map<String, dynamic> dash =
        (responses[0] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final List<Map<String, dynamic>> reports =
        responses[1] as List<Map<String, dynamic>>;

    final Map<String, dynamic> pipeline =
        (dash['pipeline'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<String, dynamic> visits =
        (dash['visits'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<String, dynamic> followups =
        (dash['followups'] as Map<String, dynamic>?) ?? <String, dynamic>{};

    final int totalLeads = snapshot.leads.length;

    // Weighted pipeline: each open lead at its stage's close probability.
    // The backend has no forecast figure, so this is computed from the leads
    // already loaded rather than guessed at.
    double weighted = 0;
    for (final Lead lead in snapshot.leads) {
      if (lead.stageKind != LeadStageKind.open) continue;
      weighted += lead.value * _probabilityFor(lead.stageId);
    }

    final double revenue = snapshot.leads
        .where((Lead l) => l.stageKind == LeadStageKind.won)
        .fold(0, (double s, Lead l) => s + l.value);

    return KpiSnapshot(
      totalLeads: totalLeads,
      visitsToday: (visits['today'] as num?)?.toInt() ?? 0,
      activeAdmins: snapshot.admins
          .where((AdminUser a) => a.status == EntityStatus.active)
          .length,
      totalAdmins: snapshot.admins.length,
      activeReps: snapshot.activeReps.length,
      totalReps: snapshot.reps.length,
      conversionRate: ((pipeline['win_rate'] as num?)?.toDouble() ?? 0) / 100.0,
      pipelineValue: weighted,
      revenueThisPeriod: revenue,
      leadsTrend: _series(
        reports,
        (Map<String, dynamic> r) =>
            ((r['leads_created'] as num?) ?? 0).toDouble(),
      ),
      visitsTrend: _series(
        reports,
        (Map<String, dynamic> r) =>
            ((r['visits_count'] as num?) ?? 0).toDouble(),
      ),
      conversionTrend: _series(reports, (Map<String, dynamic> r) {
        final double created = ((r['leads_created'] as num?) ?? 0).toDouble();
        final double leadsWon = ((r['leads_won'] as num?) ?? 0).toDouble();
        return created == 0 ? 0 : leadsWon / created * 100;
      }),
      // No per-day revenue is recorded anywhere, so the revenue sparkline
      // tracks won leads per day instead of currency.
      revenueTrend: _series(
        reports,
        (Map<String, dynamic> r) => ((r['leads_won'] as num?) ?? 0).toDouble(),
      ),
      // Overdue follow-ups are the closest thing the backend has to an item
      // demanding attention; there is no visit-proof queue.
      pendingProofCount: (followups['overdue'] as num?)?.toInt() ?? 0,
      // No incentive or payout model exists.
      pendingPayoutCount: 0,
      // The dashboard endpoint returns no comparison window, so every delta is
      // reported as flat rather than fabricated.
      totalLeadsDelta: 0,
      visitsTodayDelta: 0,
      conversionRateDelta: 0,
      generatedAt: DateTime.now(),
    );
  }

  /// Close probability per backend lead status. Mirrors `Mappers.fixedStages`.
  double _probabilityFor(String stageId) {
    final PipelineStage stage = Mappers.stageFor(stageId);
    return stage.kind == LeadStageKind.open ? stage.probability : 0;
  }

  /// Collapses DailyReport rows into one point per day, newest last.
  ///
  /// Reports are per user per day, so the same date appears once per person -
  /// the values are summed, giving a company-wide series.
  List<TrendPoint> _series(
    List<Map<String, dynamic>> reports,
    double Function(Map<String, dynamic>) value, {
    int days = 14,
  }) {
    final Map<DateTime, double> byDay = <DateTime, double>{};
    for (final Map<String, dynamic> row in reports) {
      final DateTime? date = DateTime.tryParse(row['date']?.toString() ?? '');
      if (date == null) continue;
      final DateTime key = DateTime(date.year, date.month, date.day);
      byDay[key] = (byDay[key] ?? 0) + value(row);
    }

    final List<DateTime> dates = byDay.keys.toList()..sort();
    final List<DateTime> window = dates.length <= days
        ? dates
        : dates.sublist(dates.length - days);

    return window
        .map((DateTime d) => TrendPoint(date: d, value: byDay[d]!))
        .toList(growable: false);
  }

  /// Ranked reps, built from the roster already loaded.
  ///
  /// [entityIndex] is the rep's canonical slot, never their rank, so switching
  /// metric re-orders the rows without recolouring them.
  List<LeaderboardEntry> repLeaderboard(
    CompanySnapshot snapshot,
    LeaderboardMetric metric, {
    int? limit,
    bool activeOnly = true,
  }) {
    final List<SalesRep> reps =
        (activeOnly ? snapshot.activeReps : snapshot.reps).toList();

    double valueOf(SalesRep r) {
      switch (metric) {
        case LeaderboardMetric.revenue:
          return r.revenueThisPeriod;
        case LeaderboardMetric.leadsWon:
          return r.wonLeads.toDouble();
        case LeaderboardMetric.conversion:
          return r.conversionRate;
        case LeaderboardMetric.visits:
          return r.visitsThisMonth.toDouble();
      }
    }

    reps.sort((SalesRep a, SalesRep b) => valueOf(b).compareTo(valueOf(a)));
    final List<SalesRep> ranked = limit == null
        ? reps
        : reps.take(limit).toList();

    return List<LeaderboardEntry>.generate(ranked.length, (int i) {
      final SalesRep r = ranked[i];
      return LeaderboardEntry(
        id: r.id,
        name: r.name,
        subtitle: '${r.teamName} - ${r.branch}',
        value: valueOf(r),
        rank: i + 1,
        entityIndex: snapshot.entityIndexOfRep(r.id),
        // Nothing records what the ranking was yesterday, so no movement can
        // be shown. Equal to `rank` means "unchanged" to the row widget.
        previousRank: i + 1,
        secondaryValue: r.assignedLeads.toDouble(),
      );
    });
  }

  /// Recent activity, as far as the backend can describe it.
  ///
  /// There is no audit log: nothing records reassignments, config edits or
  /// approvals. What can be shown honestly is recent CRM movement, derived
  /// from the leads already loaded.
  List<ActivityItem> recentActivity(CompanySnapshot snapshot, {int limit = 8}) {
    final List<Lead> recent = snapshot.leads.toList()
      ..sort((Lead a, Lead b) => b.updatedAt.compareTo(a.updatedAt));

    return recent
        .take(limit)
        .map((Lead lead) {
          final String what = switch (lead.stageKind) {
            LeadStageKind.won => 'Converted ${lead.companyName}',
            LeadStageKind.lost => 'Closed ${lead.companyName}',
            LeadStageKind.open =>
              'Moved ${lead.companyName} to ${lead.stageName}',
          };
          return ActivityItem(
            id: 'lead_${lead.id}',
            at: lead.updatedAt,
            actorName: lead.repName,
            actorRole: 'sales_rep',
            typeWire: 'lead_change',
            summary: what,
          );
        })
        .toList(growable: false);
  }
}
