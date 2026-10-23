import '../core/measurement_labels.dart';
import '../models/measurement.dart';

// Body Analysis: comparing two scans AS MEASUREMENTS.
//
// Proportions describe structure. Training is not expected to change them,
// so a difference between two scans is reported as a number and nothing
// more. It is never called progress, improvement, regression, a gain or a
// loss, and it never drives a trend line. This file is not part of Body
// Progress for exactly that reason.

/// One ratio across two scans.
class RatioDifference {
  const RatioDifference({
    required this.key,
    required this.name,
    required this.previous,
    required this.latest,
  });

  final String key;
  final String name;
  final double previous;
  final double latest;

  /// Latest minus previous. Signed, and nothing else: a plus is not "better".
  double get difference => latest - previous;

  /// "+0.01", "-0.02", "0.00". Two decimals, the precision ratios are shown
  /// at, so a difference is never reported finer than a reading.
  String get differenceLabel {
    final rounded = double.parse(difference.toStringAsFixed(2));
    if (rounded == 0) return '0.00';
    return rounded > 0
        ? '+${rounded.toStringAsFixed(2)}'
        : rounded.toStringAsFixed(2);
  }
}

/// Two scans side by side.
class ScanComparison {
  const ScanComparison({
    required this.previous,
    required this.latest,
    required this.rows,
  });

  final Measurement previous;
  final Measurement latest;

  /// Ratios present in BOTH scans, in the app's usual order. A ratio in only
  /// one scan has nothing to compare against and is left out.
  final List<RatioDifference> rows;

  bool get isEmpty => rows.isEmpty;
}

/// Why two readings of the same body can differ. Shown with every
/// comparison, so a difference is not read as a change in the body.
const String kScanDifferenceNote =
    'Small differences between scans are normal. They can come from measurement '
    'variation, camera position, pose or lighting.';

/// Compares [previous] with [latest], ratio by ratio.
///
/// Order matters only for the sign of each difference. Neither scan is
/// treated as the "better" one.
ScanComparison compareScans(Measurement previous, Measurement latest) {
  final before = {for (final r in readingsFor(previous)) r.key: r};
  final rows = <RatioDifference>[];
  for (final reading in readingsFor(latest)) {
    final earlier = before[reading.key];
    if (earlier == null) continue;
    rows.add(
      RatioDifference(
        key: reading.key,
        name: reading.name,
        previous: earlier.value,
        latest: reading.value,
      ),
    );
  }
  return ScanComparison(previous: previous, latest: latest, rows: rows);
}
