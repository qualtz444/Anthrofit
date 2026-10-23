import '../data/training_stats.dart';
import '../models/models.dart';

// Strength Progress: "am I getting stronger?"
//
// Built only from sets actually logged in completed workouts, through the
// existing per-exercise history in training_stats.dart. There is deliberately
// no estimated one-rep max: the app has never estimated one (see
// personalRecords), and an estimate would put a number on screen that no set
// ever reached.

/// What to plot for an exercise.
enum StrengthMetric {
  /// The heaviest weight lifted in a session.
  heaviestWeight('Best weight', 'kg'),

  /// The most reps in one set in a session.
  mostReps('Best reps', 'reps'),

  /// Weight × reps over every work set in a session. Weighted sets only.
  volume('Volume', 'kg');

  const StrengthMetric(this.label, this.unit);

  final String label;
  final String unit;
}

/// One session's value for a metric. Only sessions where the exercise was
/// actually done appear, so the line never invents a session.
class StrengthPoint {
  const StrengthPoint({required this.date, required this.value});

  final DateTime date;
  final double value;
}

/// The best set of two sessions, and the difference between them.
class StrengthComparison {
  const StrengthComparison({
    required this.previous,
    required this.latest,
    required this.previousDate,
    required this.latestDate,
  });

  final SetLog previous;
  final SetLog latest;
  final DateTime previousDate;
  final DateTime latestDate;

  double? get weightChangeKg {
    final a = previous.weightKg;
    final b = latest.weightKg;
    if (a == null || b == null || a <= 0 || b <= 0) return null;
    return b - a;
  }

  int get repChange => (latest.reps ?? 0) - (previous.reps ?? 0);
}

class StrengthProgress {
  const StrengthProgress({
    required this.exerciseId,
    required this.exerciseName,
    required this.metric,
    required this.points,
    required this.records,
    required this.comparison,
    required this.bestWeightKg,
    required this.bestReps,
    required this.volumeKg,
  });

  final String exerciseId;
  final String exerciseName;
  final StrengthMetric metric;

  /// Oldest first.
  final List<StrengthPoint> points;

  /// From the whole history, not just the window: a record is a record.
  final PersonalRecords records;

  /// The last two sessions in the window, when there are two.
  final StrengthComparison? comparison;

  /// Heaviest completed set in the window, or null with no weighted set.
  final double? bestWeightKg;

  /// Most reps in one completed set in the window, or null with none.
  final int? bestReps;

  /// Weight × reps over every weighted work set in the window, or null when
  /// no set had a weight, so a bodyweight exercise shows "—", not "0 kg".
  final double? volumeKg;

  bool get isEmpty => points.isEmpty;

  /// Two sessions are the least that can show a direction.
  bool get hasTrend => points.length >= 2;
}

/// Strength for one exercise within [range].
StrengthProgress strengthProgress({
  required List<WorkoutSession> sessions,
  required String exerciseId,
  required StrengthMetric metric,
  required ProgressRange range,
  required DateTime today,
}) {
  final completed = sessions.where((s) => s.isCompleted).toList();
  final all = exerciseHistory(completed, exerciseId);
  final inRange = all.where((e) => isInRange(e.date, range, today)).toList();

  final points = <StrengthPoint>[];
  for (final entry in inRange) {
    final value = _valueOf(entry, metric);
    if (value != null) {
      points.add(StrengthPoint(date: entry.date, value: value));
    }
  }

  StrengthComparison? comparison;
  final withBest = inRange.where((e) => e.bestSet != null).toList();
  if (withBest.length >= 2) {
    final a = withBest[withBest.length - 2];
    final b = withBest.last;
    comparison = StrengthComparison(
      previous: a.bestSet!,
      latest: b.bestSet!,
      previousDate: a.date,
      latestDate: b.date,
    );
  }

  // Window totals, from the same entries the chart uses.
  double? bestWeight;
  int? bestReps;
  double? volume;
  for (final entry in inRange) {
    final h = entry.heaviestKg;
    if (h != null && (bestWeight == null || h > bestWeight)) bestWeight = h;
    final r = entry.mostReps;
    if (r > 0 && (bestReps == null || r > bestReps)) bestReps = r;
    final v = _valueOf(entry, StrengthMetric.volume);
    if (v != null) volume = (volume ?? 0) + v;
  }

  return StrengthProgress(
    exerciseId: exerciseId,
    exerciseName: all.isEmpty ? '' : all.last.exerciseName,
    metric: metric,
    points: points,
    records: personalRecords(all),
    comparison: comparison,
    bestWeightKg: bestWeight,
    bestReps: bestReps,
    volumeKg: volume,
  );
}

/// A session's value for [metric], or null when it has none. A session with
/// no logged weight has no top weight and no volume; it is left off the
/// line rather than plotted as zero.
double? _valueOf(ExerciseEntry entry, StrengthMetric metric) {
  switch (metric) {
    case StrengthMetric.heaviestWeight:
      return entry.heaviestKg;
    case StrengthMetric.mostReps:
      final reps = entry.mostReps;
      return reps > 0 ? reps.toDouble() : null;
    case StrengthMetric.volume:
      var total = 0.0;
      var any = false;
      for (final set in entry.sets) {
        if (!isWeightedSet(set)) continue;
        total += set.weightKg! * (set.reps ?? 0);
        any = true;
      }
      return any ? total : null;
  }
}

/// Exercises with strength data in [range]: done at least once with reps.
/// Cardio is left out, because time is not a strength measure. Most recent
/// first, which is the order the existing exercise list uses.
List<ExerciseSummary> strengthExercises(
  List<WorkoutSession> sessions,
  ProgressRange range,
  DateTime today,
) {
  final inRange = sessionsInRange(
    sessions.where((s) => s.isCompleted).toList(),
    range,
    today,
  );
  return exercisesPerformed(inRange)
      .where(
        (e) => exerciseHistory(
          inRange,
          e.exerciseId,
        ).any((entry) => entry.mostReps > 0),
      )
      .toList();
}
