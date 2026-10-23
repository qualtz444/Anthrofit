import '../data/training_stats.dart';
import '../models/models.dart';

// How often the user trained in a window. Frequency only: this deliberately
// says nothing about planned or missed workouts, which is a different
// question about adherence and is not part of Progress.

class WorkoutFrequency {
  const WorkoutFrequency({
    required this.workouts,
    required this.sets,
    required this.weeks,
  });

  /// Completed workouts in the window.
  final int workouts;

  /// Completed work sets in the window. Warm-ups and skipped sets excluded.
  final int sets;

  /// How many weeks the window covers. For a fixed window this is exact
  /// (7 days is one week); for all time it runs from the week of the first
  /// workout to this week.
  final int weeks;

  /// Workouts per week, or null before any workout.
  double? get perWeek => weeks == 0 ? null : workouts / weeks;
}

/// Frequency within [range], from completed sessions only.
WorkoutFrequency workoutFrequency(
  List<WorkoutSession> sessions,
  ProgressRange range,
  DateTime today,
) {
  final completed = sessions.where((s) => s.isCompleted).toList();
  final inRange = sessionsInRange(completed, range, today);
  final summary = summarize(inRange);

  final int weeks;
  final days = range.days;
  if (days != null) {
    weeks = (days / 7).ceil();
  } else if (completed.isEmpty) {
    weeks = 0;
  } else {
    final first = startOfWeek(sessionDate(oldestFirst(completed).first));
    final now = startOfWeek(dateOnly(today));
    weeks = now.difference(first).inDays ~/ 7 + 1;
  }

  return WorkoutFrequency(
    workouts: summary.workouts,
    sets: summary.sets,
    weeks: weeks,
  );
}
