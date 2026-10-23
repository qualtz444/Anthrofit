import 'package:flutter/material.dart';

/// Fewer bars than this and a plain list reads better than a chart.
/// This is a layout choice, not a training number. Change it here.
const int kMinChartPoints = 3;

class BarPoint {
  const BarPoint({
    required this.label,
    required this.value,
    required this.valueLabel,
    String? listLabel,
  }) : listLabel = listLabel ?? label;

  /// Short label under the bar.
  final String label;
  final double value;

  /// Text above the bar (and in the list).
  final String valueLabel;

  /// Longer label used when shown as a list row.
  final String listLabel;
}

/// A bar chart with no axes or gridlines: each bar is labelled with its exact
/// value, so it never suggests more precision than the data has. Scrolls
/// sideways when there are many bars.
class SimpleBarChart extends StatelessWidget {
  const SimpleBarChart({
    super.key,
    required this.points,
    this.barAreaHeight = 88,
  });

  final List<BarPoint> points;
  final double barAreaHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxValue = points.fold<double>(
      0,
      (max, p) => p.value > max ? p.value : max,
    );

    return SizedBox(
      height: barAreaHeight + 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: points.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final p = points[index];
          double barHeight = 0;
          if (maxValue > 0 && p.value > 0) {
            final raw = p.value / maxValue * barAreaHeight;
            barHeight = raw < 2 ? 2 : raw;
          }
          return SizedBox(
            width: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(p.valueLabel, style: theme.textTheme.labelSmall),
                const SizedBox(height: 4),
                Container(
                  width: 24,
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  p.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A chart when there are enough points, otherwise a plain list.
class SeriesView extends StatelessWidget {
  const SeriesView({super.key, required this.points});

  final List<BarPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.length >= kMinChartPoints) {
      return SimpleBarChart(points: points);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (points.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'A chart appears once there is more data.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final p in points)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text(p.listLabel)),
                Text(
                  p.valueLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
