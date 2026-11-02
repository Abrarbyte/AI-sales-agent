import 'dart:ui' show PathMetric;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/common.dart';

/// Line chart with a crosshair + floating tooltip.
///
/// A single series, so there is no legend - the panel title names it. The
/// tooltip enhances rather than gates: the hero figure below the chart and the
/// axis labels carry the numbers on their own, which is what keeps the chart
/// readable for keyboard and screen-reader users.
class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.points,
    required this.color,
    this.height = 190,
    this.valueFormatter,
    this.showAxisLabels = true,
  });

  final List<TrendPoint> points;
  final Color color;
  final double height;

  /// Formats the tooltip value. Defaults to a plain count.
  final String Function(double)? valueFormatter;
  final bool showAxisLabels;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart>
    with SingleTickerProviderStateMixin {
  int? _activeIndex;

  // The line sweeps in left to right on first paint and again whenever the
  // series changes - a new window, a refresh. The tooltip waits for it.
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
  void didUpdateWidget(TrendChart old) {
    super.didUpdateWidget(old);
    if (!identical(old.points, widget.points)) {
      _activeIndex = null;
      _sweep.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  void _updateFromPosition(double dx, double width) {
    if (widget.points.length < 2 || _sweep.isAnimating) return;
    final double step = width / (widget.points.length - 1);
    final int i = (dx / step).round().clamp(0, widget.points.length - 1);
    if (i != _activeIndex) setState(() => _activeIndex = i);
  }

  @override
  Widget build(BuildContext context) {
    final ChartTheme chart = context.chart;
    final ThemeData theme = Theme.of(context);

    if (widget.points.length < 2) {
      return SizedBox(height: widget.height);
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double width = c.maxWidth;
        // The callout rests on the peak until the pointer takes over.
        int peak = 0;
        for (int i = 1; i < widget.points.length; i++) {
          if (widget.points[i].value > widget.points[peak].value) peak = i;
        }
        final int shown = _activeIndex ?? peak;

        return MouseRegion(
          onHover: (PointerHoverEvent e) =>
              _updateFromPosition(e.localPosition.dx, width),
          onExit: (_) => setState(() => _activeIndex = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (TapDownDetails d) =>
                _updateFromPosition(d.localPosition.dx, width),
            onHorizontalDragUpdate: (DragUpdateDetails d) =>
                _updateFromPosition(d.localPosition.dx, width),
            onHorizontalDragEnd: (_) => setState(() => _activeIndex = null),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  height: widget.height,
                  child: CustomPaint(
                    painter: _TrendPainter(
                      points: widget.points,
                      color: widget.color,
                      gridline: chart.gridline,
                      activeIndex: shown,
                      surface: chart.surface,
                      progress: MediaQuery.of(context).disableAnimations
                          ? const AlwaysStoppedAnimation<double>(1)
                          : CurvedAnimation(
                              parent: _sweep,
                              curve: Curves.easeOutCubic,
                            ),
                    ),
                    child: _Tooltip(
                            point: widget.points[shown],
                            previous: shown > 0
                                ? widget.points[shown - 1]
                                : null,
                            index: shown,
                            total: widget.points.length,
                            color: widget.color,
                            format:
                                widget.valueFormatter ??
                                (double v) => Fmt.count(v.round()),
                          ),
                  ),
                ),
                if (widget.showAxisLabels) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      for (final int i in <int>[
                        0,
                        widget.points.length ~/ 3,
                        (widget.points.length * 2) ~/ 3,
                        widget.points.length - 1,
                      ])
                        Text(
                          Fmt.dateShort(widget.points[i].date),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: VizPalette.inkMuted,
                            fontFeatures: kTabularFigures,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Positions the callout above the active point, clamped inside the plot.
class _Tooltip extends StatelessWidget {
  const _Tooltip({
    required this.point,
    required this.previous,
    required this.index,
    required this.total,
    required this.color,
    required this.format,
  });

  final TrendPoint point;
  final TrendPoint? previous;
  final int index;
  final int total;
  final Color color;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ChartTheme chart = context.chart;

    final double? delta = previous == null || previous!.value == 0
        ? null
        : (point.value - previous!.value) / previous!.value;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        const double boxWidth = 116;
        final double x = (c.maxWidth / (total - 1)) * index;
        final double left = (x - boxWidth / 2).clamp(
          0.0,
          c.maxWidth - boxWidth,
        );

        return Stack(
          children: <Widget>[
            Positioned(
              left: left,
              top: 12,
              width: boxWidth,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: chart.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusChip),
                  border: Border.all(color: theme.dividerColor),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      Fmt.dateShort(point.date),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: VizPalette.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: <Widget>[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          format(point.value),
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontFeatures: kTabularFigures,
                          ),
                        ),
                      ],
                    ),
                    if (delta != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        Fmt.signedPercent(delta),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: delta >= 0
                              ? chart.successText
                              : VizPalette.statusCritical,
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                    ],
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

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.color,
    required this.gridline,
    required this.surface,
    required this.progress,
    this.activeIndex,
  }) : super(repaint: progress);

  final List<TrendPoint> points;
  final Color color;
  final Color gridline;
  final Color surface;
  final int? activeIndex;

  /// 0..1: how much of the line has been drawn.
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    double min = points.first.value;
    double max = points.first.value;
    for (final TrendPoint p in points) {
      if (p.value < min) min = p.value;
      if (p.value > max) max = p.value;
    }
    // Headroom so the peak never touches the top edge.
    final double span = (max - min).abs() < 0.0001 ? 1 : (max - min) * 1.25;
    final double base = min - (max - min) * 0.12;

    const double inset = 6;
    final double h = size.height - inset * 2;
    final double dx = size.width / (points.length - 1);

    double yFor(double v) => inset + h - ((v - base) / span) * h;

    // Recessive hairline grid - four bands, solid, one shade off the surface.
    final Paint grid = Paint()
      ..color = gridline
      ..strokeWidth = 1;
    for (int i = 1; i < 4; i++) {
      final double y = inset + h * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final Path line = Path();
    for (int i = 0; i < points.length; i++) {
      final Offset o = Offset(dx * i, yFor(points[i].value));
      if (i == 0) {
        line.moveTo(o.dx, o.dy);
      } else {
        // Smooth the join a little - a monotone cubic keeps the curve from
        // overshooting the way a plain bezier does on spiky data.
        final Offset prev = Offset(dx * (i - 1), yFor(points[i - 1].value));
        final double midX = (prev.dx + o.dx) / 2;
        line.cubicTo(midX, prev.dy, midX, o.dy, o.dx, o.dy);
      }
    }

    // Sweep: keep only the drawn portion of the line, and fill under it.
    final double t = progress.value.clamp(0.0, 1.0);
    Path drawn = line;
    double reachX = size.width;
    if (t < 1) {
      drawn = Path();
      for (final PathMetric metric in line.computeMetrics()) {
        drawn.addPath(metric.extractPath(0, metric.length * t), Offset.zero);
      }
      reachX = size.width * t;
    }

    final Path fill = Path.from(drawn)
      ..lineTo(reachX, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size),
    );

    // A soft glow first, then the crisp line over it.
    canvas.drawPath(
      drawn,
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      drawn,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // The leading dot while sweeping.
    if (t < 1 && t > 0) {
      final double tipX = reachX;
      final int i = ((points.length - 1) * t).floor().clamp(
        0,
        points.length - 2,
      );
      final double f = (points.length - 1) * t - i;
      final double tipY =
          yFor(points[i].value) * (1 - f) + yFor(points[i + 1].value) * f;
      canvas.drawCircle(Offset(tipX, tipY), 3.5, Paint()..color = color);
    }

    if (activeIndex != null) {
      final double x = dx * activeIndex!;
      final double y = yFor(points[activeIndex!].value);

      canvas.drawLine(
        Offset(x, inset),
        Offset(x, size.height),
        Paint()
          ..color = color.withValues(alpha: 0.45)
          ..strokeWidth = 1,
      );
      // 2px surface ring so the marker reads on top of the line.
      canvas.drawCircle(Offset(x, y), 6, Paint()..color = surface);
      canvas.drawCircle(Offset(x, y), 4.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.points != points ||
      old.activeIndex != activeIndex ||
      old.color != color ||
      old.progress != progress;
}
