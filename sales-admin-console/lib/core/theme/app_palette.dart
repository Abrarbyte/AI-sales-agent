import 'package:flutter/material.dart';

/// Design tokens for the Super Admin console.
///
/// The data-visualisation colours below are a *validated* palette: every
/// categorical slot, ordinal ramp and surface pairing here was checked with a
/// six-check colour validator (lightness band, chroma floor, CVD separation,
/// normal-vision floor, contrast, hue spread) in BOTH light and dark mode.
///
/// Validation results at time of writing (OKLab dE x100):
///   categorical slots 1-4, light : worst adjacent CVD 9.1, normal-vision 22.9
///   categorical slots 1-4, dark  : worst adjacent CVD 8.4, normal-vision 19.8
///   ordinal ramp 5 steps,  light : monotone L, gaps >= 0.06, light end 2.06:1
///   ordinal ramp 5 steps,  dark  : monotone L, gaps >= 0.06, light end 3.23:1
///
/// RULES that come with this palette - breaking them invalidates the checks:
///  * Assign categorical slots in FIXED ORDER by entity, never by rank. A team
///    that is blue stays blue when a filter removes the rows above it.
///  * Never generate a 9th hue. Fold the tail into "Other" or facet the chart.
///  * Sequential/ordinal encoding is ONE hue, light to dark. Never a rainbow.
///  * Status colours are reserved for state and always ship with an icon+label.
///  * In light mode the aqua and yellow slots sit below 3:1 against the card
///    surface, so any chart using them must carry visible direct labels or a
///    table view. The chart kit in widgets/charts provides both.
class VizPalette {
  const VizPalette._();

  // --- Categorical: identity. Fixed order, never cycled. -------------------
  static const List<Color> categoricalLight = <Color>[
    Color(0xFF2A78D6), // 1 blue
    Color(0xFFEB6834), // 2 orange
    Color(0xFF1BAF7A), // 3 aqua
    Color(0xFFEDA100), // 4 yellow
    Color(0xFFE87BA4), // 5 magenta
    Color(0xFF008300), // 6 green
    Color(0xFF4A3AA7), // 7 violet
    Color(0xFFE34948), // 8 red
  ];

  static const List<Color> categoricalDark = <Color>[
    Color(0xFF3987E5), // 1 blue
    Color(0xFFD95926), // 2 orange
    Color(0xFF199E70), // 3 aqua
    Color(0xFFC98500), // 4 yellow
    Color(0xFFD55181), // 5 magenta
    Color(0xFF008300), // 6 green
    Color(0xFF9085E9), // 7 violet
    Color(0xFFE66767), // 8 red
  ];

  // --- Ordinal ramp: ordered categories (funnel stages, tiers). ------------
  //
  // A neutral ramp toward the charcoal ink, so ordered scales read as "more
  // of the same" and never compete with the categorical hues. Checked for
  // monotone lightness only; the light end sits close to the page ground,
  // so stage tiles always carry a label.
  static const List<Color> ordinalLight = <Color>[
    Color(0xFFB9D0FF),
    Color(0xFF8DB3FF),
    Color(0xFF4C8DFF),
    Color(0xFF2F6BE0),
    Color(0xFF1D4DB0),
  ];

  static const List<Color> ordinalDark = <Color>[
    Color(0xFF223B6E),
    Color(0xFF2C529E),
    Color(0xFF3A6FD3),
    Color(0xFF4C8DFF),
    Color(0xFF8DB3FF),
  ];

  // --- Diverging: polarity (above / below target). Ink vs red, gray mid. ---
  static const Color divergingPositiveLight = Color(0xFF4C8DFF);
  static const Color divergingNegativeLight = Color(0xFFE5484D);
  static const Color divergingMidLight = Color(0xFFE6E6EA);
  static const Color divergingPositiveDark = Color(0xFF4C8DFF);
  static const Color divergingNegativeDark = Color(0xFFFF6369);
  static const Color divergingMidDark = Color(0xFF1E1E22);

  // --- Status: reserved. Never used as "series 5". Always icon + label. ----
  static const Color statusGood = Color(0xFF30D158);
  static const Color statusWarning = Color(0xFFFFD60A);
  static const Color statusSerious = Color(0xFFFF9F0A);
  static const Color statusCritical = Color(0xFFFF453A);

  // --- Surfaces and ink ---------------------------------------------------
  //
  // Dark first. Near-black ground, panels a step lighter, controls a step
  // lighter again, every edge a hairline of white at 8%. One blue accent
  // carries the numbers that matter; everything else is white or grey.
  //
  //   rail    - the icon bar, darkest
  //   plane   - the page behind everything
  //   surface - a panel sitting on the plane
  //   raised  - a control or nested block inside a panel
  static const Color accent = Color(0xFF059669); // emerald-600
  static const Color railDark = Color(0xFF050506);
  static const Color heroDark = Color(
    0xFF101A38,
  ); // navy glow behind a hero chart

  static const Color surfaceDark = Color(0xFF141417);
  static const Color planeDark = Color(0xFF09090B);
  static const Color raisedDark = Color(0xFF1B1B1F);
  static const Color inkPrimaryDark = Color(0xFFFFFFFF);
  static const Color inkSecondaryDark = Color(0xFFA1A1AA);
  static const Color gridlineDark = Color(0xFF1B1B1F);
  static const Color axisDark = Color(0xFF26262B);
  static const Color borderDark = Color(0x0DFFFFFF);
  static const Color successTextDark = Color(0xFF30D158);

  // Light: the same structure in white, for anyone who flips the toggle.
  // The "Modern CRM" design: near-white plane, white panels, slate-200
  // hairlines, slate-50 controls, slate ink.
  static const Color railLight = Color(0xFFFFFFFF);
  static const Color heroLight = Color(0xFFECFDF5);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color planeLight = Color(0xFFFAFCFB);
  static const Color raisedLight = Color(0xFFF8FAFC);
  static const Color inkPrimaryLight = Color(0xFF0F172A);
  static const Color inkSecondaryLight = Color(0xFF475569);
  static const Color inkMuted = Color(0xFF94A3B8);
  static const Color gridlineLight = Color(0xFFF1F5F9);
  static const Color axisLight = Color(0xFFE2E8F0);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color successTextLight = Color(0xFF047857);

  // Kept for the few places that still spell them; both map onto the
  // new ink and control tones.
  static const Color charcoal = inkPrimaryLight;
  static const Color mist = raisedLight;
}

/// Chart-facing slice of the theme. Charts read colours from here rather than
/// hard-coding hex, so light/dark swap in exactly one place.
@immutable
class ChartTheme extends ThemeExtension<ChartTheme> {
  const ChartTheme({
    required this.series,
    required this.ordinal,
    required this.positive,
    required this.negative,
    required this.neutralMid,
    required this.surface,
    required this.gridline,
    required this.axis,
    required this.inkPrimary,
    required this.inkSecondary,
    required this.inkMuted,
    required this.successText,
  });

  final List<Color> series;
  final List<Color> ordinal;
  final Color positive;
  final Color negative;
  final Color neutralMid;
  final Color surface;
  final Color gridline;
  final Color axis;
  final Color inkPrimary;
  final Color inkSecondary;
  final Color inkMuted;
  final Color successText;

  /// Categorical colour for a stable entity index. Callers must pass an index
  /// derived from the ENTITY (e.g. its position in the canonical team list),
  /// never from its rank in the current sort, or filtering repaints the rows
  /// that survive and a reader who learned "Northern is blue" is misled.
  ///
  /// Past the 8th slot this returns muted ink rather than inventing a hue - the
  /// caller should have folded the tail into "Other" before getting here.
  Color seriesFor(int entityIndex) =>
      entityIndex >= 0 && entityIndex < series.length
      ? series[entityIndex]
      : inkMuted;

  /// Colour for step [step] of an ordered scale with [stepCount] steps.
  Color ordinalFor(int step, int stepCount) {
    if (stepCount <= 1) return ordinal[ordinal.length ~/ 2];
    final double t = step / (stepCount - 1);
    final int i = (t * (ordinal.length - 1)).round();
    return ordinal[i.clamp(0, ordinal.length - 1)];
  }

  static const ChartTheme light = ChartTheme(
    series: VizPalette.categoricalLight,
    ordinal: VizPalette.ordinalLight,
    positive: VizPalette.divergingPositiveLight,
    negative: VizPalette.divergingNegativeLight,
    neutralMid: VizPalette.divergingMidLight,
    surface: VizPalette.surfaceLight,
    gridline: VizPalette.gridlineLight,
    axis: VizPalette.axisLight,
    inkPrimary: VizPalette.inkPrimaryLight,
    inkSecondary: VizPalette.inkSecondaryLight,
    inkMuted: VizPalette.inkMuted,
    successText: VizPalette.successTextLight,
  );

  static const ChartTheme dark = ChartTheme(
    series: VizPalette.categoricalDark,
    ordinal: VizPalette.ordinalDark,
    positive: VizPalette.divergingPositiveDark,
    negative: VizPalette.divergingNegativeDark,
    neutralMid: VizPalette.divergingMidDark,
    surface: VizPalette.surfaceDark,
    gridline: VizPalette.gridlineDark,
    axis: VizPalette.axisDark,
    inkPrimary: VizPalette.inkPrimaryDark,
    inkSecondary: VizPalette.inkSecondaryDark,
    inkMuted: VizPalette.inkMuted,
    successText: VizPalette.successTextDark,
  );

  @override
  ChartTheme copyWith({
    List<Color>? series,
    List<Color>? ordinal,
    Color? positive,
    Color? negative,
    Color? neutralMid,
    Color? surface,
    Color? gridline,
    Color? axis,
    Color? inkPrimary,
    Color? inkSecondary,
    Color? inkMuted,
    Color? successText,
  }) {
    return ChartTheme(
      series: series ?? this.series,
      ordinal: ordinal ?? this.ordinal,
      positive: positive ?? this.positive,
      negative: negative ?? this.negative,
      neutralMid: neutralMid ?? this.neutralMid,
      surface: surface ?? this.surface,
      gridline: gridline ?? this.gridline,
      axis: axis ?? this.axis,
      inkPrimary: inkPrimary ?? this.inkPrimary,
      inkSecondary: inkSecondary ?? this.inkSecondary,
      inkMuted: inkMuted ?? this.inkMuted,
      successText: successText ?? this.successText,
    );
  }

  @override
  ChartTheme lerp(ThemeExtension<ChartTheme>? other, double t) {
    if (other is! ChartTheme) return this;
    return t < 0.5 ? this : other;
  }
}

extension ChartThemeContext on BuildContext {
  ChartTheme get chart =>
      Theme.of(this).extension<ChartTheme>() ?? ChartTheme.light;
}
