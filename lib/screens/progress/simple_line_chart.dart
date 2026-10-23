import 'package:flutter/material.dart';

/// The fewest points a line can be drawn from. One point is a value, not a
/// direction: it is drawn as a single dot, and the screen says a trend needs
/// more sessions.
const int kMinTrendPoints = 2;

class LinePoint {
  const LinePoint({
    required this.label,
    required this.value,
    required this.valueLabel,
  });

  /// Under the point: a short date.
  final String label;
  final double value;

  /// Above the point: the exact value.
  final String valueLabel;
}

/// A line through real observations, and nothing else.
///
/// Each point is a recorded value and is marked with a dot. Points are
/// joined with straight segments: no smoothing, no curve fitting, and no
/// points invented between them, so the line never shows a value nobody
/// recorded.
///
/// To make it readable at a glance, the lowest and highest values are
/// written on the left beside faint guide lines, and with a few points every
/// point carries its value and date. Every label is a value from the data:
/// the scale is never rounded out to numbers nobody recorded.
///
/// Always drawn. With no points it is an empty plot area (the caller puts a
/// message over it); with one point it is a single labelled dot.
class SimpleLineChart extends StatelessWidget {
  const SimpleLineChart({super.key, required this.points, this.height = 180});

  /// Oldest first. Exposed so a test can check exactly what was plotted.
  final List<LinePoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _LinePainter(
          points: points,
          lineColor: theme.colorScheme.primary,
          labelStyle: theme.textTheme.labelSmall!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          valueStyle: theme.textTheme.labelMedium!.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.points,
    required this.lineColor,
    required this.labelStyle,
    required this.valueStyle,
  });

  final List<LinePoint> points;
  final Color lineColor;
  final TextStyle labelStyle;
  final TextStyle valueStyle;

  static const double _top = 22; // room for value labels
  static const double _bottom = 22; // room for date labels
  static const double _left = 44; // room for the low and high labels
  static const double _right = 18;

  /// With this many points or fewer, every point is labelled.
  static const int _labelAll = 6;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      // The plot area alone: a faint baseline, so it reads as an empty chart.
      final y = size.height - _bottom;
      canvas.drawLine(
        Offset(_left, y),
        Offset(size.width - _right, y),
        Paint()
          ..color = labelStyle.color!.withValues(alpha: 0.25)
          ..strokeWidth = 1,
      );
      return;
    }

    var minV = points.first.value;
    var maxV = points.first.value;
    for (final p in points) {
      if (p.value < minV) minV = p.value;
      if (p.value > maxV) maxV = p.value;
    }
    // A flat line sits in the middle rather than dividing by zero.
    final span = maxV - minV;
    final plotH = size.height - _top - _bottom;
    final plotW = size.width - _left - _right;

    Offset at(int i) {
      // A single point sits in the middle.
      final x = points.length == 1
          ? _left + plotW / 2
          : _left + plotW * i / (points.length - 1);
      final t = span == 0 ? 0.5 : (points[i].value - minV) / span;
      return Offset(x, _top + plotH * (1 - t));
    }

    // Guide lines at the highest and lowest values, labelled with those
    // values. One line when every value is the same.
    final guide = Paint()
      ..color = labelStyle.color!.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    final hiIndex = _indexOf(maxV);
    final loIndex = _indexOf(minV);
    final guides = <int>{hiIndex, if (span != 0) loIndex};
    for (final i in guides) {
      final y = at(i).dy;
      canvas.drawLine(Offset(_left, y), Offset(size.width - _right, y), guide);
      _text(
        canvas,
        points[i].valueLabel,
        labelStyle,
        Offset(0, y),
        leftAligned: true,
        width: _left - 6,
      );
    }

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    final few = points.length <= _labelAll;
    final dot = Paint()..color = lineColor;
    final valueIndexes = few
        ? {for (var i = 0; i < points.length; i++) i}
        : {0, points.length - 1};
    for (var i = 0; i < points.length; i++) {
      final o = at(i);
      canvas.drawCircle(o, 3.5, dot);
      if (valueIndexes.contains(i)) {
        _text(
          canvas,
          points[i].valueLabel,
          valueStyle,
          Offset(o.dx, o.dy - 6),
          above: true,
          width: size.width,
        );
      }
    }

    // Every date with a few points; otherwise first, middle and last, so
    // the time span reads without the labels crowding into each other.
    final dateIndexes = few
        ? {for (var i = 0; i < points.length; i++) i}
        : {0, points.length ~/ 2, points.length - 1};
    for (final i in dateIndexes) {
      _text(
        canvas,
        points[i].label,
        labelStyle,
        Offset(at(i).dx, size.height - _bottom + 4),
        above: false,
        width: size.width,
      );
    }
  }

  /// The first point holding [value].
  int _indexOf(double value) {
    for (var i = 0; i < points.length; i++) {
      if (points[i].value == value) return i;
    }
    return 0;
  }

  void _text(
    Canvas canvas,
    String text,
    TextStyle style,
    Offset anchor, {
    bool above = false,
    bool leftAligned = false,
    required double width,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: leftAligned ? width : double.infinity);
    if (leftAligned) {
      // Right-aligned against the plot, centred on the guide line.
      painter.paint(
        canvas,
        Offset(width - painter.width, anchor.dy - painter.height / 2),
      );
      return;
    }
    var dx = anchor.dx - painter.width / 2;
    if (dx < 0) dx = 0;
    if (dx + painter.width > width) dx = width - painter.width;
    final dy = above ? anchor.dy - painter.height : anchor.dy;
    painter.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.points != points || old.lineColor != lineColor;
}
