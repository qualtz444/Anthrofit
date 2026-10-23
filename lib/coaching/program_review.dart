import '../data/exercise_library.dart';
import '../data/setup_options.dart';
import '../data/training_stats.dart';
import '../models/models.dart';
import '../recommendation/prescription_rules.dart';
import '../recommendation/weekly_volume.dart';

/// Checks a program against the profile and the training log, and proposes
/// the SMALLEST change that fits. Deterministic, and it writes nothing: the
/// screen shows a preview and saves only what the user approves.

/// How many most-recent sessions must all fall below the rep range before
/// an exercise is flagged. APP CHOICE: one bad session is noise; two in a
/// row is the smallest "repeated" pattern. Not from a published source.
const int kStruggleSessions = 2;

/// One planned exercise whose prescription would change.
class PrescriptionChange {
  const PrescriptionChange({
    required this.exerciseName,
    required this.before,
    required this.after,
  });

  final String exerciseName;
  final String before;
  final String after;
}

class ProgramReview {
  const ProgramReview({
    this.goalChange,
    this.changes = const [],
    this.proposed,
    this.notes = const [],
    this.struggling = const [],
    this.missingEquipment = const [],
    this.unscheduledWorkouts = const [],
    this.unplannedMuscles = const [],
    this.weeklySets = const {},
  });

  /// Workouts in the program that are on no training day.
  final List<String> unscheduledWorkouts;

  /// Muscles the program's own workouts train directly that get 0 direct
  /// sets in the week as scheduled. A fact about the schedule, not a
  /// judgement against an external target.
  final List<String> unplannedMuscles;

  /// Direct working sets per muscle per week, as scheduled.
  final Map<MuscleGroup, int> weeklySets;

  /// Exercises needing equipment the profile no longer lists, using the
  /// same rule the recommender uses to choose exercises.
  final List<String> missingEquipment;

  /// (program goal, profile goal) when they differ.
  final (TrainingGoal?, TrainingGoal)? goalChange;

  /// What re-prescribing for the profile goal would change.
  final List<PrescriptionChange> changes;

  /// The program with only reps and rest re-prescribed. Same id, exercises,
  /// sets, loads, schedule and history. Null when nothing would change.
  final TrainingProgram? proposed;

  /// Differences that need the user's own edit (days, session length).
  final List<String> notes;

  /// Exercise names below their rep range in the last [kStruggleSessions]
  /// sessions running.
  final List<String> struggling;

  bool get isEmpty =>
      proposed == null &&
      notes.isEmpty &&
      struggling.isEmpty &&
      missingEquipment.isEmpty &&
      unscheduledWorkouts.isEmpty &&
      unplannedMuscles.isEmpty;
}

String _range(PlannedSet s) {
  final min = s.targetRepMin;
  final max = s.targetRepMax ?? min;
  final reps = min == null ? 'no rep target' : (min == max ? '$min' : '$min–$max');
  return '$reps reps, ${s.restSeconds}s rest';
}

ProgramReview reviewProgram({
  required TrainingProgram program,
  required UserProfile profile,
  required List<WorkoutSession> history,
  PrescriptionRules rules = PrescriptionRules.standard,
}) {
  // ---- goal: same exercises, new reps and rest --------------------------
  (TrainingGoal?, TrainingGoal)? goalChange;
  final changes = <PrescriptionChange>[];
  TrainingProgram? proposed;
  // A program saved before goals existed has none: nothing to compare.
  if (program.goal != null && program.goal != profile.goal) {
    goalChange = (program.goal, profile.goal);
    final (repMin, repMax) = rules.repsFor(profile.goal, profile.experience);
    final workouts = <Workout>[];
    for (final w in program.workouts) {
      final exercises = <PlannedExercise>[];
      for (final pe in w.exercises) {
        final ex = ExerciseLibrary.byId(pe.exerciseId);
        if (ex == null || ex.exerciseType == ExerciseType.cardio) {
          exercises.add(pe);
          continue;
        }
        final rest = rules.restFor(profile.goal, profile.experience, ex);
        final sets = [
          for (final s in pe.plannedSets)
            // Only working sets with a rep target: warm-ups, failure sets
            // and timed sets keep what the user set.
            s.setType == SetType.working && s.targetRepMin != null
                ? s.copyWith(
                    targetRepMin: repMin,
                    targetRepMax: repMax,
                    restSeconds: rest,
                  )
                : s,
        ];
        final before = pe.plannedSets.isEmpty ? '' : _range(pe.plannedSets.first);
        final after = sets.isEmpty ? '' : _range(sets.first);
        if (before != after) {
          changes.add(
            PrescriptionChange(
              exerciseName: ex.name,
              before: before,
              after: after,
            ),
          );
        }
        exercises.add(pe.copyWith(plannedSets: sets));
      }
      workouts.add(w.copyWith(exercises: exercises));
    }
    proposed = program.copyWith(
      goal: profile.goal,
      workouts: workouts,
      updatedAt: DateTime.now(),
    );
  }

  // ---- days and session length: reported, never rebuilt silently --------
  final notes = <String>[];
  final days = program.trainingDays.length;
  final wanted = profile.trainingFrequency.days;
  // Only for programs generated from a setup: a template or hand-made
  // program's days are the user's own choice, not a mismatch.
  if (program.setup != null && days > 0 && days != wanted) {
    notes.add(
      'Your profile says ${profile.trainingFrequency.label} days a week; this '
      'program is scheduled on $days. Edit the schedule or create a new program '
      'for $wanted days.',
    );
  }
  final setupDuration = program.setup?.sessionDuration;
  if (setupDuration != null && setupDuration != profile.sessionDuration) {
    notes.add(
      'This program was built for ${setupDuration.label} sessions; your profile '
      'now says ${profile.sessionDuration.label}. Create a new program to fit '
      'that time.',
    );
  }

  // ---- schedule balance: what the week actually trains -----------------
  final unscheduled = <String>[];
  final unplanned = <String>[];
  var weekly = const <MuscleGroup, int>{};
  if (program.schedule.isNotEmpty) {
    final scheduledIds = {for (final s in program.schedule) s.workoutId};
    for (final w in program.workouts) {
      if (w.exercises.isNotEmpty && !scheduledIds.contains(w.id)) {
        unscheduled.add(w.name);
      }
    }
    weekly = weeklyDirectSets(program);
    final inProgram = <MuscleGroup>{};
    for (final w in program.workouts) {
      for (final pe in w.exercises) {
        final ex = ExerciseLibrary.byId(pe.exerciseId);
        if (ex != null && ex.exerciseType != ExerciseType.cardio) {
          inProgram.addAll(ex.primaryMuscles);
        }
      }
    }
    for (final m in MuscleGroup.values) {
      if (inProgram.contains(m) && (weekly[m] ?? 0) == 0) {
        unplanned.add(m.label);
      }
    }
  }

  // ---- equipment: same mapping and rule as the recommender ------------
  final missingEquipment = <String>[];
  if (profile.equipment.isNotEmpty) {
    final available = equipmentForCategories(
      categoriesFromProfile(profile),
    ).toSet();
    final availableExtra = {
      for (final e in extraEquipmentForCategories(
        categoriesFromProfile(profile),
      ))
        e.id,
    };
    final checked = <String>{};
    for (final w in program.workouts) {
      for (final pe in w.exercises) {
        if (!checked.add(pe.exerciseId)) continue;
        final ex = ExerciseLibrary.byId(pe.exerciseId);
        if (ex == null) continue;
        final needs = ex.equipment.where((i) => i != EquipmentItem.none);
        if (needs.any((i) => !available.contains(i)) ||
            ex.extraEquipment.any((id) => !availableExtra.contains(id))) {
          missingEquipment.add(ex.name);
        }
      }
    }
  }

  // ---- repeated difficulty ----------------------------------------------
  final struggling = <String>[];
  final recent = newestFirst([
    for (final s in history)
      if (s.isCompleted && s.programId == program.id) s,
  ]);
  final seen = <String>{};
  for (final w in program.workouts) {
    for (final pe in w.exercises) {
      if (!seen.add(pe.exerciseId)) continue;
      var below = 0;
      for (final s in recent) {
        ExerciseLog? log;
        for (final l in s.exerciseLogs) {
          if (l.exerciseId == pe.exerciseId && workSetsOf(l).isNotEmpty) {
            log = l;
          }
        }
        if (log == null) continue;
        final min = log.plannedSetFor(0)?.targetRepMin;
        final sets = workSetsOf(log);
        final allBelow =
            min != null && sets.every((x) => (x.reps ?? 0) < min);
        if (!allBelow) break;
        below++;
        if (below >= kStruggleSessions) break;
      }
      if (below >= kStruggleSessions) {
        struggling.add(
          ExerciseLibrary.byId(pe.exerciseId)?.name ?? pe.exerciseId,
        );
      }
    }
  }

  return ProgramReview(
    goalChange: goalChange,
    changes: changes,
    proposed: changes.isEmpty && goalChange == null ? null : proposed,
    notes: notes,
    struggling: struggling,
    missingEquipment: missingEquipment,
    unscheduledWorkouts: unscheduled,
    unplannedMuscles: unplanned,
    weeklySets: weekly,
  );
}
