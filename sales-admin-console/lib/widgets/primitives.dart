import 'package:flutter/material.dart';

import '../core/theme/app_palette.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';

/// A state pill. Colour NEVER carries the meaning on its own - every chip ships
/// an icon and a label, which is what makes the reserved status palette safe
/// for colour-blind readers and in forced-colours mode.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    required this.icon,
    this.dense = false,
  });

  final String label;
  final Color color;
  final IconData icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final TextStyle? style = dense
        ? Theme.of(context).textTheme.labelSmall
        : Theme.of(context).textTheme.labelMedium;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusChip),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: dense ? 12 : 14, color: color),
          const SizedBox(width: 5),
          Text(label, style: style?.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// The standard content container: hairline border, no elevation, optional
/// title row with trailing actions.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.actions,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.titlePadding,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final List<Widget>? actions;
  final EdgeInsets padding;
  final EdgeInsets? titlePadding;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasHeader = title != null || (actions?.isNotEmpty ?? false);

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (hasHeader)
            Padding(
              padding: titlePadding ??
                  const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.sm,
                  ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (title != null)
                          Text(title!, style: theme.textTheme.titleSmall),
                        if (subtitle != null) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(subtitle!, style: theme.textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                  if (actions != null) ...actions!,
                ],
              ),
            ),
          if (hasHeader) Divider(color: theme.dividerColor, height: 1),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// Signed change indicator for a KPI tile.
///
/// The arrow plus the sign carry the direction; the colour only reinforces it.
/// [higherIsBetter] is false for figures like "leads gone stale", where a rise
/// is bad news.
class MetricDelta extends StatelessWidget {
  const MetricDelta({
    super.key,
    required this.value,
    this.higherIsBetter = true,
    this.suffix,
  });

  final double value;
  final bool higherIsBetter;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final ChartTheme chart = context.chart;
    final ThemeData theme = Theme.of(context);

    if (value.abs() < 0.0005) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.remove, size: 14, color: chart.inkMuted),
          const SizedBox(width: 3),
          Text(
            'no change',
            style: theme.textTheme.bodySmall?.copyWith(color: chart.inkMuted),
          ),
        ],
      );
    }

    final bool up = value > 0;
    final bool good = up == higherIsBetter;
    final Color color = good ? chart.successText : VizPalette.statusCritical;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          up ? Icons.arrow_upward : Icons.arrow_downward,
          size: 13,
          color: color,
        ),
        const SizedBox(width: 2),
        Text(
          Fmt.signedPercent(value),
          style: theme.textTheme.labelMedium?.copyWith(
            color: color,
            fontFeatures: kTabularFigures,
          ),
        ),
        if (suffix != null) ...<Widget>[
          const SizedBox(width: 4),
          Text(suffix!, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

/// Initials bubble. Avoids a network avatar request per row in a long table.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.name,
    this.size = 30,
    this.entityIndex,
  });

  final String name;
  final double size;

  /// When given, tints the bubble with that entity's stable series colour so a
  /// team reads consistently across the directory and the charts.
  final int? entityIndex;

  @override
  Widget build(BuildContext context) {
    final ChartTheme chart = context.chart;
    final Color base = entityIndex == null
        ? chart.inkMuted
        : chart.seriesFor(entityIndex!);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: base.withValues(alpha: 0.3)),
      ),
      child: Text(
        Fmt.initials(name),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: base,
              fontSize: size * 0.38,
            ),
      ),
    );
  }
}

/// Shown when a filtered list comes back empty. Always offers the way out.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 30, color: VizPalette.inkMuted),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: theme.textTheme.titleSmall),
            if (message != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline error with a retry, used wherever a repository call can fail.
class ErrorNotice extends StatelessWidget {
  const ErrorNotice({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.error_outline,
              size: 28,
              color: VizPalette.statusCritical,
            ),
            const SizedBox(height: AppSpacing.md),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Page heading used at the top of every section.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: AppSpacing.md,
        spacing: AppSpacing.lg,
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(title, style: theme.textTheme.headlineSmall),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 3),
                Text(subtitle!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
          if (actions.isNotEmpty)
            Wrap(
              spacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
        ],
      ),
    );
  }
}
