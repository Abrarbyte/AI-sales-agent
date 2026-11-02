import 'package:flutter/material.dart';

/// The "Modern CRM Dashboard" design's tokens: Tailwind's slate scale, the
/// emerald brand ramp, and the few text styles the shell and dashboard are
/// laid out with class-for-class from its markup.
class Ds {
  const Ds._();

  // Surfaces.  body bg-[#F9FAFB], main bg-[#FAFCFB], cards white.
  static const Color page = Color(0xFFFAFCFB);
  static const Color sidebar = Colors.white;
  static const Color card = Colors.white;
  static const Color control = Color(0xFFF8FAFC); // slate-50
  static const Color border = Color(0xFFE2E8F0); // slate-200
  static const Color borderSoft = Color(0xFFF1F5F9); // slate-100
  static const Color track = Color(0xFFF1F5F9); // slate-100 bar track

  // Brand ramp (tailwind.config brand.* = emerald).
  static const Color brand50 = Color(0xFFECFDF5);
  static const Color brand100 = Color(0xFFD1FAE5);
  static const Color brand200 = Color(0xFFA7F3D0);
  static const Color brand300 = Color(0xFF6EE7B7);
  static const Color brand400 = Color(0xFF34D399);
  static const Color brand500 = Color(0xFF10B981);
  static const Color brand600 = Color(0xFF059669);
  static const Color brand700 = Color(0xFF047857);
  static const Color brand800 = Color(0xFF065F46);

  static const Color rose50 = Color(0xFFFFF1F2);
  static const Color rose200 = Color(0xFFFECDD3);
  static const Color rose700 = Color(0xFFBE123C);
  static const Color indigo50 = Color(0xFFEEF2FF);
  static const Color indigo100 = Color(0xFFE0E7FF);
  static const Color indigo600 = Color(0xFF4F46E5);
  static const Color amber50 = Color(0xFFFFFBEB);
  static const Color amber100 = Color(0xFFFEF3C7);
  static const Color amber600 = Color(0xFFD97706);

  static const Color slate300 = Color(0xFFCBD5E1);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate600 = Color(0xFF475569);
  static const Color slate700 = Color(0xFF334155);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate900 = Color(0xFF0F172A);

  /// shadow-2xs: 0 1px 2px rgba(0,0,0,.05)
  static const List<BoxShadow> shadow2xs = <BoxShadow>[
    BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1)),
  ];

  // --- type (Inter) --------------------------------------------------------

  static TextStyle t(
    double size,
    Color color, {
    int w = 400,
    double spacing = 0,
    double height = 1.35,
  }) => TextStyle(
    fontSize: size,
    fontWeight: FontWeight.values[(w ~/ 100) - 1],
    fontVariations: <FontVariation>[FontVariation('wght', w.toDouble())],
    letterSpacing: spacing,
    height: height,
    color: color,
  );

  static TextStyle t10(Color c, {int w = 400}) => t(10, c, w: w);
  static TextStyle t11(Color c, {int w = 400}) => t(11, c, w: w);
  static TextStyle t12(Color c, {int w = 400}) => t(12, c, w: w);
  static TextStyle t13(Color c, {int w = 400}) => t(13, c, w: w);
  static TextStyle t14(Color c, {int w = 400}) => t(14, c, w: w);

  /// text-sm font-bold text-slate-900 - card titles.
  static TextStyle get h3 => t(14, slate900, w: 700);

  /// text-lg font-bold text-slate-900 - the page title.
  static TextStyle get h1 => t(18, slate900, w: 700, spacing: -0.2);

  /// text-2xl font-bold tracking-tight - the KPI figure.
  static TextStyle get figure => t(24, slate900, w: 700, spacing: -0.5, height: 1.2);
}

/// bg-white p-6 rounded-2xl border border-slate-200/80 shadow-2xs
class DsCard extends StatelessWidget {
  const DsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Ds.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Ds.border.withValues(alpha: 0.8)),
        boxShadow: Ds.shadow2xs,
      ),
      child: child,
    );
  }
}

/// The delta chip on a KPI: bg-emerald-50 text-emerald-700 for up,
/// bg-rose-50 text-rose-700 for down, slate for flat.
class DsDeltaChip extends StatelessWidget {
  const DsDeltaChip({super.key, required this.label, required this.sign});

  final String label;

  /// 1 up, -1 down, 0 flat.
  final int sign;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, Color line) = switch (sign) {
      > 0 => (Ds.brand50, Ds.brand700, Ds.brand200),
      < 0 => (Ds.rose50, Ds.rose700, Ds.rose200),
      _ => (Ds.control, Ds.slate500, Ds.border),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: line.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: Ds.t11(fg, w: 600)),
    );
  }
}

/// text-xs font-medium bg-slate-50 border border-slate-200/80 px-2.5
/// py-1.5 rounded-lg - the "Last 30 Days" control.
class DsControlButton extends StatelessWidget {
  const DsControlButton({
    super.key,
    required this.label,
    this.icon,
    this.trailing = Icons.expand_more,
    this.onTap,
    this.white = false,
  });

  final String label;
  final IconData? icon;
  final IconData? trailing;
  final VoidCallback? onTap;

  /// bg-white with shadow, like "Export Report"; otherwise slate-50.
  final bool white;

  @override
  Widget build(BuildContext context) {
    final Widget body = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: white ? Colors.white : Ds.control,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Ds.border.withValues(alpha: 0.8)),
        boxShadow: white ? Ds.shadow2xs : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 14, color: Ds.slate500),
            if (label.isNotEmpty) const SizedBox(width: 6),
          ],
          if (label.isNotEmpty)
            Text(label, style: Ds.t12(white ? Ds.slate700 : Ds.slate600, w: 500)),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 6),
            Icon(trailing, size: 14, color: Ds.slate400),
          ],
        ],
      ),
    );
    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: body,
    );
  }
}

/// Initials in a coloured circle.
class DsAvatar extends StatelessWidget {
  const DsAvatar({super.key, required this.initials, this.size = 32});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Ds.border,
        shape: BoxShape.circle,
        border: Border.all(color: Ds.brand500.withValues(alpha: 0.2), width: 2),
      ),
      child: Text(initials, style: Ds.t12(Ds.slate600, w: 500)),
    );
  }
}
