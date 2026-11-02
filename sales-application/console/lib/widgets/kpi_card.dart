import 'package:flutter/material.dart';

import '../core/theme/app_palette.dart';
import '../core/theme/app_theme.dart';
import 'charts/mini_charts.dart';
import 'primitives.dart';

/// A stat tile: the headline number, its change, and the shape of the trend.
///
/// This is the right form for a single current value - a one-bar bar chart
/// would carry the same information with far more ink. The number IS the chart;
/// the sparkline is supporting context, which is why it has no axes.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.delta,
    this.higherIsBetter = true,
    this.trend,
    this.footnote,
    this.icon,
    this.accent,
    this.onTap,
  });

  final String label;

  /// Pre-formatted. Proportional figures - tabular digits make a large number
  /// look loose at display size.
  final String value;

  /// Fractional change vs the previous window. Null hides the delta row.
  final double? delta;
  final bool higherIsBetter;

  final List<double>? trend;
  final String? footnote;
  final IconData? icon;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ChartTheme chart = context.chart;
    final Color color = accent ?? chart.series.first;

    final Widget content = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: VizPalette.inkMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: theme.textTheme.headlineMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (delta != null || footnote != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: <Widget>[
                if (delta != null)
                  MetricDelta(value: delta!, higherIsBetter: higherIsBetter),
                if (delta != null && footnote != null)
                  const SizedBox(width: AppSpacing.sm),
                if (footnote != null)
                  Flexible(
                    child: Text(
                      footnote!,
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ],
          if (trend != null && trend!.length > 1) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Sparkline(values: trend!, color: color),
          ],
        ],
      ),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, child: content),
    );
  }
}

/// A callout tile for work waiting on the Super Admin - pending proof reviews,
/// unapproved payouts. Visually distinct from a KPI so it does not read as
/// "another number".
class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.count,
    required this.label,
    required this.actionLabel,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final int count;
  final String label;
  final String actionLabel;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '$count $label',
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(actionLabel, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: VizPalette.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}
