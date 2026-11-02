import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// The "Orders Management" table design: a dark charcoal panel on the
/// light page. Every data table in the console sits in one of these, so
/// the tokens live here and the tables only pick column widths.
class Dt {
  const Dt._();

  static const Color bg = Color(0xFF0C0D0E); // brandDark.bg
  static const Color panel = Color(0xFF111214); // brandDark.panel
  static const Color hover = Color(0xFF18191C); // brandDark.hover
  static const Color border = Color(0xFF232529); // brandDark.border
  static const Color borderLight = Color(0xFF2C2E35);
  static const Color textPrimary = Color(0xFFEDEDED);
  static const Color textSecondary = Color(0xFF8E929B);
  static const Color textMuted = Color(0xFF5B5F67);

  /// Pipeline stage colours, from the Orders design's pill tints: one hue
  /// per stage that reads on both the charcoal panel and the light page.
  static Color stage(String stageId) => switch (stageId) {
    'new' => textSecondary,
    'assigned' => const Color(0xFFE0A944), // amber pill text
    'demo' => const Color(0xFFBDA2FF), // purple pill text
    'negotiation' => const Color(0xFFC084FC),
    'proposal' => const Color(0xFF4E82EA), // VISA blue
    'converted' => const Color(0xFF78D49A), // fulfilled green
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

  /// The dark theme the panel's contents render with: every table cell,
  /// chip and expanded drawer picks its ink from here, so a table can sit
  /// on the light page without each widget knowing.
  static ThemeData theme(BuildContext context) {
    final ThemeData dark = AppTheme.dark();
    return dark.copyWith(
      scaffoldBackgroundColor: panel,
      canvasColor: panel,
      dividerColor: border.withValues(alpha: 0.7),
      dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 1),
      hoverColor: hover,
      colorScheme: dark.colorScheme.copyWith(
        surface: panel,
        onSurface: textPrimary,
        onSurfaceVariant: textSecondary,
        surfaceContainer: hover,
        surfaceContainerHigh: hover,
        surfaceContainerHighest: borderLight,
        outline: textSecondary,
        outlineVariant: border,
      ),
      textTheme: dark.textTheme.apply(
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
          border: Border.all(color: Dt.border.withValues(alpha: 0.6)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
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
