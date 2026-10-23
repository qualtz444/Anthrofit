import '../data/training_stats.dart';
import '../models/models.dart';
import 'progression_rules.dart';

/// What to do with the load next time.
enum ProgressionAction {
  /// Every set reached the top of the range: add a little.
  increaseLoad,

  /// Working through the range: same load, aim for one more rep.
  holdLoad,

  /// A clear drop: ease off.
  reduceLoad,

  /// Nothing logged for this exercise yet.
  noHistory,
}

/// A suggestion for the next time an exercise comes up.
///
/// Every field is a suggestion. Nothing here changes a plan or a log by
/// itself, and the user can always type something else.
class ProgressionSuggestion {
  const ProgressionSuggestion({
    required this.action,
    this.suggestedLoadKg,
    this.suggestedReps,
    required this.reason,
    this.lastPerformance,
  });

  final ProgressionAction action;

  /// The load to put in the weight box, or null when there is nothing to go
  /// on. Never invented: it only ever comes from what was actually lifted.
  final double? suggestedLoadKg;

  /// The rep target for the next set, inside the planned range.
  final int? suggestedReps;

  /// One short sentence a person can read.
  final String reason;

  /// "40 kg × 10, 10, 9" from the last time, or null.
  final String? lastPerformance;

  bool get hasSuggestion => suggestedLoadKg != null || suggestedReps != null;
}

/// Works out the next load and rep target from what was actually logged.
///
/// Deterministic, and only ever reads completed sessions. It writes nothing.
class ProgressionService {
  const ProgressionService({this.rules = ProgressionRules.standard});

  final ProgressionRules rules;

  /// The most recent completed log for [exerciseId], or null.
  /// Warm-up sets are ignored, as they are everywhere else in the app.
  ExerciseLog? lastLogFor(List<WorkoutSession> sessions, String exerciseId) {
    for (final session in newestFirst(sessions)) {
      for (final log in session.exerciseLogs) {
        if (log.exerciseId == exerciseId && workSetsOf(log).isNotEmpty) {
          return log;
        }
      }
    }
    return null;
  }

  /// What to suggest for [exerciseId] next.
  ///
  /// [planned] is the prescription it will be performed against, used for the
  /// rep range. Pass null to use the range the last session recorded.
  ProgressionSuggestion suggestFor({
    required List<WorkoutSession> sessions,
    required String exerciseId,
    PlannedSet? planned,
  }) {
    final log = lastLogFor(sessions, exerciseId);
    if (log == null) {
      return const ProgressionSuggestion(
        action: ProgressionAction.noHistory,
        reason:
            'First time logging this exercise. Start with a weight you '
            'can control for every set.',
      );
    }

    final sets = workSetsOf(log);
    final reps = [for (final s in sets) s.reps ?? 0];
    final loads = [
      for (final s in sets)
        if (isWeightedSet(s)) s.weightKg!,
    ];
    final lastLoad = loads.isEmpty
        ? null
        : loads.reduce((a, b) => a > b ? a : b);

    // The range to judge against: the one planned now, else the one recorded.
    final target = planned ?? log.plannedSetFor(0);
    final repMin = target?.targetRepMin;
    final repMax = target?.targetRepMax ?? repMin;

    final summary = _summarise(sets);

    // A Failure set has no rep target, so there is nothing to judge.
    if (repMin == null || repMax == null) {
      return ProgressionSuggestion(
        action: ProgressionAction.holdLoad,
        suggestedLoadKg: lastLoad,
        reason: lastLoad == null
            ? 'Last time: $summary.'
            : 'Last time: $summary. No rep target, so the same load is '
                  'suggested.',
        lastPerformance: summary,
      );
    }

    final everySetAtTop = reps.isNotEmpty && reps.every((r) => r >= repMax);
    final belowRange =
        reps.isNotEmpty &&
        reps.every((r) => r < repMin - rules.regressionTolerance);

    if (everySetAtTop) {
      final next = lastLoad == null ? null : rules.round(_increase(lastLoad));
      return ProgressionSuggestion(
        action: ProgressionAction.increaseLoad,
        suggestedLoadKg: next,
        // After a load increase the reps start at the bottom of the range.
        suggestedReps: repMin,
        reason: next == null
            ? 'You hit $repMax reps on every set. Add a little resistance.'
            : 'You hit $repMax reps on every set, so the load goes up to '
                  '${_kg(next)}. Aim for $repMin reps to start.',
        lastPerformance: summary,
      );
    }

    if (belowRange) {
      final next = lastLoad == null
          ? null
          : rules.round(lastLoad * (1 - rules.decreasePercent / 100));
      return ProgressionSuggestion(
        action: ProgressionAction.reduceLoad,
        suggestedLoadKg: next,
        suggestedReps: repMin,
        reason: next == null
            ? 'Your reps dropped below $repMin. Ease off and build back up.'
            : 'Your reps dropped below $repMin, so the load eases to '
                  '${_kg(next)}.',
        lastPerformance: summary,
      );
    }

    // Working through the range: same load, one more rep than last time.
    final best = reps.isEmpty ? repMin : reps.reduce((a, b) => a > b ? a : b);
    final nextReps = (best + 1).clamp(repMin, repMax);
    return ProgressionSuggestion(
      action: ProgressionAction.holdLoad,
      suggestedLoadKg: lastLoad,
      suggestedReps: nextReps,
      reason: 'Last time: $summary. Same load, aim for $nextReps reps.',
      lastPerformance: summary,
    );
  }

  double _increase(double load) {
    final step = load * rules.increasePercent / 100;
    return load + (step < rules.minIncrementKg ? rules.minIncrementKg : step);
  }

  static String _kg(double kg) =>
      kg == kg.roundToDouble() ? '${kg.round()} kg' : '$kg kg';

  /// "40 kg × 10, 10, 9", or "10, 10, 9 reps" with no load.
  static String _summarise(List<SetLog> sets) {
    final reps = sets.map((s) => '${s.reps ?? 0}').join(', ');
    final weighted = sets.where(isWeightedSet).toList();
    if (weighted.isEmpty) return '$reps reps';
    final load = weighted.first.weightKg!;
    final sameLoad = weighted.every((s) => s.weightKg == load);
    return sameLoad ? '${_kg(load)} × $reps' : '$reps reps at varying loads';
  }
}
