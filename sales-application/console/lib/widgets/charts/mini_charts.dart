import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';

/// Tiny trend line for a KPI tile. No axes, no labels - the tile's number is
/// the value, and this only carries the shape of the last two weeks.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 34,
  });

  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox(height: height);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(values: values, color: color),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    double min = values.first;
    double max = values.first;
    for (final double v in values) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    final double span = (max - min).abs() < 0.0001 ? 1 : max - min;

    // Inset by the stroke's half-width so the line never clips at the edges.
    const double inset = 1.5;
    final double h = size.height - inset * 2;
    final double dx = size.width / (values.length - 1);

    final Path line = Path();
    for (int i = 0; i < values.length; i++) {
      final double x = dx * i;
      final double y = inset + h - ((values[i] - min) / span) * h;
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }

    // A soft fill under the line gives the tile weight without a heavy stroke.
    final Path fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            color.withValues(alpha: 0.20),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        // 2px lines: thin marks read as data, thick ones read as decoration.
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Mark the latest point so the eye lands on "now".
    final double lastX = size.width;
    final double lastY =
        inset + h - ((values.last - min) / span) * h;
    canvas.drawCircle(Offset(lastX - 2, lastY), 2.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.color != color;
}

/// One row of a horizontal bar chart.
class BarDatum {
  const BarDatum({
    required this.label,
    required this.value,
    required this.entityIndex,
    this.sublabel,
    this.valueLabel,
  });

  final String label;
  final double value;

  /// Stable colour index for the ENTITY. Never pass a row's rank here: sorting
  /// or filtering would then repaint the survivors and a reader who learned
  /// "Coastal is orange" would be misled.
  final int entityIndex;

  final String? sublabel;

  /// Pre-formatted value shown at the bar's end. Direct labels are what make
  /// this chart readable without decoding colour.
  final String? valueLabel;
}

/// Horizontal bars for a ranked list (leaderboards, per-team comparisons).
///
/// Horizontal because the category names are long - a vertical column chart
/// would force rotated tick labels, which nobody reads comfortably.
class HBarChart extends StatelessWidget {
  const HBarChart({
    super.key,
    required this.data,
    this.barHeight = 22,
    this.gap = 12,
    this.labelWidth = 132,
    this.singleHue = false,
    this.highlightIndex,
  });

  final List<BarDatum> data;
  final double barHeight;
  final double gap;
  final double labelWidth;

  /// When true every bar takes series slot 1.
  ///
  /// This is the right default for nominal categories: colouring each bar
  /// darker-where-bigger double-encodes the bar length as hue and burns the
  /// only free channel on information the length already shows. Use per-entity
  /// colour only when the same entities appear in other charts and the colour
  /// is doing identity work across them.
  final bool singleHue;

  /// Row to emphasise; all others drop to a de-emphasis grey.
  final int? highlightIndex;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    final ChartTheme chart = context.chart;
    final ThemeData theme = Theme.of(context);

    double max = 0;
    for (final BarDatum d in data) {
      if (d.value > max) max = d.value;
    }
    if (max <= 0) max = 1;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool tight = constraints.maxWidth < 420;
        final double labels = tight ? 96 : labelWidth;
        // Reserve room for the direct value label at the bar's end.
        final double trackWidth =
            (constraints.maxWidth - labels - 68).clamp(40.0, 4000.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < data.length; i++) ...<Widget>[
              if (i > 0) SizedBox(height: gap),
              _BarRow(
                datum: data[i],
                max: max,
                labelWidth: labels,
                trackWidth: trackWidth,
                barHeight: barHeight,
                color: _colorFor(chart, i),
                theme: theme,
              ),
            ],
          ],
        );
      },
    );
  }

  Color _colorFor(ChartTheme chart, int row) {
    if (highlightIndex != null) {
      return row == highlightIndex
          ? chart.seriesFor(data[row].entityIndex)
          : chart.inkMuted.withValues(alpha: 0.45);
    }
    if (singleHue) return chart.series.first;
    return chart.seriesFor(data[row].entityIndex);
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.datum,
    required this.max,
    required this.labelWidth,
    required this.trackWidth,
    required this.barHeight,
    required this.color,
    required this.theme,
  });

  final BarDatum datum;
  final double max;
  final double labelWidth;
  final double trackWidth;
  final double barHeight;
  final Color color;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final double fraction = (datum.value / max).clamp(0.0, 1.0);
    final ChartTheme chart = context.chart;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: labelWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                datum.label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              if (datum.sublabel != null)
                Text(
                  datum.sublabel!,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: VizPalette.inkMuted),
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        SizedBox(
          width: trackWidth,
          height: barHeight,
          child: Stack(
            children: <Widget>[
              // Recessive track, one shade off the surface.
              Container(
                decoration: BoxDecoration(
                  color: chart.gridline.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              FractionallySizedBox(
                widthFactor: fraction,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    // Rounded data-end only; the baseline end stays square so
                    // the bar reads as anchored to zero.
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(2),
                      right: Radius.circular(4),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            datum.valueLabel ?? datum.value.toStringAsFixed(0),
            style: theme.textTheme.labelMedium
                ?.copyWith(fontFeatures: kTabularFigures),
          ),
        ),
      ],
    );
  }
}

/// A single ratio against its limit - target attainment, proof compliance.
/// Preferred over a two-slice pie, which is unreadable at this size.
class MeterBar extends StatelessWidget {
  const MeterBar({
    super.key,
    required this.fraction,
    required this.color,
    this.height = 6,
    this.showOverflow = true,
  });

  /// 0..1+. Values past 1 render as an overflow segment when [showOverflow].
  final double fraction;
  final Color color;
  final double height;
  final bool showOverflow;

  @override
  Widget build(BuildContext context) {
    final ChartTheme chart = context.chart;
    final double base = fraction.clamp(0.0, 1.0);
    final double over = showOverflow ? (fraction - 1).clamp(0.0, 1.0) : 0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          children: <Widget>[
            Container(color: chart.gridline.withValues(alpha: 0.55)),
            FractionallySizedBox(
              widthFactor: base,
              child: Container(color: color),
            ),
            if (over > 0)
              FractionallySizedBox(
                widthFactor: over,
                child: Container(color: color.withValues(alpha: 0.45)),
              ),
          ],
        ),
      ),
    );
  }
}
