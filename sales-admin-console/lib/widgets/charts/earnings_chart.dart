import 'dart:ui' show PathMetric;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/common.dart';
import '../../features/dashboard/design_tokens.dart';

/// The design's "Earning Summary" area chart: this period as a filled
/// emerald curve, the comparison period as a dashed grey line, dashed
/// gridlines with currency ticks on the left and date labels below.
///
/// Both series must have the same number of points; the comparison is
/// drawn against the same x positions ("same day of the previous period").
class EarningsChart extends StatefulWidget {
  const EarningsChart({
    super.key,
    required this.current,
    required this.previous,
    this.height = 256,
    this.format = _defaultFormat,
  });

  final List<TrendPoint> current;
  final List<TrendPoint> previous;
  final double height;
  final String Function(double) format;

  static String _defaultFormat(double v) => Fmt.moneyCompact(v);

  @override
  State<EarningsChart> createState() => _EarningsChartState();
}

class _EarningsChartState extends State<EarningsChart>
    with SingleTickerProviderStateMixin {
  int? _active;

  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _sweep.forward();
  }

  @override
  void didUpdateWidget(EarningsChart old) {
    super.didUpdateWidget(old);
    if (!identical(old.current, widget.current)) {
      _active = null;
      _sweep.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  static const double _axisWidth = 48;

  void _hover(double dx, double plotWidth) {
    if (widget.current.length < 2) return;
    final double step = plotWidth / (widget.current.length - 1);
    final int i = ((dx - _axisWidth) / step).round().clamp(
      0,
      widget.current.length - 1,
    );
    if (i != _active) setState(() => _active = i);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.current.length < 2) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text('Not enough days to draw yet.', style: Ds.t12(Ds.slate400)),
        ),
      );
    }
    // Peak of this period is where the callout rests until hovered.
    int peak = 0;
    for (int i = 1; i < widget.current.length; i++) {
      if (widget.current[i].value > widget.current[peak].value) peak = i;
    }
    final int shown = _active ?? peak;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double plotWidth = c.maxWidth - _axisWidth - 8;
        return MouseRegion(
          onHover: (PointerHoverEvent e) => _hover(e.localPosition.dx, plotWidth),
          onExit: (_) => setState(() => _active = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (TapDownDetails d) => _hover(d.localPosition.dx, plotWidth),
            onHorizontalDragUpdate: (DragUpdateDetails d) =>
                _hover(d.localPosition.dx, plotWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  height: widget.height,
                  child: CustomPaint(
                    painter: _Painter(
                      current: widget.current,
                      previous: widget.previous,
                      axisWidth: _axisWidth,
                      format: widget.format,
                      active: shown,
                      progress: MediaQuery.of(context).disableAnimations
                          ? const AlwaysStoppedAnimation<double>(1)
                          : CurvedAnimation(
                              parent: _sweep,
                              curve: Curves.easeOutCubic,
                            ),
                    ),
                    child: _Callout(
                      point: widget.current[shown],
                      previous: shown < widget.previous.length
                          ? widget.previous[shown]
                          : null,
                      index: shown,
                      total: widget.current.length,
                      axisWidth: _axisWidth,
                      format: widget.format,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(left: _axisWidth, right: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      for (final int i in _labelIndexes(widget.current.length))
                        Text(
                          Fmt.dateShort(widget.current[i].date),
                          style: Ds.t11(Ds.slate400, w: 500),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static List<int> _labelIndexes(int n) {
    final int want = n <= 7 ? n : 6;
    return <int>[
      for (int k = 0; k < want; k++) ((n - 1) * k / (want - 1)).round(),
    ];
  }
}

class _Callout extends StatelessWidget {
  const _Callout({
    required this.point,
    required this.previous,
    required this.index,
    required this.total,
    required this.axisWidth,
    required this.format,
  });

  final TrendPoint point;
  final TrendPoint? previous;
  final int index;
  final int total;
  final double axisWidth;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    const double boxWidth = 150;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double plot = c.maxWidth - axisWidth - 8;
        final double x = axisWidth + plot / (total - 1) * index;
        final double left = (x - boxWidth / 2).clamp(
          axisWidth,
          c.maxWidth - boxWidth,
        );
        return Stack(
          children: <Widget>[
            Positioned(
              left: left,
              top: 0,
              child: Container(
                width: boxWidth,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Ds.border),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(Fmt.date(point.date), style: Ds.t11(Ds.slate400)),
                    const SizedBox(height: 2),
                    Row(
                      children: <Widget>[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Ds.brand500,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(format(point.value), style: Ds.t12(Ds.slate900, w: 700)),
                      ],
                    ),
                    if (previous != null)
                      Row(
                        children: <Widget>[
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Ds.slate300,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${format(previous!.value)} before',
                            style: Ds.t11(Ds.slate500),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Painter extends CustomPainter {
  _Painter({
    required this.current,
    required this.previous,
    required this.axisWidth,
    required this.format,
    required this.active,
    required this.progress,
  }) : super(repaint: progress);

  final List<TrendPoint> current;
  final List<TrendPoint> previous;
  final double axisWidth;
  final String Function(double) format;
  final int active;
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    double max = 0;
    for (final TrendPoint p in current) {
      if (p.value > max) max = p.value;
    }
    for (final TrendPoint p in previous) {
      if (p.value > max) max = p.value;
    }
    if (max <= 0) max = 1;
    // Three bands with a round step (1, 2, 2.5, 5 x 10^n), so the ticks
    // read as 10K / 20K / 30K rather than thirds of an awkward maximum.
    final double top = _niceCeil(max * 1.15 / 3) * 3;

    const double topInset = 40; // room for the callout
    const double bottomInset = 8;
    final double left = axisWidth;
    final double right = size.width - 8;
    final double plotW = right - left;
    final double h = size.height - topInset - bottomInset;
    double yFor(double v) => topInset + h - (v / top) * h;
    double xFor(int i, int n) => left + plotW * i / (n - 1);

    // Dashed gridlines with tick labels: 4 bands, $0 at the bottom.
    final Paint grid = Paint()
      ..color = Ds.border
      ..strokeWidth = 1;
    for (int k = 0; k <= 3; k++) {
      final double v = top * (3 - k) / 3;
      final double y = yFor(v);
      _dashed(canvas, Offset(left, y), Offset(right, y), grid, 4, 4);
      final TextPainter tp = TextPainter(
        text: TextSpan(text: format(v), style: Ds.t11(Ds.slate400, w: 500)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(left - tp.width - 8, y - tp.height / 2));
    }

    // Comparison period: dashed slate line, no fill.
    if (previous.length >= 2) {
      final Path prev = _curve(previous, xFor, yFor);
      _dashedPath(
        canvas,
        prev,
        Paint()
          ..color = Ds.slate300
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
        6,
        5,
      );
    }

    // This period: sweep in, fill under, crisp emerald line.
    final Path line = _curve(current, xFor, yFor);
    final double t = progress.value.clamp(0.0, 1.0);
    Path drawn = line;
    double reachX = right;
    if (t < 1) {
      drawn = Path();
      for (final PathMetric m in line.computeMetrics()) {
        drawn.addPath(m.extractPath(0, m.length * t), Offset.zero);
      }
      reachX = left + plotW * t;
    }
    final Path fill = Path.from(drawn)
      ..lineTo(reachX, yFor(0))
      ..lineTo(left, yFor(0))
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Ds.brand500.withValues(alpha: 0.28),
            Ds.brand500.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTRB(left, topInset, right, yFor(0))),
    );
    canvas.drawPath(
      drawn,
      Paint()
        ..color = Ds.brand500
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Marker on the active point: white ring, emerald dot, like the design.
    if (t >= 1) {
      final Offset o = Offset(xFor(active, current.length), yFor(current[active].value));
      canvas.drawLine(
        Offset(o.dx, topInset),
        Offset(o.dx, yFor(0)),
        Paint()
          ..color = Ds.brand500.withValues(alpha: 0.25)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(o, 7, Paint()..color = Colors.white);
      canvas.drawCircle(o, 5, Paint()..color = Ds.brand500);
    }
  }

  static Path _curve(
    List<TrendPoint> pts,
    double Function(int, int) xFor,
    double Function(double) yFor,
  ) {
    final Path p = Path();
    for (int i = 0; i < pts.length; i++) {
      final Offset o = Offset(xFor(i, pts.length), yFor(pts[i].value));
      if (i == 0) {
        p.moveTo(o.dx, o.dy);
      } else {
        final Offset prev = Offset(xFor(i - 1, pts.length), yFor(pts[i - 1].value));
        final double midX = (prev.dx + o.dx) / 2;
        p.cubicTo(midX, prev.dy, midX, o.dy, o.dx, o.dy);
      }
    }
    return p;
  }

  static void _dashed(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint,
    double dash,
    double gap,
  ) {
    final double len = (b - a).distance;
    final Offset dir = (b - a) / len;
    double d = 0;
    while (d < len) {
      final double e = (d + dash).clamp(0, len);
      canvas.drawLine(a + dir * d, a + dir * e, paint);
      d += dash + gap;
    }
  }

  static void _dashedPath(
    Canvas canvas,
    Path path,
    Paint paint,
    double dash,
    double gap,
  ) {
    for (final PathMetric m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        final double e = (d + dash).clamp(0, m.length);
        canvas.drawPath(m.extractPath(d, e), paint);
        d += dash + gap;
      }
    }
  }

  static double _niceCeil(double v) {
    if (v <= 0) return 1;
    final double mag = _pow10((v.abs()).toString().split('.').first.length - 1);
    for (final double m in <double>[1, 2, 2.5, 5, 10]) {
      if (mag * m >= v) return mag * m;
    }
    return mag * 10;
  }

  static double _pow10(int n) {
    double r = 1;
    for (int i = 0; i < n; i++) {
      r *= 10;
    }
    return r;
  }

  @override
  bool shouldRepaint(_Painter old) =>
      old.current != current ||
      old.previous != previous ||
      old.active != active;
}
