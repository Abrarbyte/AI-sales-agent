import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';

enum TargetPeriod {
  monthly('monthly', 'Monthly'),
  quarterly('quarterly', 'Quarterly'),
  annual('annual', 'Annual');

  const TargetPeriod(this.wire, this.label);

  final String wire;
  final String label;

  static TargetPeriod fromWire(String? v) => TargetPeriod.values.firstWhere(
        (TargetPeriod p) => p.wire == v,
        orElse: () => TargetPeriod.monthly,
      );
}

/// What a target is measured in. Revenue is the default, but a branch pushing
/// coverage may be measured on visits or new leads instead.
enum TargetMetric {
  revenue('revenue', 'Revenue'),
  leadsWon('leads_won', 'Leads won'),
  visits('visits', 'Visits'),
  newLeads('new_leads', 'New leads');

  const TargetMetric(this.wire, this.label);

  final String wire;
  final String label;

  static TargetMetric fromWire(String? v) => TargetMetric.values.firstWhere(
        (TargetMetric m) => m.wire == v,
        orElse: () => TargetMetric.revenue,
      );

  bool get isCurrency => this == TargetMetric.revenue;
}

/// A quota assigned to one Admin's team for one period.
@immutable
class TargetPlan {
  const TargetPlan({
    required this.id,
    required this.adminId,
    required this.adminName,
    required this.teamName,
    required this.period,
    required this.periodLabel,
    required this.metric,
    required this.targetValue,
    required this.actualValue,
    required this.periodStart,
    required this.periodEnd,
    this.perRepBreakdown = const <String, double>{},
  });

  final String id;
  final String adminId;
  final String adminName;
  final String teamName;
  final TargetPeriod period;

  /// Human label for the period, e.g. "Aug 2026" or "Q3 2026".
  final String periodLabel;
  final TargetMetric metric;
  final double targetValue;
  final double actualValue;
  final DateTime periodStart;
  final DateTime periodEnd;

  /// Optional split of [targetValue] across the team's reps, keyed by rep id.
  /// An Admin with `canEditTargets` may rebalance this but not change the total.
  final Map<String, double> perRepBreakdown;

  /// 0..1+ where 1.0 is exactly on target.
  double get attainment => targetValue == 0 ? 0 : actualValue / targetValue;

  /// Signed distance from target, as a fraction. Drives the diverging bar.
  double get variance => attainment - 1;

  /// Fraction of the period that has elapsed, for the pace comparison.
  double get periodProgress {
    final int total = periodEnd.difference(periodStart).inMinutes;
    if (total <= 0) return 1;
    final int done = DateTime.now().difference(periodStart).inMinutes;
    return (done / total).clamp(0.0, 1.0);
  }

  /// Ahead of the pace needed to land on target by [periodEnd].
  bool get isOnPace => attainment >= periodProgress;

  factory TargetPlan.fromJson(Map<String, dynamic> json) => TargetPlan(
        id: json['id'].toString(),
        adminId: json['admin_id'].toString(),
        adminName: json['admin_name']?.toString() ?? '',
        teamName: json['team_name']?.toString() ?? '',
        period: TargetPeriod.fromWire(json['period']?.toString()),
        periodLabel: json['period_label']?.toString() ?? '',
        metric: TargetMetric.fromWire(json['metric']?.toString()),
        targetValue: (json['target_value'] as num?)?.toDouble() ?? 0,
        actualValue: (json['actual_value'] as num?)?.toDouble() ?? 0,
        periodStart: DateTime.parse(json['period_start'].toString()),
        periodEnd: DateTime.parse(json['period_end'].toString()),
        perRepBreakdown:
            ((json['per_rep_breakdown'] as Map<String, dynamic>?) ??
                    const <String, dynamic>{})
                .map((String k, dynamic v) =>
                    MapEntry<String, double>(k, (v as num).toDouble())),
      );

  Map<String, dynamic> toWriteJson() => <String, dynamic>{
        'admin_id': adminId,
        'period': period.wire,
        'period_label': periodLabel,
        'metric': metric.wire,
        'target_value': targetValue,
        'period_start': periodStart.toIso8601String(),
        'period_end': periodEnd.toIso8601String(),
        if (perRepBreakdown.isNotEmpty) 'per_rep_breakdown': perRepBreakdown,
      };

  TargetPlan copyWith({double? targetValue, TargetMetric? metric}) => TargetPlan(
        id: id,
        adminId: adminId,
        adminName: adminName,
        teamName: teamName,
        period: period,
        periodLabel: periodLabel,
        metric: metric ?? this.metric,
        targetValue: targetValue ?? this.targetValue,
        actualValue: actualValue,
        periodStart: periodStart,
        periodEnd: periodEnd,
        perRepBreakdown: perRepBreakdown,
      );
}

/// How commission is computed.
enum IncentiveBasis {
  percentOfRevenue('percent_of_revenue', 'Percent of revenue'),
  flatPerWonLead('flat_per_won_lead', 'Flat per won lead'),
  tieredOnAttainment('tiered_on_attainment', 'Tiered on attainment'),
  flatPerCompliantVisit('flat_per_compliant_visit', 'Flat per compliant visit');

  const IncentiveBasis(this.wire, this.label);

  final String wire;
  final String label;

  static IncentiveBasis fromWire(String? v) => IncentiveBasis.values.firstWhere(
        (IncentiveBasis b) => b.wire == v,
        orElse: () => IncentiveBasis.percentOfRevenue,
      );
}

/// One tier of a tiered commission rule.
@immutable
class IncentiveTier {
  const IncentiveTier({
    required this.fromAttainment,
    required this.rate,
  });

  /// Lower bound of the band, as attainment (0.8 == 80% of target).
  final double fromAttainment;

  /// Payout rate applied in this band. Percent basis: fraction of revenue.
  final double rate;

  factory IncentiveTier.fromJson(Map<String, dynamic> json) => IncentiveTier(
        fromAttainment: (json['from_attainment'] as num).toDouble(),
        rate: (json['rate'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'from_attainment': fromAttainment,
        'rate': rate,
      };
}

@immutable
class IncentiveRule {
  const IncentiveRule({
    required this.id,
    required this.name,
    required this.basis,
    required this.appliesTo,
    required this.active,
    this.rate = 0,
    this.flatAmount = 0,
    this.tiers = const <IncentiveTier>[],
    this.capAmount,
    this.adminIds = const <String>[],
  });

  final String id;
  final String name;
  final IncentiveBasis basis;

  /// "all_reps" | "all_admins" | "selected_teams"
  final String appliesTo;
  final bool active;

  /// Used when [basis] is percentOfRevenue.
  final double rate;

  /// Used for the flat-amount bases.
  final double flatAmount;

  /// Used when [basis] is tieredOnAttainment, ordered ascending.
  final List<IncentiveTier> tiers;

  /// Optional monthly ceiling per person.
  final double? capAmount;

  /// Populated when [appliesTo] is "selected_teams".
  final List<String> adminIds;

  String get summary {
    switch (basis) {
      case IncentiveBasis.percentOfRevenue:
        return '${(rate * 100).toStringAsFixed(1)}% of closed revenue';
      case IncentiveBasis.flatPerWonLead:
        return 'Flat ${flatAmount.toStringAsFixed(0)} per won lead';
      case IncentiveBasis.flatPerCompliantVisit:
        return 'Flat ${flatAmount.toStringAsFixed(0)} per compliant visit';
      case IncentiveBasis.tieredOnAttainment:
        return '${tiers.length} tiers, '
            '${(tiers.isEmpty ? 0 : tiers.last.rate * 100).toStringAsFixed(1)}% top rate';
    }
  }

  factory IncentiveRule.fromJson(Map<String, dynamic> json) => IncentiveRule(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? '',
        basis: IncentiveBasis.fromWire(json['basis']?.toString()),
        appliesTo: json['applies_to']?.toString() ?? 'all_reps',
        active: json['active'] as bool? ?? true,
        rate: (json['rate'] as num?)?.toDouble() ?? 0,
        flatAmount: (json['flat_amount'] as num?)?.toDouble() ?? 0,
        tiers: ((json['tiers'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) =>
                IncentiveTier.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        capAmount: (json['cap_amount'] as num?)?.toDouble(),
        adminIds: ((json['admin_ids'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) => e.toString())
            .toList(growable: false),
      );

  Map<String, dynamic> toWriteJson() => <String, dynamic>{
        'name': name,
        'basis': basis.wire,
        'applies_to': appliesTo,
        'active': active,
        'rate': rate,
        'flat_amount': flatAmount,
        'tiers': tiers.map((IncentiveTier t) => t.toJson()).toList(),
        if (capAmount != null) 'cap_amount': capAmount,
        if (adminIds.isNotEmpty) 'admin_ids': adminIds,
      };
}

enum PayoutStatus {
  pending('pending', 'Pending approval'),
  approved('approved', 'Approved'),
  rejected('rejected', 'Rejected'),
  paid('paid', 'Paid');

  const PayoutStatus(this.wire, this.label);

  final String wire;
  final String label;

  static PayoutStatus fromWire(String? v) => PayoutStatus.values.firstWhere(
        (PayoutStatus s) => s.wire == v,
        orElse: () => PayoutStatus.pending,
      );

  Color get color {
    switch (this) {
      case PayoutStatus.approved:
      case PayoutStatus.paid:
        return VizPalette.statusGood;
      case PayoutStatus.pending:
        return VizPalette.statusWarning;
      case PayoutStatus.rejected:
        return VizPalette.statusCritical;
    }
  }

  IconData get icon {
    switch (this) {
      case PayoutStatus.approved:
        return Icons.check_circle_outline;
      case PayoutStatus.paid:
        return Icons.payments_outlined;
      case PayoutStatus.pending:
        return Icons.hourglass_empty;
      case PayoutStatus.rejected:
        return Icons.cancel_outlined;
    }
  }
}

/// A computed payout awaiting a Super Admin's sign-off.
@immutable
class IncentivePayout {
  const IncentivePayout({
    required this.id,
    required this.personId,
    required this.personName,
    required this.personRole,
    required this.teamName,
    required this.adminId,
    required this.ruleName,
    required this.periodLabel,
    required this.amount,
    required this.status,
    required this.computedAt,
    this.attainment = 0,
    this.note,
  });

  final String id;
  final String personId;
  final String personName;

  /// "admin" | "sales_rep"
  final String personRole;
  final String teamName;
  final String adminId;
  final String ruleName;
  final String periodLabel;
  final double amount;
  final PayoutStatus status;
  final DateTime computedAt;
  final double attainment;
  final String? note;

  factory IncentivePayout.fromJson(Map<String, dynamic> json) =>
      IncentivePayout(
        id: json['id'].toString(),
        personId: json['person_id'].toString(),
        personName: json['person_name']?.toString() ?? '',
        personRole: json['person_role']?.toString() ?? 'sales_rep',
        teamName: json['team_name']?.toString() ?? '',
        adminId: json['admin_id']?.toString() ?? '',
        ruleName: json['rule_name']?.toString() ?? '',
        periodLabel: json['period_label']?.toString() ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        status: PayoutStatus.fromWire(json['status']?.toString()),
        computedAt: DateTime.parse(json['computed_at'].toString()),
        attainment: (json['attainment'] as num?)?.toDouble() ?? 0,
        note: json['note']?.toString(),
      );
}
