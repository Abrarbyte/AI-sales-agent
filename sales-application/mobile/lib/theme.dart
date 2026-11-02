import 'package:flutter/material.dart';

/// "Ambient Neo" - the Stitch design "SalesHub Dashboard".
///
/// Light and soft: a pale blue ground with a faint radial mesh, white cards
/// lifted by a two-sided shadow (dark below-right, light above-left), deep
/// blue and teal for the one gradient button, cyan for accents. The values
/// are the design's Tailwind tokens, kept under their names.
class AppTheme {
  // --- the design's palette, verbatim ---
  static const neoBg = Color(0xFFEEF3F8);
  static const neoCard = Color(0xFFFFFFFF);
  static const neoBlue = Color(0xFF0A4B6E);
  static const neoBlueDeep = Color(0xFF06354F);
  static const neoBlueLight = Color(0xFFE1EEF6);
  static const neoTeal = Color(0xFF088395);
  static const neoCyan = Color(0xFF22C1C3);
  static const neoAccent = Color(0xFF0E6285);

  // slate, as Tailwind spells it
  static const slate800 = Color(0xFF1E293B);
  static const slate500 = Color(0xFF64748B);
  static const slate400 = Color(0xFF94A3B8);
  static const slate200 = Color(0xFFE2E8F0);


  // --- light (the design) ---
  static const _lPrimary = neoBlue;
  static const _lOnPrimary = Colors.white;
  static const _lPrimaryContainer = neoBlueLight;
  static const _lOnPrimaryContainer = neoBlue;
  static const _lSecondary = neoTeal;
  static const _lOnSecondary = Colors.white;
  static const _lSecondaryContainer = Color(0xFFDDF4F5);
  static const _lOnSecondaryContainer = Color(0xFF065E6B);
  static const _lTertiary = slate800;
  static const _lOnTertiary = Colors.white;
  static const _lSurface = neoBg;
  static const _lOnSurface = slate800;
  static const _lSurfaceVariant = neoBlueLight;
  static const _lOnSurfaceVariant = slate500;
  static const _lCard = neoCard;
  static const _lSurfaceLow = Color(0xFFF6F9FC);
  static const _lSurfaceContainer = Color(0xFFF1F5F9);
  static const _lSurfaceHigh = neoBlueLight;
  static const _lOutlineVariant = Color(0xFFD9E4EE);
  static const _lError = Color(0xFFE0384F);
  static const _lOnError = Colors.white;
  static const _lErrorContainer = Color(0xFFFDE8EC);

  // --- dark: a derived twin, not designed; the app pins light ---
  static const _dPrimary = Color(0xFF7CC4E8);
  static const _dOnPrimary = neoBlueDeep;
  static const _dPrimaryContainer = Color(0xFF0E3A52);
  static const _dOnPrimaryContainer = Color(0xFFCFE7F5);
  static const _dSecondary = neoCyan;
  static const _dOnSecondary = neoBlueDeep;
  static const _dSecondaryContainer = Color(0xFF0B4A52);
  static const _dOnSecondaryContainer = Color(0xFFBDF1F2);
  static const _dTertiary = Colors.white;
  static const _dOnTertiary = neoBlueDeep;
  static const _dSurface = Color(0xFF0B1620);
  static const _dOnSurface = Color(0xFFE6EEF5);
  static const _dSurfaceVariant = Color(0xFF1A2A38);
  static const _dOnSurfaceVariant = slate400;
  static const _dCard = Color(0xFF122130);
  static const _dSurfaceLow = Color(0xFF0F1C28);
  static const _dSurfaceContainer = Color(0xFF122130);
  static const _dSurfaceHigh = Color(0xFF1A2A38);
  static const _dOutlineVariant = Color(0x1FFFFFFF);
  static const _dError = Color(0xFFFF7A8A);
  static const _dOnError = Color(0xFF3B0A12);
  static const _dErrorContainer = Color(0xFF4A1520);

  /// Accent by name: the cyan the design uses for live dots and highlights.
  static const accent = neoCyan;
  static const accentContainer = neoBlueLight;

  /// Status colours, tuned to sit on white.
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const emerald700 = Color(0xFF047857);
  static const orange500 = Color(0xFFF97316);
  static const orange600 = Color(0xFFEA580C);
  static const amber500 = Color(0xFFF5B301);
  static const amber600 = Color(0xFFD69E00);
  static const violet500 = Color(0xFF8B5CF6);
  static const violet600 = Color(0xFF7C3AED);
  static const blue500 = neoAccent;
  static const blue600 = neoBlue;
  static const rose500 = Color(0xFFE0384F);
  static const rose600 = Color(0xFFC1273C);

  /// The primary gradient: deep blue to teal, left to right.
  static const primaryGradient = LinearGradient(
    colors: [neoBlue, neoTeal],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// The hero tile gradient: navy, darker toward the bottom-right.
  static const heroGradient = LinearGradient(
    colors: [neoBlue, neoBlueDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// `shadow-neo-flat`: lifted, both sides.
  static const List<BoxShadow> neoFlat = [
    BoxShadow(
        color: Color(0x66A6B9CE), offset: Offset(8, 8), blurRadius: 18),
    BoxShadow(
        color: Color(0xD9FFFFFF), offset: Offset(-8, -8), blurRadius: 18),
  ];

  /// `shadow-neo-flat-sm`: the same, for controls and small tiles.
  static const List<BoxShadow> neoFlatSm = [
    BoxShadow(
        color: Color(0x59A6B9CE), offset: Offset(4, 4), blurRadius: 10),
    BoxShadow(
        color: Color(0xCCFFFFFF), offset: Offset(-4, -4), blurRadius: 10),
  ];

  /// `shadow-neo-glow`: under the gradient button.
  static const List<BoxShadow> neoGlow = [
    BoxShadow(
        color: Color(0x380A4B6E), offset: Offset(0, 8), blurRadius: 20),
  ];

  /// `shadow-neo-dock`: the bottom dock, lit from above.
  static const List<BoxShadow> neoDock = [
    BoxShadow(
        color: Color(0x59B4CAE0), offset: Offset(0, -6), blurRadius: 20),
  ];

  /// Android's minimum touch target. Above the design's 44px `touch-target-min`
  /// on purpose: this app is used one-handed, outdoors, often in a hurry.
  static const controlHeight = 48.0;

  /// The design's shape scale — `borderRadius` in its tailwind.config:
  ///
  ///   DEFAULT = 0.25rem =  4   inputs, chips, small buttons
  ///   lg      = 0.5rem  =  8   stat tiles, list rows
  ///   xl      = 0.75rem = 12   the clock card, sheets
  ///
  /// `radius2xl` has no counterpart in the design; it continues the step for
  /// the few places that need a softer corner than `xl`.
  static const radiusMd = 12.0; // rounded-xl: inputs, chips
  static const radius = 16.0; // rounded-2xl: tiles, rows
  static const radiusXl = 24.0; // rounded-3xl: cards
  static const radius2xl = 28.0; // the design's custom 3xl
  static const radiusDock = 36.0; // rounded-4xl: the bottom dock

  // ---------------------------------------------------------------------
  // Type. Both faces are variable fonts, so the weight travels as a
  // `fontVariations` axis rather than a `fontWeight` the renderer would have
  // to fake. `fontWeight` is set alongside it so that widgets which inspect
  // the style (and tests) still read the intended weight.
  // ---------------------------------------------------------------------

  static TextStyle _face(
    String family,
    double size,
    int weight,
    double lineHeight, {
    double? letterSpacing,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: family,
      fontSize: size,
      height: lineHeight / size,
      fontWeight: FontWeight.values[(weight ~/ 100) - 1],
      fontVariations: [FontVariation('wght', weight.toDouble())],
      letterSpacing: letterSpacing,
      color: color,
    );
  }

  /// Hanken Grotesk — body copy, headlines, buttons. Everything but the
  /// small uppercase labels.
  static TextStyle sans(double size, int weight, double lineHeight,
          {double? letterSpacing, Color? color}) =>
      _face('HankenGrotesk', size, weight, lineHeight,
          letterSpacing: letterSpacing, color: color);

  /// JetBrains Mono — the design's `label-sm` only: the small tracked-out
  /// uppercase labels ("MONTHLY TARGET", "OCT 24, 2023") and figures that
  /// benefit from tabular alignment.
  static TextStyle mono(double size, int weight, double lineHeight,
          {double? letterSpacing, Color? color}) =>
      _face('JetBrainsMono', size, weight, lineHeight,
          letterSpacing: letterSpacing, color: color);

  // The design's named type scale, as ready-made styles.
  static TextStyle get displayLg =>
      sans(64, 700, 72, letterSpacing: -1.28); // -0.02em
  static TextStyle get headlineLg => sans(40, 600, 48);
  static TextStyle get headlineLgMobile => sans(32, 600, 40);
  static TextStyle get headlineMd => sans(28, 500, 36);
  static TextStyle get bodyLg => sans(18, 400, 28);
  static TextStyle get bodyMd => sans(16, 400, 24);
  static TextStyle get button => sans(14, 600, 20, letterSpacing: 0.28); // .02em
  static TextStyle get labelSm =>
      mono(12, 500, 16, letterSpacing: 0.6); // 0.05em

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: isLight ? _lPrimary : _dPrimary,
      onPrimary: isLight ? _lOnPrimary : _dOnPrimary,
      primaryContainer: isLight ? _lPrimaryContainer : _dPrimaryContainer,
      onPrimaryContainer: isLight ? _lOnPrimaryContainer : _dOnPrimaryContainer,
      secondary: isLight ? _lSecondary : _dSecondary,
      onSecondary: isLight ? _lOnSecondary : _dOnSecondary,
      secondaryContainer: isLight ? _lSecondaryContainer : _dSecondaryContainer,
      onSecondaryContainer:
          isLight ? _lOnSecondaryContainer : _dOnSecondaryContainer,
      tertiary: isLight ? _lTertiary : _dTertiary,
      onTertiary: isLight ? _lOnTertiary : _dOnTertiary,
      surface: isLight ? _lSurface : _dSurface,
      onSurface: isLight ? _lOnSurface : _dOnSurface,
      surfaceContainerLowest: isLight ? _lCard : _dCard,
      surfaceContainerLow: isLight ? _lSurfaceLow : _dSurfaceLow,
      surfaceContainer: isLight ? _lSurfaceContainer : _dSurfaceContainer,
      surfaceContainerHigh: isLight ? _lSurfaceHigh : _dSurfaceHigh,
      surfaceContainerHighest: isLight ? _lSurfaceVariant : _dSurfaceVariant,
      onSurfaceVariant: isLight ? _lOnSurfaceVariant : _dOnSurfaceVariant,
      outlineVariant: isLight ? _lOutlineVariant : _dOutlineVariant,
      error: isLight ? _lError : _dError,
      onError: isLight ? _lOnError : _dOnError,
      errorContainer: isLight ? _lErrorContainer : _dErrorContainer,
    );

    final onSurface = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      fontFamily: 'HankenGrotesk',
      // Flutter's default is adaptive, which is compact anywhere but a phone
      // and quietly takes 8px off every control — undoing `controlHeight` in
      // the web build a phone actually loads.
      visualDensity: VisualDensity.standard,
      textTheme: TextTheme(
        displayLarge: displayLg.copyWith(color: onSurface),
        headlineLarge: headlineLg.copyWith(color: onSurface),
        headlineMedium: headlineMd.copyWith(color: onSurface),
        titleLarge: headlineLgMobile.copyWith(color: onSurface),
        bodyLarge: bodyLg.copyWith(color: onSurface),
        bodyMedium: bodyMd.copyWith(color: onSurface),
        bodySmall: bodyMd.copyWith(fontSize: 14, color: muted),
        labelSmall: labelSm.copyWith(color: muted),
        labelLarge: button.copyWith(color: onSurface),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: headlineLgMobile.copyWith(color: onSurface),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(controlHeight + 4),
          textStyle: button,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(controlHeight + 4),
          textStyle: button,
          backgroundColor: isLight ? Colors.white : scheme.surfaceContainerHigh,
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: button,
          foregroundColor: scheme.primary,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? Colors.white : scheme.surfaceContainerLowest,
        constraints: const BoxConstraints(minHeight: controlHeight),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: bodyMd.copyWith(
            fontSize: 14, color: muted.withValues(alpha: 0.7)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStatePropertyAll(labelSm.copyWith(color: muted)),
      ),
    );
  }
}

/// The neo lift. Light mode gets the two-sided shadow the design specifies;
/// dark mode, which the app does not ship, falls back to a plain drop.
List<BoxShadow> cardShadow(Brightness brightness, {bool small = false}) =>
    brightness == Brightness.light
        ? (small ? AppTheme.neoFlatSm : AppTheme.neoFlat)
        : const [BoxShadow(color: Color(0x66000000), blurRadius: 12)];

Color cardBorder(Brightness brightness) => brightness == Brightness.light
    ? Colors.white.withValues(alpha: 0.8)
    : const Color(0x1FFFFFFF);

/// A white card lifted off the pale ground by the neo shadow: the shape every
/// card in the design shares, so screens describe what is inside rather than
/// restating the box.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = AppTheme.radiusXl,
    this.onTap,
    this.color,
    this.gradient,
    this.small = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? color;

  /// For the one dark hero tile: paints a gradient instead of the colour.
  final Gradient? gradient;

  /// The smaller shadow, for tiles and rows.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decorated = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null
            ? (color ?? theme.colorScheme.surfaceContainerLowest)
            : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: gradient == null
            ? Border.all(color: cardBorder(theme.brightness))
            : null,
        boxShadow: gradient == null
            ? cardShadow(theme.brightness, small: small)
            : AppTheme.neoGlow,
      ),
      child: child,
    );

    if (onTap == null) return decorated;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: decorated,
      ),
    );
  }
}

/// The design's primary action: deep-blue-to-teal gradient, glow beneath,
/// white label. `FilledButton` stays for secondary saves inside sheets.
class NeoButton extends StatelessWidget {
  const NeoButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.busy = false,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool busy;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          boxShadow: enabled ? AppTheme.neoGlow : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.white),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 20, color: Colors.white),
                          const SizedBox(width: 10),
                        ],
                        Text(label,
                            style:
                                AppTheme.button.copyWith(color: Colors.white)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small tinted label: "Pipeline", "Scheduled", "Urgent", "LIVE GPS".
class NeoTag extends StatelessWidget {
  const NeoTag(this.text, {super.key, this.color, this.onDark = false});

  final String text;
  final Color? color;

  /// On the navy hero tile the tag is a translucent white pill.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.neoAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.16) : c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: onDark ? Colors.white : c,
        ),
      ),
    );
  }
}

/// A square icon well - the rounded tile behind an icon on every card.
class NeoIconWell extends StatelessWidget {
  const NeoIconWell(this.icon, {super.key, this.color, this.onDark = false});

  final IconData icon;
  final Color? color;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.neoBlue;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.14) : c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Icon(icon, size: 20, color: onDark ? Colors.white : c),
    );
  }
}

/// The ambient mesh behind every screen: the pale ground with two soft
/// lighter pools, top-left and bottom-right.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (theme.brightness == Brightness.dark) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.neoBg,
            gradient: RadialGradient(
              center: Alignment(-0.7, -0.7),
              radius: 1.1,
              colors: [Color(0xCCE1F0FC), Color(0x00EEF3F8)],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.7, 0.7),
              radius: 1.1,
              colors: [Color(0xE6EAF3FA), Color(0x00EEF3F8)],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// The Tailwind colours the design's markup names, so a class like
/// `text-slate-400` maps to one spelling here.
class Tw {
  const Tw._();

  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate600 = Color(0xFF475569);
  static const slate700 = Color(0xFF334155);
  static const slate800 = Color(0xFF1E293B);

  static const sky50 = Color(0xFFF0F9FF);
  static const sky100 = Color(0xFFE0F2FE);
  static const sky400 = Color(0xFF38BDF8);
  static const sky600 = Color(0xFF0284C7);
  static const sky700 = Color(0xFF0369A1);
  static const sky800 = Color(0xFF075985);

  static const teal400 = Color(0xFF2DD4BF);

  static const cyan200 = Color(0xFFA5F3FC);
  static const cyan400 = Color(0xFF22D3EE);
  static const cyan700 = Color(0xFF0E7490);
  static const cyan800 = Color(0xFF155E75);
  static const cyan950 = Color(0xFF083344);

  static const amber50 = Color(0xFFFFFBEB);
  static const amber100 = Color(0xFFFEF3C7);
  static const amber200 = Color(0xFFFDE68A);
  static const amber700 = Color(0xFFB45309);

  static const rose50 = Color(0xFFFFF1F2);
  static const rose100 = Color(0xFFFFE4E6);
  static const rose500 = Color(0xFFF43F5E);
  static const rose600 = Color(0xFFE11D48);

  static const emerald500 = Color(0xFF10B981);
  static const red500 = Color(0xFFEF4444);
}
