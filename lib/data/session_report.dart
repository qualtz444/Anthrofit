import '../models/models.dart';
import 'training_stats.dart';

/// Numbers for the Workout complete screen, worked out from what was logged.
/// Nothing here is stored: it is recalculated from the session every time.

/// MET value for resistance training.
///
/// Source: 2024 Adult Compendium of Physical Activities (Herrmann et al.),
/// code 02054, "Resistance (weight) training, multiple exercises, 8-15 reps
/// at varied resistance" = 3.5 METs. The app's programs prescribe 8-12 reps
/// on most goals, which this description fits; it does not fit heavy
/// strength work or circuits (other codes), so the estimate is rough.
const double kResistanceTrainingMet = 3.5;

/// Estimated kilocalories: MET x body weight (kg) x hours, using the
/// standard approximation 1 MET = 1 kcal per kg per hour. Null without a
/// body weight. A population estimate, not a measurement of this person.
double? estimatedKcal(Duration duration, double? bodyWeightKg) {
  if (bodyWeightKg == null || bodyWeightKg <= 0) return null;
  final hours = duration.inSeconds / 3600;
  return kResistanceTrainingMet * bodyWeightKg * hours;
}

/// Mean time between finishing one set and finishing the next, from the
/// sets that have it (see SetLog.restBeforeSeconds). Null when none do.
Duration? averageTimeBetweenSets(WorkoutSession session) {
  var total = 0;
  var count = 0;
  for (final log in session.exerciseLogs) {
    for (final set in log.sets) {
      final rest = set.restBeforeSeconds;
      if (!set.isCompleted || rest == null || rest <= 0) continue;
      total += rest;
      count++;
    }
  }
  if (count == 0) return null;
  return Duration(seconds: (total / count).round());
}

/// One exercise's row in the breakdown.
class ExerciseReport {
  const ExerciseReport({
    required this.setsDone,
    required this.setsSkipped,
    required this.minReps,
    required this.maxReps,
    required this.minWeightKg,
    required this.maxWeightKg,
    required this.volumeKg,
    required this.durationSeconds,
  });

  /// Completed sets, warm-ups included.
  final int setsDone;
  final int setsSkipped;

  /// Reps across completed sets; null when no set has reps (cardio).
  final int? minReps;
  final int? maxReps;

  /// Load across completed weighted sets; null when all were bodyweight.
  final double? minWeightKg;
  final double? maxWeightKg;

  /// Weight x reps over working sets (warm-ups left out, as everywhere
  /// else in the app).
  final double volumeKg;

  /// Total time of timed (cardio) sets, 0 for none.
  final int durationSeconds;

  bool get nothingDone => setsDone == 0;
  bool get isTimed => durationSeconds > 0 && minReps == null;

  /// "3 × 10" or "3 × 10–12".
  String get setsByReps {
    final lo = minReps, hi = maxReps;
    if (lo == null || hi == null) return '$setsDone sets';
    return lo == hi ? '$setsDone × $lo' : '$setsDone × $lo–$hi';
  }
}

ExerciseReport exerciseReport(ExerciseLog log) {
  var done = 0;
  var skipped = 0;
  int? minReps, maxReps;
  double? minW, maxW;
  var volume = 0.0;
  var seconds = 0;
  // A skipped exercise keeps anything logged before it was skipped, but none
  // of it counts (as with ExerciseLog.completedSets everywhere else).
  for (final set in log.skipped ? const <SetLog>[] : log.sets) {
    if (set.skipped) {
      skipped++;
      continue;
    }
    if (!set.isCompleted) continue;
    done++;
    final d = set.durationSeconds;
    if (d != null && d > 0) seconds += d;
    final r = set.reps;
    if (r != null && r > 0) {
      minReps = minReps == null || r < minReps ? r : minReps;
      maxReps = maxReps == null || r > maxReps ? r : maxReps;
    }
    if (isWeightedSet(set)) {
      final w = set.weightKg!;
      minW = minW == null || w < minW ? w : minW;
      maxW = maxW == null || w > maxW ? w : maxW;
      if (isWorkSet(set)) volume += w * (r ?? 0);
    }
  }
  return ExerciseReport(
    setsDone: done,
    setsSkipped: skipped,
    minReps: minReps,
    maxReps: maxReps,
    minWeightKg: minW,
    maxWeightKg: maxW,
    volumeKg: volume,
    durationSeconds: seconds,
  );
}
