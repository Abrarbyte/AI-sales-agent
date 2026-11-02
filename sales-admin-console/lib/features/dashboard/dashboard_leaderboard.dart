import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/company_profile.dart';
import '../../data/providers.dart';
import '../../data/repositories/company_repository.dart';
import '../../data/models/analytics.dart';
import '../../data/models/common.dart';
import '../../data/models/people.dart';
import '../../widgets/charts/mini_charts.dart';
import 'dashboard_panels.dart';

/// Rep leaderboard for the single Demand Generation team.
///
/// API: GET /super/dashboard/leaderboard?scope=reps&metric=revenue
///   200 { "items": [ { "id": "rep_2", "name": "Aditi Patil",
///                      "subtitle": "Demand Generation - Pune HQ",
///                      "value": 61400.0, "rank": 1,
///                      "entity_index": 1, "previous_rank": 2,
///                      "secondary_value": 34 } ] }
///
/// `entity_index` is the rep's stable colour slot. It must NOT be the rank -
/// colour follows the person, so re-sorting by a different metric reorders the
/// rows without repainting them.
class LeaderboardPanel extends ConsumerWidget {
  const LeaderboardPanel({
    super.key,
    required this.entries,
    required this.metric,
    required this.onMetric,
    required this.onOpenRep,
  });

  final List<LeaderboardEntry> entries;
  final LeaderboardMetric metric;
  final ValueChanged<LeaderboardMetric> onMetric;
  final ValueChanged<String> onOpenRep;

  String _format(double v) {
    if (metric.isCurrency) return Fmt.moneyCompact(v);
    if (metric.isRatio) return Fmt.percent(v);
    return Fmt.count(v);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CompanySnapshot? co = ref.watch(companyProvider).valueOrNull;

    double maxValue = 0;
    for (final LeaderboardEntry e in entries) {
      if (e.value > maxValue) maxValue = e.value;
    }

    return Panel(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelHeader(
            title: 'Rep leaderboard',
            subtitle: Text(
              '${entries.length} active reps in ${CompanyProfile.teamName}',
            ),
            trailing: PillDropdown<LeaderboardMetric>(
              value: metric,
              items: LeaderboardMetric.values,
              labelOf: (LeaderboardMetric m) => m.label,
              onChanged: onMetric,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double tableWidth = constraints.maxWidth > _minTableWidth
                  ? constraints.maxWidth
                  : _minTableWidth;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _HeaderRow(metricLabel: metric.label),
                      for (final LeaderboardEntry e in entries)
                        _RepRow(
                          entry: e,
                          valueLabel: _format(e.value),
                          maxValue: maxValue,
                          rep: co?.repById(e.id),
                          onOpen: () => onOpenRep(e.id),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

const List<double> _cols = <double>[56, 210, 128, 108, 110, 108];

/// Sum of [_cols] - the table never compresses below this; it stretches
/// to fill anything wider and scrolls horizontally below it.
const double _minTableWidth = 720;

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.metricLabel});

  final String metricLabel;

  @override
  Widget build(BuildContext context) {
    final TextStyle? style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: VizPalette.inkMuted, letterSpacing: 0.5);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: _cols[0],
            child: Text('RANK', style: style),
          ),
          SizedBox(
            width: _cols[1],
            child: Text('SALES REP', style: style),
          ),
          SizedBox(
            width: _cols[2],
            child: Text('LEADS', style: style),
          ),
          SizedBox(
            width: _cols[3],
            child: Text('STATUS', style: style),
          ),
          SizedBox(
            width: _cols[4],
            child: Text(metricLabel.toUpperCase(), style: style),
          ),
          SizedBox(width: _cols[5], child: const SizedBox.shrink()),
        ],
      ),
    );
  }
}

class _RepRow extends StatelessWidget {
  const _RepRow({
    required this.entry,
    required this.valueLabel,
    required this.maxValue,
    required this.rep,
    required this.onOpen,
  });

  final LeaderboardEntry entry;
  final String valueLabel;
  final double maxValue;
  final SalesRep? rep;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ChartTheme chart = context.chart;
    final Color color = chart.seriesFor(entry.entityIndex);
    final EntityStatus status = rep?.status ?? EntityStatus.active;

    return Container(
      height: AppSpacing.tableRowHeight,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: <Widget>[
          // Rank. The movement arrows were removed: previousRank is never
          // populated - nothing stores a prior ranking - so rankDelta was
          // always null and no arrow ever rendered.
          SizedBox(
            width: _cols[0],
            child: Row(
              children: <Widget>[
                Text(
                  '#${entry.rank}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontFeatures: kTabularFigures,
                  ),
                ),
              ],
            ),
          ),

          // Rep, with their stable colour on the avatar - identity is never
          // colour alone, the name sits right beside it.
          SizedBox(
            width: _cols[1],
            child: Row(
              children: <Widget>[
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    Fmt.initials(entry.name),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontSize: 9.5,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        entry.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      Text(
                        rep?.email ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: VizPalette.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SizedBox(
            width: _cols[2],
            child: Text(
              '${rep?.wonLeads ?? 0} / ${rep?.assignedLeads ?? 0}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: kTabularFigures,
              ),
            ),
          ),

          SizedBox(
            width: _cols[3],
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: status.color.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(status.icon, size: 11, color: status.color),
                    const SizedBox(width: 4),
                    Text(
                      status.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: status.color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Value with an inline meter - the bar makes the ranking scannable
          // without making the reader compare numbers across rows.
          SizedBox(
            width: _cols[4],
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  valueLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontFeatures: kTabularFigures,
                  ),
                ),
                const SizedBox(height: 5),
                SizedBox(
                  width: 84,
                  child: MeterBar(
                    fraction: maxValue == 0 ? 0 : entry.value / maxValue,
                    color: color,
                    height: 4,
                    showOverflow: false,
                  ),
                ),
              ],
            ),
          ),

          SizedBox(
            width: _cols[5],
            child: Align(
              alignment: Alignment.centerLeft,
              child: PillButton(label: 'View', onTap: onOpen),
            ),
          ),
        ],
      ),
    );
  }
}
