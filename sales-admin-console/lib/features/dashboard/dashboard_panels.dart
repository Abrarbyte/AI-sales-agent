import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/motion.dart';
import '../../widgets/table_panel.dart';

/// Rounded panel used across the dashboard. Matches the reference's cards:
/// generous radius, hairline border, no elevation.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.gradient,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsets padding;
  final Gradient? gradient;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    // Inside a charcoal DataBlock the toolbar is part of the block: no
    // second box, just its padding.
    if (TablePanelScope.isInside(context)) {
      return Padding(padding: padding, child: child);
    }
    final ThemeData theme = Theme.of(context);
    final bool light = theme.brightness == Brightness.light;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? theme.colorScheme.surface : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: borderColor ?? theme.dividerColor),
        // shadow-2xs on the light design; flat on dark.
        boxShadow: light
            ? const <BoxShadow>[
                BoxShadow(
                  color: Color(0x0D000000),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

/// Panel header: title, optional supporting line, optional trailing control.
class PanelHeader extends StatelessWidget {
  const PanelHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final Widget? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 3),
                DefaultTextStyle.merge(
                  style: theme.textTheme.bodySmall ?? const TextStyle(),
                  child: subtitle!,
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Rounded dropdown used in panel headers ("All sources", "USD").
class PillDropdown<T> extends StatelessWidget {
  const PillDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // The design's "Last 30 Days" control: slate-50, rounded-lg.
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.light
            ? theme.colorScheme.surfaceContainer
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          icon: Icon(Icons.expand_more, size: 17, color: VizPalette.inkMuted),
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
          dropdownColor: theme.colorScheme.surface,
          style: theme.textTheme.labelMedium,
          items: items
              .map(
                (T i) => DropdownMenuItem<T>(value: i, child: Text(labelOf(i))),
              )
              .toList(),
          onChanged: (T? v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// Segmented period switch (24h / Week / Month) as in the reference's
/// Overview card.
class PeriodSegments extends StatelessWidget {
  const PeriodSegments({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<String> options;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Container(
      height: 38,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? VizPalette.raisedDark : VizPalette.raisedLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: options.map((String o) {
          final bool on = o == selected;
          return Expanded(
            child: InkWell(
              onTap: () => onChanged(o),
              borderRadius: BorderRadius.circular(9),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? theme.colorScheme.surface : null,
                  borderRadius: BorderRadius.circular(9),
                  border: on ? Border.all(color: theme.dividerColor) : null,
                ),
                child: Text(
                  o,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: on
                        ? theme.colorScheme.onSurface
                        : VizPalette.inkMuted,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Overlapping avatar bubbles with a "+N" overflow chip, as in the reference's
/// campaign rows.
class AvatarStack extends StatelessWidget {
  const AvatarStack({
    super.key,
    required this.names,
    this.max = 4,
    this.size = 26,
    this.tint,
  });

  final List<String> names;
  final int max;
  final double size;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color base = tint ?? theme.colorScheme.primary;
    final List<String> shown = names.take(max).toList();
    final int extra = names.length - shown.length;
    final double overlap = size * 0.32;

    return SizedBox(
      height: size,
      width: shown.isEmpty
          ? 0
          : size +
                (shown.length - 1) * (size - overlap) +
                (extra > 0 ? size - overlap : 0),
      child: Stack(
        children: <Widget>[
          for (int i = 0; i < shown.length; i++)
            Positioned(
              left: i * (size - overlap),
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: base.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  // Ring in the surface colour separates overlapping bubbles.
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 2,
                  ),
                ),
                child: Text(
                  Fmt.initials(shown[i]),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: base,
                    fontSize: size * 0.34,
                  ),
                ),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * (size - overlap),
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? VizPalette.raisedDark
                      : VizPalette.raisedLight,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 2,
                  ),
                ),
                child: Text(
                  '+$extra',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: VizPalette.inkMuted,
                    fontSize: size * 0.30,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small pill button used at the end of leaderboard rows.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color fg = filled
        ? (isDark ? VizPalette.planeDark : Colors.white)
        : theme.colorScheme.onSurface;

    return PressScale(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled
                ? (isDark ? Colors.white : VizPalette.inkPrimaryLight)
                : (isDark ? VizPalette.raisedDark : VizPalette.raisedLight),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: filled ? Colors.transparent : theme.dividerColor,
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: fg),
          ),
        ),
      ),
    );
  }
}
