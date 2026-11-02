import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/dashboard/design_tokens.dart';

/// The table panel every data screen sits in: a white card on the page
/// ground, in the Modern CRM design's slate palette. The tokens live here
/// and the tables only pick column widths.
///
/// These were charcoal, from the Orders design. The console around them is
/// light, and two grounds in one window never settled - so the panel now
/// matches the page rather than cutting a dark hole in it.
class Dt {
  const Dt._();

  static const Color bg = Ds.page;
  static const Color panel = Ds.card; // white
  static const Color hover = Ds.control; // slate-50
  static const Color border = Ds.border; // slate-200
  static const Color borderLight = Ds.borderSoft; // slate-100
  static const Color textPrimary = Ds.slate900;
  static const Color textSecondary = Ds.slate500;
  static const Color textMuted = Ds.slate400;

  /// Pipeline stage colours. One hue per stage, at the 600 weight so each
  /// reads as text on white - the lighter tints these replaced were chosen
  /// to carry on charcoal and turn illegible here.
  static Color stage(String stageId) => switch (stageId) {
    'new' => textSecondary,
    'demo' => const Color(0xFF7C3AED), // violet-600
    'negotiation' => const Color(0xFF9333EA), // purple-600
    'proposal' => const Color(0xFF2563EB), // blue-600
    'converted' => const Color(0xFF059669), // emerald-600
    'closed' => textMuted,
    _ => textSecondary,
  };

  /// thead: text-[13px] font-normal, secondary grey.
  static const TextStyle head = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    height: 1.3,
  );

  /// The theme the panel's contents render with: every table cell, chip and
  /// expanded drawer picks its ink from here, so no table widget has to know
  /// what it is sitting on.
  static ThemeData theme(BuildContext context) {
    final ThemeData base = AppTheme.light();
    return base.copyWith(
      scaffoldBackgroundColor: panel,
      canvasColor: panel,
      dividerColor: border.withValues(alpha: 0.7),
      dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 1),
      hoverColor: hover,
      colorScheme: base.colorScheme.copyWith(
        surface: panel,
        onSurface: textPrimary,
        onSurfaceVariant: textSecondary,
        surfaceContainer: hover,
        surfaceContainerHigh: hover,
        surfaceContainerHighest: borderLight,
        outline: textSecondary,
        outlineVariant: border,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
    );
  }
}

/// bg-[#111214] border border-[#232529]/60 rounded-xl overflow-hidden, with
/// the dark theme applied to everything inside.
/// Marks the subtree inside a [TablePanel], so a nested TablePanel or
/// [Panel] renders as plain padding instead of a second box.
class TablePanelScope extends InheritedWidget {
  const TablePanelScope({super.key, required super.child});

  static bool isInside(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TablePanelScope>() != null;

  @override
  bool updateShouldNotify(TablePanelScope oldWidget) => false;
}

/// One charcoal block: the filters on top (px-5 py-3, hairline below, like
/// the Orders design's toolbar) and the table or empty state beneath, so
/// the dark surface reads as one component rather than a table under a
/// white toolbar.
class DataBlock extends StatelessWidget {
  const DataBlock({super.key, required this.children});

  /// First child is the toolbar; the rest is the body.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return TablePanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (children.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Dt.border.withValues(alpha: 0.7)),
                ),
              ),
              child: children.first,
            ),
          ...children.skip(1),
        ],
      ),
    );
  }
}

class TablePanel extends StatelessWidget {
  const TablePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.sm,
    ),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (TablePanelScope.isInside(context)) {
      return Padding(padding: padding, child: child);
    }
    return Theme(
      data: Dt.theme(context),
      child: TablePanelScope(
        child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Dt.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Dt.border.withValues(alpha: 0.8)),
          // The heavy drop shadow belonged to a dark panel lifted off a
          // light page. A white card on a near-white page needs a hairline.
          boxShadow: Ds.shadow2xs,
        ),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Dt.textPrimary),
          child: child,
        ),
      ),
      ),
    );
  }
}
