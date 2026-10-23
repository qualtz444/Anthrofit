import '../data/exercise_library.dart';
import '../models/models.dart';

// Weekly volume per muscle, read from a program as it is scheduled.
//
// Counts DIRECT work only: working sets of exercises where the muscle is a
// primary mover. Secondary involvement is left out, so the numbers are a
// floor, not the whole stimulus. Each workout counts once for every day it
// is scheduled. Cardio is not counted.
//
// For reading these numbers: Schoenfeld, Ogborn and Krieger (2017), J Sports
// Sci, found a graded dose-response (more weekly sets, more growth), with a
// trend across their <5, 5-9 and 10+ sets-per-muscle bands (P = 0.074). No
// target is enforced from it.

/// Direct working sets per muscle per week.
Map<MuscleGroup, int> weeklyDirectSets(TrainingProgram program) {
  final sets = <MuscleGroup, int>{};
  _forEachScheduledExercise(program, (exercise, planned) {
    final working = planned.plannedSets
        .where((s) => s.setType == SetType.working)
        .length;
    for (final m in exercise.primaryMuscles) {
      sets[m] = (sets[m] ?? 0) + working;
    }
  });
  return sets;
}

/// Days per week each muscle gets direct work.
Map<MuscleGroup, int> weeklyMuscleDays(TrainingProgram program) {
  final days = <MuscleGroup, Set<Weekday>>{};
  for (final slot in program.schedule) {
    final workout = program.workoutById(slot.workoutId);
    if (workout == null) continue;
    for (final planned in workout.exercises) {
      final exercise = ExerciseLibrary.byId(planned.exerciseId);
      if (exercise == null || exercise.exerciseType == ExerciseType.cardio) {
        continue;
      }
      for (final m in exercise.primaryMuscles) {
        (days[m] ??= <Weekday>{}).add(slot.day);
      }
    }
  }
  return {for (final e in days.entries) e.key: e.value.length};
}

void _forEachScheduledExercise(
  TrainingProgram program,
  void Function(Exercise exercise, PlannedExercise planned) visit,
) {
  for (final slot in program.schedule) {
    final workout = program.workoutById(slot.workoutId);
    if (workout == null) continue;
    for (final planned in workout.exercises) {
      final exercise = ExerciseLibrary.byId(planned.exerciseId);
      if (exercise == null || exercise.exerciseType == ExerciseType.cardio) {
        continue;
      }
      visit(exercise, planned);
    }
  }
}
