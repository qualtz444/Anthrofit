import '../data/exercise_library.dart';
import '../models/models.dart';
import 'muscle_exposure.dart';

/// Written findings for the Progress tabs. Deterministic: every sentence is
/// worked out from logged workouts, the active program or saved scans, and
/// no new thresholds are introduced.

/// Muscles the active program trains as a PRIMARY target that got no direct
/// (primary) sets in the period. Null when there is no program, no workout
/// in the period, or nothing is missing.
///
/// A gap in one period is a fact about the log, not a judgement that the
/// muscle is undertrained.
String? programGapInsight(TrainingProgram? program, MuscleDistribution d) {
  if (program == null || d.isEmpty) return null;
  final planned = <MuscleGroup>{};
  for (final w in program.workouts) {
    for (final e in w.exercises) {
      final ex = ExerciseLibrary.byId(e.exerciseId);
      if (ex != null) planned.addAll(ex.primaryMuscles);
    }
  }
  if (planned.isEmpty) return null;
  final direct = {
    for (final i in d.involved)
      if (i.primaryWorkouts > 0) i.muscle,
  };
  final missing = [
    for (final m in MuscleGroup.values)
      if (planned.contains(m) && !direct.contains(m)) m,
  ];
  if (missing.isEmpty) {
    return 'Every muscle your program "${program.name}" targets directly got '
        'at least one direct set in this period.';
  }
  final names = missing.map((m) => m.label).join(', ');
  return 'Your program "${program.name}" targets $names directly, but no '
      'direct sets for ${missing.length == 1 ? 'it' : 'them'} were logged in '
      'this period. Check whether those workouts were skipped or swapped.';
}

/// The latest scan against the one before it. Null with fewer than two.
///
/// Uses each scan's own 80% range: when the ranges overlap, the scans cannot
/// be told apart, so no fat loss or muscle gain is claimed.
String? compositionInsight(List<CompositionRecord> log) {
  if (log.length < 2) return null;
  final sorted = [...log]..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  final prev = sorted[sorted.length - 2];
  final last = sorted.last;
  final days = last.takenAt.difference(prev.takenAt).inDays;
  final diff = last.bodyFatPct - prev.bodyFatPct;
  final overlap =
      last.bodyFatLow <= prev.bodyFatHigh && prev.bodyFatLow <= last.bodyFatHigh;
  final sign = diff >= 0 ? '+' : '−';
  final change =
      '${prev.bodyFatPct.toStringAsFixed(1)}% to '
      '${last.bodyFatPct.toStringAsFixed(1)}% '
      '($sign${diff.abs().toStringAsFixed(1)} pts) over $days '
      'day${days == 1 ? '' : 's'}';
  if (overlap) {
    return 'Estimated body fat went from $change. The ranges overlap, so this '
        'may not be a real change.';
  }
  return 'Estimated body fat went from $change, and the ranges do not overlap. '
      'It is still a camera estimate.';
}
