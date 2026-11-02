import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// The three layout modes the console renders in.
///
/// * [compact]  - phone / narrow window. Sidebar becomes a modal drawer,
///                data tables collapse into stacked cards.
/// * [medium]   - tablet portrait and small laptop. Icon-only sidebar rail,
///                tables scroll horizontally with a reduced column set.
/// * [expanded] - tablet landscape and desktop. Full sidebar with labels, the
///                complete column set, multi-column dashboards.
enum LayoutSize { compact, medium, expanded }

extension LayoutSizeX on LayoutSize {
  bool get isCompact => this == LayoutSize.compact;
  bool get isMedium => this == LayoutSize.medium;
  bool get isExpanded => this == LayoutSize.expanded;

  /// True when the sidebar is shown inline rather than as a modal drawer.
  bool get hasInlineSidebar => this != LayoutSize.compact;

  /// True when sidebar entries show their label next to the icon.
  bool get hasSidebarLabels => this == LayoutSize.expanded;
}

class Responsive {
  const Responsive._();

  static LayoutSize of(BuildContext context) =>
      sizeFor(MediaQuery.sizeOf(context).width);

  static LayoutSize sizeFor(double width) {
    if (width < AppBreakpoints.compact) return LayoutSize.compact;
    if (width < AppBreakpoints.expanded) return LayoutSize.medium;
    return LayoutSize.expanded;
  }

  /// How many KPI tiles fit on one row at this width.
  static int kpiColumns(double width) {
    if (width < 560) return 1;
    if (width < 860) return 2;
    if (width < 1180) return 3;
    if (width < 1560) return 4;
    return 5;
  }

  /// Page padding. Tighter on tablets so the data gets the pixels.
  static EdgeInsets pagePadding(LayoutSize size) {
    switch (size) {
      case LayoutSize.compact:
        return const EdgeInsets.all(AppSpacing.lg);
      case LayoutSize.medium:
        return const EdgeInsets.all(AppSpacing.lg);
      case LayoutSize.expanded:
        return const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xl,
        );
    }
  }
}

/// Rebuilds its child whenever the layout mode changes.
class LayoutBuilderScope extends StatelessWidget {
  const LayoutBuilderScope({super.key, required this.builder});

  final Widget Function(BuildContext context, LayoutSize size) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) =>
          builder(context, Responsive.sizeFor(constraints.maxWidth)),
    );
  }
}
