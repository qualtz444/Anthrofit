import 'package:flutter/material.dart';

/// A ruler you drag sideways to pick a number.
///
///     IIIIIIIIIIII|IIIIIIIIII  75 kg
///
/// The centre line is the value. Dragging moves the ruler under it, and the
/// value snaps to [step], so a body weight or a height can be set with a
/// thumb instead of a keyboard.
///
/// It reports whatever units it is given and knows nothing about conversion:
/// the caller passes a range and a label already in the units it wants.
class ScrubberInput extends StatefulWidget {
  const ScrubberInput({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.unit = '',
    this.majorEvery = 10,
    this.pixelsPerStep = 10,
  });

  final double value;
  final double min;
  final double max;

  /// Called on every change, including mid-drag.
  final ValueChanged<double> onChanged;

  /// The smallest change. 1 for whole kilograms, 0.5 for finer control.
  final double step;

  /// Shown after the number.
  final String unit;

  /// A taller tick every this many steps.
  final int majorEvery;

  /// How far a drag moves per step. Larger is slower and more precise.
  final double pixelsPerStep;

  @override
  State<ScrubberInput> createState() => _ScrubberInputState();
}

class _ScrubberInputState extends State<ScrubberInput> {
  /// Carried between drag updates, so movement smaller than one step is not
  /// lost: without it a slow drag would never move at all.
  double _leftover = 0;

  double _clamp(double value) => value < widget.min
      ? widget.min
      : (value > widget.max ? widget.max : value);

  void _onDragUpdate(DragUpdateDetails details) {
    // Dragging left raises the value, as on a physical dial.
    final moved = _leftover - details.delta.dx;
    final steps = (moved / widget.pixelsPerStep).truncate();
    if (steps == 0) {
      _leftover = moved;
      return;
    }
    _leftover = moved - steps * widget.pixelsPerStep;
    final next = _clamp(widget.value + steps * widget.step);
    if (next != widget.value) widget.onChanged(next);
  }

  void _nudge(double direction) =>
      widget.onChanged(_clamp(widget.value + direction * widget.step));

  /// The number without trailing zeros: 75, or 75.5.
  String _text(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);

  /// How a value is read aloud: "75 kg".
  String _announce(double value) => '${_text(value)} ${widget.unit}'.trim();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = _text(widget.value);

    return Column(
      children: [
        // Centre alignment, not baseline: an IconButton has no text baseline,
        // and asking for one throws on every frame.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Less',
              icon: const Icon(Icons.remove),
              onPressed: widget.value <= widget.min ? null : () => _nudge(-1),
            ),
            Text(
              text,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (widget.unit.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(widget.unit, style: theme.textTheme.titleMedium),
            ],
            IconButton(
              tooltip: 'More',
              icon: const Icon(Icons.add),
              onPressed: widget.value >= widget.max ? null : () => _nudge(1),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // The ruler itself. Semantics carries the value, because the ticks
        // are painted and a screen reader cannot see them.
        Semantics(
          slider: true,
          value: _announce(widget.value),
          // Flutter requires increasedValue and decreasedValue alongside
          // value whenever onIncrease and onDecrease are given.
          increasedValue: _announce(_clamp(widget.value + widget.step)),
          decreasedValue: _announce(_clamp(widget.value - widget.step)),
          onIncrease: () => _nudge(1),
          onDecrease: () => _nudge(-1),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => _leftover = 0,
            onHorizontalDragUpdate: _onDragUpdate,
            child: SizedBox(
              // Full width and a fixed height, so the painter always has a
              // real box to draw in. Without the width a painter with no
              // child collapses to nothing.
              width: double.infinity,
              height: 56,
              child: CustomPaint(
                painter: _RulerPainter(
                  value: widget.value,
                  min: widget.min,
                  max: widget.max,
                  step: widget.step,
                  majorEvery: widget.majorEvery,
                  pixelsPerStep: widget.pixelsPerStep,
                  tickColor: theme.colorScheme.onSurfaceVariant,
                  centreColor: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.majorEvery,
    required this.pixelsPerStep,
    required this.tickColor,
    required this.centreColor,
  });

  final double value;
  final double min;
  final double max;
  final double step;
  final int majorEvery;
  final double pixelsPerStep;
  final Color tickColor;
  final Color centreColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.width / 2;
    final tick = Paint()
      ..color = tickColor.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    // How many steps fit either side of the centre line.
    final reach = (centre / pixelsPerStep).ceil() + 1;
    final stepsFromMin = ((value - min) / step).round();

    for (var offset = -reach; offset <= reach; offset++) {
      final index = stepsFromMin + offset;
      final atValue = min + index * step;
      if (atValue < min || atValue > max) continue;

      final x = centre + offset * pixelsPerStep;
      final isMajor = index % majorEvery == 0;
      final height = isMajor ? size.height * 0.6 : size.height * 0.3;
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        tick,
      );
    }

    // The centre line: whatever sits under it is the value.
    canvas.drawLine(
      Offset(centre, size.height * 0.1),
      Offset(centre, size.height * 0.9),
      Paint()
        ..color = centreColor
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.value != value ||
      old.min != min ||
      old.max != max ||
      old.step != step ||
      old.tickColor != tickColor ||
      old.centreColor != centreColor;
}
