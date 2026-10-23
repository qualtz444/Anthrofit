import '../data/training_stats.dart';
import '../models/models.dart';

// Body Progress: physical attributes that can meaningfully change with
// training and be tracked over time.
//
// Today that is body weight and nothing else, because it is the only such
// attribute the app records. Body PROPORTIONS from a scan are deliberately
// not here: they describe structure, are not expected to change with
// training, and live under Body Analysis instead (see scan_comparison.dart).

/// One point on the body-weight line: a real recorded entry, never filled in.
class BodyWeightPoint {
  const BodyWeightPoint({required this.date, required this.weightKg});

  final DateTime date;
  final double weightKg;
}

/// Body weight within one window.
class BodyWeightProgress {
  const BodyWeightProgress({required this.points});

  /// Recorded entries in the window, oldest first.
  final List<BodyWeightPoint> points;

  bool get isEmpty => points.isEmpty;

  /// A trend needs two readings. One reading is a value, not a direction.
  bool get hasTrend => points.length >= 2;

  double? get latestKg => points.isEmpty ? null : points.last.weightKg;

  /// Latest minus earliest in the window. Null without two readings, so a
  /// single entry is never shown as "no change".
  double? get changeKg =>
      hasTrend ? points.last.weightKg - points.first.weightKg : null;
}

/// The body-weight entries inside [range], oldest first.
BodyWeightProgress bodyWeightProgress(
  List<BodyWeightEntry> log,
  ProgressRange range,
  DateTime today,
) {
  final inRange =
      log
          .where(
            (e) =>
                e.weightKg.isFinite &&
                e.weightKg > 0 &&
                isInRange(dateOnly(e.date), range, today),
          )
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
  return BodyWeightProgress(
    points: [
      for (final e in inRange)
        BodyWeightPoint(date: dateOnly(e.date), weightKg: e.weightKg),
    ],
  );
}

/// The log after recording [weightKg] on [now].
///
/// One entry per day: weighing twice in a day keeps the later reading. A
/// value that matches the most recent entry adds nothing, so saving a
/// profile for an unrelated reason never fakes a reading.
List<BodyWeightEntry> recordBodyWeight(
  List<BodyWeightEntry> log,
  double weightKg,
  DateTime now,
) {
  if (weightKg <= 0) return log;
  final day = dateOnly(now);
  final sorted = [...log]..sort((a, b) => a.date.compareTo(b.date));
  if (sorted.isNotEmpty && sorted.last.weightKg == weightKg) return sorted;
  return [
    for (final e in sorted)
      if (dateOnly(e.date) != day) e,
    BodyWeightEntry(date: day, weightKg: weightKg),
  ];
}
