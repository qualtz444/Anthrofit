import '../data/training_stats.dart';
import '../models/models.dart';
import '../progression/progression_rules.dart';
import '../progression/progression_service.dart';

/// Rule-based coaching during a workout. Deterministic, offline, and it
/// writes nothing: completed sets are facts and are never changed here.
///
/// Every comparison is against the set's own planned rep range or the user's
/// own logged sets. No thresholds are introduced. It does not judge effort or
/// technique, which reps alone cannot show.
const String kCoachSafetyNote =
    'Stop the exercise if you feel pain, dizziness or chest discomfort.';

/// One short message after set [setIndex] of [log] was completed, or null
/// when there is nothing grounded to say (warm-up, timed set, no rep target).
///
/// [sessionSoFar] is the active session, used only for the next-time
/// suggestion once the last set of the exercise is done.
String? coachAfterSet(
  ExerciseLog log,
  int setIndex, {
  WorkoutSession? sessionSoFar,
  ProgressionService progression = const ProgressionService(),
}) {
  if (setIndex < 0 || setIndex >= log.sets.length) return null;
  final set = log.sets[setIndex];
  final reps = set.reps;
  if (!set.isCompleted || set.setType == SetType.warmUp || reps == null) {
    return null;
  }
  final planned = log.plannedSetFor(setIndex);
  final min = planned?.targetRepMin;
  final max = planned?.targetRepMax ?? min;
  if (min == null || max == null) return null;

  final range = min == max ? '$min' : '$min–$max';
  final rest = planned!.restSeconds;
  final restText = rest > 0 ? ' (${rest}s)' : '';

  String message;
  if (reps > max) {
    message =
        '$reps reps, above the $range target. Keep this load for today. '
        'What you log here sets the suggestion for next time.';
  } else if (reps >= min) {
    message = '$reps reps, inside the $range target. Keep the same load.';
  } else {
    final previous = _previousWorkSet(log, setIndex);
    if (previous != null &&
        previous.weightKg == set.weightKg &&
        (previous.reps ?? 0) > reps) {
      message =
          'Reps went from ${previous.reps} to $reps at the same load. Some '
          'drop across sets is expected. Take your full rest$restText '
          'before the next set.';
    } else {
      message =
          '$reps reps, below the $range target. Take your full '
          'rest$restText. If the next set is also below, a lighter load may '
          'fit better today.';
    }
  }

  // Last set of the exercise: what the progression rules make of it.
  final allSettled = log.sets.every((s) => s.isSettled);
  if (allSettled && sessionSoFar != null) {
    final next = progression.suggestFor(
      sessions: [sessionSoFar],
      exerciseId: log.exerciseId,
      planned: planned,
    );
    if (next.action != ProgressionAction.noHistory) {
      message = '$message\nFor next time: ${next.reason}';
    }
  }
  return message;
}

SetLog? _previousWorkSet(ExerciseLog log, int setIndex) {
  for (var i = setIndex - 1; i >= 0; i--) {
    final s = log.sets[i];
    if (s.isCompleted && s.setType != SetType.warmUp) return s;
  }
  return null;
}

/// Where a suggested number came from, shown to the user.
enum ProposalSource {
  plan('your plan'),
  thisWorkout('earlier sets today'),
  history('your last session');

  const ProposalSource(this.label);
  final String label;
}

/// A suggested target for one set not yet done. Never an actual result.
class SetProposal {
  const SetProposal({
    required this.setIndex,
    this.loadKg,
    this.reps,
    this.loadSource,
    this.repsSource,
  });

  final int setIndex;
  final double? loadKg;
  final int? reps;
  final ProposalSource? loadSource;
  final ProposalSource? repsSource;

  SetProposal copyWith({double? loadKg, int? reps}) => SetProposal(
    setIndex: setIndex,
    loadKg: loadKg ?? this.loadKg,
    reps: reps ?? this.reps,
    loadSource: loadSource,
    repsSource: repsSource,
  );
}

/// Suggested load and reps for every working set of [log] not yet done.
///
/// Order of evidence, as the panel spec asks:
///   1. the plan's own targets
///   2. completed sets earlier in this workout
///   3. the last completed session, through the progression rules
/// Nothing is invented: a set with none of these gets no number, and the
/// list is empty when there is nothing at all to go on. Warm-ups, timed
/// sets and sets already done or skipped are left alone.
List<SetProposal> proposeTargets({
  required ExerciseLog log,
  required List<WorkoutSession> history,
  ProgressionService progression = const ProgressionService(),
}) {
  final today = [
    for (final s in log.sets)
      if (s.isCompleted && s.setType != SetType.warmUp && s.reps != null) s,
  ];
  final lastToday = today.isEmpty ? null : today.last;

  final out = <SetProposal>[];
  for (var i = 0; i < log.sets.length; i++) {
    final set = log.sets[i];
    if (set.isSettled || set.setType == SetType.warmUp) continue;
    final planned = log.plannedSetFor(i);
    if ((planned?.targetDurationSeconds ?? 0) > 0) continue;
    final min = planned?.targetRepMin;
    final max = planned?.targetRepMax ?? min;
    final next = progression.suggestFor(
      sessions: history,
      exerciseId: log.exerciseId,
      planned: planned,
    );
    final hasHistory = next.action != ProgressionAction.noHistory;

    double? load;
    ProposalSource? loadSource;
    final plannedLoad = planned?.targetLoadKg;
    if (plannedLoad != null && plannedLoad > 0) {
      load = plannedLoad;
      loadSource = ProposalSource.plan;
    } else if (lastToday != null && isWeightedSet(lastToday)) {
      load = lastToday.weightKg;
      loadSource = ProposalSource.thisWorkout;
    } else if (hasHistory && next.suggestedLoadKg != null) {
      load = next.suggestedLoadKg;
      loadSource = ProposalSource.history;
    }

    int? reps;
    ProposalSource? repsSource;
    if (lastToday != null) {
      reps = lastToday.reps;
      if (min != null && max != null) reps = reps!.clamp(min, max);
      repsSource = ProposalSource.thisWorkout;
    } else if (hasHistory && next.suggestedReps != null) {
      reps = next.suggestedReps;
      repsSource = ProposalSource.history;
    } else if (min != null) {
      reps = min;
      repsSource = ProposalSource.plan;
    }

    if (load == null && reps == null) continue;
    out.add(
      SetProposal(
        setIndex: i,
        loadKg: load,
        reps: reps,
        loadSource: loadSource,
        repsSource: repsSource,
      ),
    );
  }
  return out;
}

/// Checks a proposal (possibly edited by the user) before it is applied.
/// Returns an error message, or null when it is fine.
String? validateProposal(SetProposal p) {
  final load = p.loadKg;
  if (load != null && (!load.isFinite || load <= 0)) {
    return 'Set ${p.setIndex + 1}: weight must be above 0.';
  }
  final reps = p.reps;
  if (reps != null && reps < 1) {
    return 'Set ${p.setIndex + 1}: reps must be at least 1.';
  }
  return null;
}

/// Completed sessions only, without the one in progress.
List<WorkoutSession> historyWithout(
  List<WorkoutSession> completed,
  WorkoutSession active,
) => [
  for (final s in completed)
    if (s.id != active.id) s,
];

// ---------------------------------------------------------------------------
// Situation check: asked during the rest after each working set.
// ---------------------------------------------------------------------------

/// How the set just done felt, in the user's own words. Fixed answers so the
/// rules can act on them; the app never guesses effort from reps alone.
enum SetFeel {
  easy('Easy'),
  justRight('Just right'),
  hard('Hard'),
  pain('Pain or dizziness');

  const SetFeel(this.label);
  final String label;
}

/// What the rules do with the answer. [setIndex] is the next set to change,
/// or null when there is none (last set) or the exercise should stop.
class NextSetAdjustment {
  const NextSetAdjustment({
    required this.reason,
    this.setIndex,
    this.loadKg,
    this.reps,
    this.stop = false,
  });

  final String reason;
  final int? setIndex;
  final double? loadKg;
  final int? reps;

  /// Pain or dizziness: no next-set target at all.
  final bool stop;
}

/// The next working set's target after the user says how [doneIndex] felt.
///
/// Rules, all inside the planned rep range and using the progression rules'
/// own load steps (app heuristics, see ProgressionRules):
///   Easy        at or above the top of the range: load up one step;
///               otherwise same load, one more rep
///   Just right  same load and reps
///   Hard        below the range: load down one step; otherwise same load
///               and reps, no extra rep
///   Pain        stop the exercise; no target is suggested
/// Only a suggestion: it fills the input boxes, and the user logs what they
/// actually do.
NextSetAdjustment adjustNextSet(
  ExerciseLog log,
  int doneIndex,
  SetFeel feel, {
  ProgressionRules rules = ProgressionRules.standard,
}) {
  if (feel == SetFeel.pain) {
    return const NextSetAdjustment(
      stop: true,
      reason:
          'You reported pain or dizziness. Stop this exercise now. Skip it, '
          'rest, and get help if it does not ease quickly.',
    );
  }
  final done = log.sets[doneIndex];
  final reps = done.reps ?? 0;
  final load = done.weightKg;

  var next = -1;
  for (var i = doneIndex + 1; i < log.sets.length; i++) {
    final s = log.sets[i];
    if (!s.isSettled && s.setType != SetType.warmUp) {
      next = i;
      break;
    }
  }
  if (next < 0) {
    return NextSetAdjustment(
      reason: 'That was the last set of ${log.exerciseName}; you said it '
          'felt ${feel.label.toLowerCase()}.',
    );
  }

  final planned = log.plannedSetFor(next) ?? log.plannedSetFor(doneIndex);
  final min = planned?.targetRepMin;
  final max = planned?.targetRepMax ?? min;
  int clampReps(int r) =>
      (min == null || max == null) ? r : r.clamp(min, max);
  final hasLoad = load != null && load > 0;
  double up(double kg) {
    final step = kg * rules.increasePercent / 100;
    return rules.round(kg + (step < rules.minIncrementKg ? rules.minIncrementKg : step));
  }
  double down(double kg) => rules.round(kg * (1 - rules.decreasePercent / 100));
  String kg(double v) =>
      '${v == v.roundToDouble() ? v.toInt() : v} kg';

  switch (feel) {
    case SetFeel.easy:
      if (max != null && reps >= max && hasLoad) {
        final l = up(load);
        return NextSetAdjustment(
          setIndex: next,
          loadKg: l,
          reps: min,
          reason: 'Easy at $reps reps, the top of the range: next set '
              '${kg(l)} for $min reps.',
        );
      }
      final r = clampReps(reps + 1);
      return NextSetAdjustment(
        setIndex: next,
        loadKg: hasLoad ? load : null,
        reps: r,
        reason: 'Easy at $reps reps: next set '
            '${hasLoad ? '${kg(load)} for ' : ''}$r reps.',
      );
    case SetFeel.justRight:
      final r = clampReps(reps);
      return NextSetAdjustment(
        setIndex: next,
        loadKg: hasLoad ? load : null,
        reps: r,
        reason: 'Just right: keep ${hasLoad ? '${kg(load)} for ' : ''}$r reps.',
      );
    case SetFeel.hard:
      if (min != null && reps < min && hasLoad) {
        final l = down(load);
        return NextSetAdjustment(
          setIndex: next,
          loadKg: l,
          reps: min,
          reason: 'Hard and below the range at $reps reps: next set '
              '${kg(l)} for $min reps.',
        );
      }
      final r = clampReps(reps);
      return NextSetAdjustment(
        setIndex: next,
        loadKg: hasLoad ? load : null,
        reps: r,
        reason: 'Hard at $reps reps: keep '
            '${hasLoad ? '${kg(load)} for ' : ''}$r reps, take your full rest.',
      );
    case SetFeel.pain:
      throw StateError('handled above');
  }
}
