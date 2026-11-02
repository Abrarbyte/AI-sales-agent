import 'package:flutter/foundation.dart';

import 'common.dart';

/// Company-wide headline numbers for the dashboard's KPI row.
///
/// Every figure carries its own comparison against the previous equivalent
/// window so a tile can show a delta without a second request.
@immutable
class KpiSnapshot {
  const KpiSnapshot({
    required this.totalLeads,
    required this.totalLeadsDelta,
    required this.visitsToday,
    required this.visitsTodayDelta,
    required this.activeAdmins,
    required this.totalAdmins,
    required this.activeReps,
    required this.totalReps,
    required this.conversionRate,
    required this.conversionRateDelta,
    required this.pipelineValue,
    required this.revenueThisPeriod,
    required this.leadsTrend,
    required this.visitsTrend,
    required this.conversionTrend,
    required this.revenueTrend,
    required this.pendingProofCount,
    required this.pendingPayoutCount,
    required this.generatedAt,
  });

  final int totalLeads;

  /// Fractional change vs the previous window, e.g. 0.124 == +12.4%.
  final double totalLeadsDelta;

  final int visitsToday;
  final double visitsTodayDelta;

  final int activeAdmins;
  final int totalAdmins;
  final int activeReps;
  final int totalReps;

  /// 0..1
  final double conversionRate;
  final double conversionRateDelta;

  final double pipelineValue;
  final double revenueThisPeriod;

  /// Sparkline series for the tiles. Short - 14 points is plenty at tile size.
  final List<TrendPoint> leadsTrend;
  final List<TrendPoint> visitsTrend;
  final List<TrendPoint> conversionTrend;
  final List<TrendPoint> revenueTrend;

  /// Action counts that drive the "needs you" callouts.
  final int pendingProofCount;
  final int pendingPayoutCount;

  final DateTime generatedAt;

  factory KpiSnapshot.fromJson(Map<String, dynamic> json) {
    List<TrendPoint> trend(String key) =>
        ((json[key] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) => TrendPoint.fromJson(e as Map<String, dynamic>))
            .toList(growable: false);

    return KpiSnapshot(
      totalLeads: (json['total_leads'] as num?)?.toInt() ?? 0,
      totalLeadsDelta: (json['total_leads_delta'] as num?)?.toDouble() ?? 0,
      visitsToday: (json['visits_today'] as num?)?.toInt() ?? 0,
      visitsTodayDelta: (json['visits_today_delta'] as num?)?.toDouble() ?? 0,
      activeAdmins: (json['active_admins'] as num?)?.toInt() ?? 0,
      totalAdmins: (json['total_admins'] as num?)?.toInt() ?? 0,
      activeReps: (json['active_reps'] as num?)?.toInt() ?? 0,
      totalReps: (json['total_reps'] as num?)?.toInt() ?? 0,
      conversionRate: (json['conversion_rate'] as num?)?.toDouble() ?? 0,
      conversionRateDelta:
          (json['conversion_rate_delta'] as num?)?.toDouble() ?? 0,
      pipelineValue: (json['pipeline_value'] as num?)?.toDouble() ?? 0,
      revenueThisPeriod:
          (json['revenue_this_period'] as num?)?.toDouble() ?? 0,
      leadsTrend: trend('leads_trend'),
      visitsTrend: trend('visits_trend'),
      conversionTrend: trend('conversion_trend'),
      revenueTrend: trend('revenue_trend'),
      pendingProofCount: (json['pending_proof_count'] as num?)?.toInt() ?? 0,
      pendingPayoutCount: (json['pending_payout_count'] as num?)?.toInt() ?? 0,
      generatedAt: DateTime.parse(json['generated_at'].toString()),
    );
  }
}

/// What a leaderboard row is ranked on.
enum LeaderboardMetric {
  revenue('revenue', 'Revenue'),
  leadsWon('leads_won', 'Leads won'),
  conversion('conversion', 'Conversion rate'),
  visits('visits', 'Visits');

  const LeaderboardMetric(this.wire, this.label);

  final String wire;
  final String label;

  bool get isCurrency => this == LeaderboardMetric.revenue;

  bool get isRatio => this == LeaderboardMetric.conversion;
}

/// Whether the board ranks whole teams or individual reps.
enum LeaderboardScope {
  teams('teams', 'Teams'),
  reps('reps', 'Reps');

  const LeaderboardScope(this.wire, this.label);

  final String wire;
  final String label;
}

@immutable
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.value,
    required this.rank,
    required this.entityIndex,
    this.previousRank,
    this.secondaryValue,
  });

  final String id;
  final String name;

  /// Team name for a rep row, branch for a team row.
  final String subtitle;
  final double value;
  final int rank;

  /// Stable index into the canonical entity list.
  ///
  /// The leaderboard sorts by [value], but colour must follow the ENTITY, not
  /// the row position - otherwise changing the metric repaints every bar and a
  /// reader who learned "Coastal is orange" is misled. Charts pass this, never
  /// [rank], to `ChartTheme.seriesFor`.
  final int entityIndex;

  final int? previousRank;

  /// Optional supporting figure shown beside the bar, e.g. deal count.
  final double? secondaryValue;

  /// Positive when the entry climbed since the previous period.
  int? get rankDelta => previousRank == null ? null : previousRank! - rank;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      LeaderboardEntry(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? '',
        subtitle: json['subtitle']?.toString() ?? '',
        value: (json['value'] as num?)?.toDouble() ?? 0,
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        entityIndex: (json['entity_index'] as num?)?.toInt() ?? 0,
        previousRank: (json['previous_rank'] as num?)?.toInt(),
        secondaryValue: (json['secondary_value'] as num?)?.toDouble(),
      );
}

/// One item in the dashboard's recent-activity feed (an audit-log preview).
@immutable
class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.at,
    required this.actorName,
    required this.actorRole,
    required this.summary,
    required this.typeWire,
  });

  final String id;
  final DateTime at;
  final String actorName;
  final String actorRole;
  final String summary;

  /// Matches `AuditActionType.wire`, so the feed and the full log share icons.
  final String typeWire;

  factory ActivityItem.fromJson(Map<String, dynamic> json) => ActivityItem(
        id: json['id'].toString(),
        at: DateTime.parse(json['at'].toString()),
        actorName: json['actor_name']?.toString() ?? '',
        actorRole: json['actor_role']?.toString() ?? '',
        summary: json['summary']?.toString() ?? '',
        typeWire: json['type']?.toString() ?? '',
      );
}

/// One stage of the conversion funnel.
@immutable
class FunnelStageStat {
  const FunnelStageStat({
    required this.stageId,
    required this.stageName,
    required this.order,
    required this.count,
    required this.value,
  });

  final String stageId;
  final String stageName;
  final int order;
  final int count;
  final double value;

  factory FunnelStageStat.fromJson(Map<String, dynamic> json) =>
      FunnelStageStat(
        stageId: json['stage_id'].toString(),
        stageName: json['stage_name']?.toString() ?? '',
        order: (json['order'] as num?)?.toInt() ?? 0,
        count: (json['count'] as num?)?.toInt() ?? 0,
        value: (json['value'] as num?)?.toDouble() ?? 0,
      );
}

/// Everything the Reports screen renders for one filter selection.
@immutable
class ReportBundle {
  const ReportBundle({
    required this.range,
    required this.revenueTrend,
    required this.leadsCreatedTrend,
    required this.funnel,
    required this.visitCompliance,
    required this.sourceMix,
    required this.teamRows,
    required this.totalRevenue,
    required this.totalLeads,
    required this.totalVisits,
    required this.overallConversion,
    required this.overallCompliance,
  });

  final DateRange range;

  /// Two named series so the trend chart can label them directly.
  final List<TrendPoint> revenueTrend;
  final List<TrendPoint> leadsCreatedTrend;
  final List<FunnelStageStat> funnel;

  /// Per-team visit-compliance rate, 0..1.
  final List<TeamMetricRow> visitCompliance;

  /// Lead volume by source, for the stacked share bar.
  final List<CategoryShare> sourceMix;

  /// The table-view twin of the charts above - every chart's numbers are
  /// reachable without reading colour.
  final List<TeamMetricRow> teamRows;

  final double totalRevenue;
  final int totalLeads;
  final int totalVisits;
  final double overallConversion;
  final double overallCompliance;
}

@immutable
class TeamMetricRow {
  const TeamMetricRow({
    required this.adminId,
    required this.teamName,
    required this.adminName,
    required this.entityIndex,
    required this.revenue,
    required this.leads,
    required this.wonLeads,
    required this.visits,
    required this.compliantVisits,
    required this.target,
  });

  final String adminId;
  final String teamName;
  final String adminName;

  /// Stable colour index. See [LeaderboardEntry.entityIndex].
  final int entityIndex;

  final double revenue;
  final int leads;
  final int wonLeads;
  final int visits;
  final int compliantVisits;
  final double target;

  double get conversion => leads == 0 ? 0 : wonLeads / leads;

  double get compliance => visits == 0 ? 0 : compliantVisits / visits;

  double get attainment => target == 0 ? 0 : revenue / target;
}

@immutable
class CategoryShare {
  const CategoryShare({
    required this.label,
    required this.value,
    required this.entityIndex,
  });

  final String label;
  final double value;
  final int entityIndex;
}
