import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Layout constants. The console is data-dense, so the spacing scale is tight
/// and deliberately small-stepped: 4/8/12/16/24/32.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Corner radius for cards, inputs and chips. Kept modest - a big radius
  /// reads consumer, not admin.
  static const double radiusCard = 16;
  static const double radiusControl = 12;
  static const double radiusChip = 9;

  /// Width of the expanded sidebar and of its collapsed (icon-only) form.
  static const double sidebarExpanded = 246;
  static const double sidebarCollapsed = 64;

  /// Height of the persistent top bar.
  static const double topBarHeight = 68;

  /// Standard height of a data-table row. Dense on purpose.
  static const double tableRowHeight = 52;
  static const double tableHeaderHeight = 48;
}

/// Breakpoints. Tablet is a first-class target: field managers open this on a
/// 10-13" tablet in landscape, which lands in [medium] or [expanded].
class AppBreakpoints {
  const AppBreakpoints._();

  /// Below this the sidebar becomes a modal drawer.
  static const double compact = 900;

  /// At or above this the sidebar is fully expanded with labels; between
  /// [compact] and this it is a collapsed icon rail.
  static const double expanded = 1280;
}

/// Numerals that must line up vertically (table cells, axis ticks, KPI deltas).
/// Never applied to a hero figure - equal-width digits make large numbers look
/// loose.
const List<FontFeature> kTabularFigures = <FontFeature>[
  FontFeature.tabularFigures(),
];

class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    final Color plane = isDark ? VizPalette.planeDark : VizPalette.planeLight;
    final Color surface = isDark
        ? VizPalette.surfaceDark
        : VizPalette.surfaceLight;
    final Color inkPrimary = isDark
        ? VizPalette.inkPrimaryDark
        : VizPalette.inkPrimaryLight;
    final Color inkSecondary = isDark
        ? VizPalette.inkSecondaryDark
        : VizPalette.inkSecondaryLight;
    final Color border = isDark
        ? VizPalette.borderDark
        : VizPalette.borderLight;
    final Color raised = isDark
        ? VizPalette.raisedDark
        : VizPalette.raisedLight;
    // One blue accent for figures and selection. The explicit scheme keeps
    // Material from tinting surfaces toward it.
    const Color accent = VizPalette.accent;
    const Color onAccent = Colors.white;
    // Primary buttons carry the brand: emerald with white text on light,
    // white pills on dark.
    final Color buttonFill = isDark ? Colors.white : accent;
    final Color onButton = isDark ? VizPalette.planeDark : Colors.white;

    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      primaryContainer: raised,
      onPrimaryContainer: inkPrimary,
      secondary: inkSecondary,
      onSecondary: onAccent,
      secondaryContainer: raised,
      onSecondaryContainer: inkPrimary,
      tertiary: inkSecondary,
      onTertiary: onAccent,
      error: VizPalette.statusCritical,
      onError: Colors.white,
      surface: surface,
      onSurface: inkPrimary,
      surfaceContainerLowest: plane,
      surfaceContainerLow: plane,
      surfaceContainer: raised,
      surfaceContainerHigh: raised,
      surfaceContainerHighest: raised,
      onSurfaceVariant: inkSecondary,
      outline: inkSecondary,
      outlineVariant: border,
      shadow: Colors.transparent,
      scrim: Colors.black54,
      inverseSurface: inkPrimary,
      onInverseSurface: surface,
      inversePrimary: onAccent,
      surfaceTint: Colors.transparent,
    );

    final TextTheme text = _textTheme(inkPrimary, inkSecondary);

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Inter',
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: plane,
      canvasColor: plane,
      textTheme: text,
      // Compact density: this is an admin console, not a phone app.
      visualDensity: VisualDensity.compact,
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          side: BorderSide(color: border),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: inkPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: AppSpacing.topBarHeight,
        titleTextStyle: text.titleMedium,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: raised,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: text.bodyMedium?.copyWith(color: VizPalette.inkMuted),
        labelStyle: text.bodyMedium?.copyWith(color: inkSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: VizPalette.statusCritical),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: buttonFill,
          foregroundColor: onButton,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: inkPrimary,
          backgroundColor: isDark ? raised : surface,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: text.labelLarge,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: raised,
        side: BorderSide(color: border),
        labelStyle: text.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusChip),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowHeight: AppSpacing.tableHeaderHeight,
        dataRowMinHeight: AppSpacing.tableRowHeight,
        dataRowMaxHeight: AppSpacing.tableRowHeight,
        horizontalMargin: AppSpacing.lg,
        columnSpacing: AppSpacing.xl,
        dividerThickness: 1,
        headingTextStyle: text.labelSmall?.copyWith(
          color: inkSecondary,
          letterSpacing: 0.4,
        ),
        dataTextStyle: text.bodyMedium,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? VizPalette.raisedDark : VizPalette.inkPrimaryLight,
          borderRadius: BorderRadius.circular(AppSpacing.radiusChip),
        ),
        textStyle: text.bodySmall?.copyWith(color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        waitDuration: const Duration(milliseconds: 400),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          side: BorderSide(color: border),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> s) =>
              s.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> s) =>
              s.contains(WidgetState.selected) ? accent : null,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? VizPalette.raisedDark
            : VizPalette.inkPrimaryLight,
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(8),
        radius: const Radius.circular(4),
        thumbColor: WidgetStateProperty.all(
          isDark ? VizPalette.raisedDark : VizPalette.axisLight,
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[
        isDark ? ChartTheme.dark : ChartTheme.light,
      ],
    );
  }

  /// One sans family throughout, including the hero figures. A display or serif
  /// face on a KPI number reads as off-brand decoration.
  static TextTheme _textTheme(Color primary, Color secondary) {
    const List<String> fallback = <String>[
      'Segoe UI',
      'Roboto',
      'Helvetica Neue',
      'Arial',
    ];

    TextStyle s(
      double size,
      FontWeight weight, {
      Color? color,
      double? height,
      double? spacing,
    }) {
      return TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color ?? primary,
        height: height,
        letterSpacing: spacing,
        fontFamilyFallback: fallback,
      );
    }

    return TextTheme(
      // Hero figure - proportional figures on purpose.
      displaySmall: s(34, FontWeight.w600, height: 1.1, spacing: -0.5),
      headlineMedium: s(26, FontWeight.w600, height: 1.15, spacing: -0.3),
      headlineSmall: s(21, FontWeight.w600, height: 1.2, spacing: -0.2),
      titleLarge: s(17, FontWeight.w600, height: 1.25),
      titleMedium: s(15, FontWeight.w600, height: 1.3),
      titleSmall: s(13.5, FontWeight.w600, height: 1.3),
      bodyLarge: s(14.5, FontWeight.w400, height: 1.45),
      bodyMedium: s(13.5, FontWeight.w400, height: 1.45),
      bodySmall: s(12.5, FontWeight.w400, color: secondary, height: 1.4),
      labelLarge: s(13.5, FontWeight.w600, height: 1.2),
      labelMedium: s(12.5, FontWeight.w500, height: 1.2),
      labelSmall: s(11.5, FontWeight.w600, color: secondary, spacing: 0.3),
    );
  }
}
