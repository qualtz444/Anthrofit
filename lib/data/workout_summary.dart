import '../models/models.dart';
import 'exercise_library.dart';

/// Primary muscles trained by a workout, without repeats, in the order they
/// first appear. Always read from the exercise library, never stored on the
/// workout, so it can't drift out of sync with the exercise definitions.
List<MuscleGroup> primaryMusclesOf(Workout workout) {
  final result = <MuscleGroup>[];
  for (final planned in workout.exercises) {
    final exercise = ExerciseLibrary.byId(planned.exerciseId);
    if (exercise == null) continue;
    for (final muscle in exercise.primaryMuscles) {
      if (!result.contains(muscle)) result.add(muscle);
    }
  }
  return result;
}

/// Equipment a workout needs, without repeats, in the order it first
/// appears. "None" is left out: an exercise needing nothing is not a piece
/// of equipment to list.
///
/// Read from the library like the muscles above, so adding or removing an
/// exercise changes it immediately and nothing can go stale.
List<EquipmentItem> equipmentOf(Workout workout) {
  final result = <EquipmentItem>[];
  for (final planned in workout.exercises) {
    final exercise = ExerciseLibrary.byId(planned.exerciseId);
    if (exercise == null) continue;
    for (final item in exercise.equipment) {
      if (item == EquipmentItem.none) continue;
      if (!result.contains(item)) result.add(item);
    }
  }
  return result;
}

/// Primary muscles across every workout in a program, in [MuscleGroup]
/// order so the list reads the same however the workouts are arranged.
List<MuscleGroup> programMuscles(TrainingProgram program) {
  final seen = <MuscleGroup>{};
  for (final workout in program.workouts) {
    seen.addAll(primaryMusclesOf(workout));
  }
  return MuscleGroup.values.where(seen.contains).toList();
}

/// Equipment across every workout in a program, in [EquipmentItem] order.
List<EquipmentItem> programEquipment(TrainingProgram program) {
  final seen = <EquipmentItem>{};
  for (final workout in program.workouts) {
    seen.addAll(equipmentOf(workout));
  }
  return EquipmentItem.values.where(seen.contains).toList();
}
