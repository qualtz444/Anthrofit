import 'package:flutter/material.dart';

import '../../core/id.dart';
import '../../models/models.dart';
import '../../state/program_controller.dart';
import '../../state/program_scope.dart';
import '../program/workout_editor_screen.dart';
import '../../core/snack_bar_timing.dart';

/// Where custom workouts are kept.
///
/// The app has no standalone workout store: a Workout only exists inside a
/// TrainingProgram. Rather than build a second architecture for one feature,
/// custom workouts live in a normal program of this name, created the first
/// time one is saved. That makes them editable, schedulable, startable and
/// deletable with everything that already exists.
const String kCustomWorkoutsProgramName = 'My Workouts';

/// Offers "Add to program" and "Add to custom workout" for one exercise.
Future<void> showAddExerciseSheet(
  BuildContext context, {
  required Exercise exercise,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              exercise.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text('Add to a program'),
            subtitle: const Text('Choose one of your workouts'),
            onTap: () => Navigator.of(sheetContext).pop('program'),
          ),
          ListTile(
            leading: const Icon(Icons.post_add),
            title: const Text('Add to a custom workout'),
            subtitle: const Text('Build a workout of your own'),
            onTap: () => Navigator.of(sheetContext).pop('custom'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  if (choice == 'program') {
    await _addToProgram(context, exercise);
  } else {
    await _addToCustomWorkout(context, exercise);
  }
}

/// Picks one of the user's workouts and appends the exercise to it.
Future<void> _addToProgram(BuildContext context, Exercise exercise) async {
  final messenger = ScaffoldMessenger.of(context);
  final controller = ProgramScope.of(context, listen: false);
  final programs = controller.programs;

  if (programs.every((p) => p.workouts.isEmpty)) {
    messenger.showSnackBar(
      const SnackBar(duration: kSnackBarDuration, persist: false,
        content: Text('You have no workouts yet. Create a program first.'),
      ),
    );
    return;
  }

  final target = await showModalBottomSheet<(String, String)>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(
            title: Text(
              'Add to which workout?',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          for (final program in programs)
            for (final workout in program.workouts)
              ListTile(
                title: Text(workout.name),
                subtitle: Text(program.name),
                onTap: () =>
                    Navigator.of(sheetContext).pop((program.id, workout.id)),
              ),
        ],
      ),
    ),
  );
  if (target == null || !context.mounted) return;

  final (programId, workoutId) = target;
  final program = controller.programById(programId);
  final workout = program?.workoutById(workoutId);
  if (program == null || workout == null) return;

  try {
    await controller.saveProgram(
      program.copyWith(
        workouts: [
          for (final w in program.workouts)
            if (w.id != workoutId)
              w
            else
              w.copyWith(
                exercises: [
                  ...w.exercises,
                  PlannedExercise.withDefaults(
                    exercise.id,
                    isCardio: exercise.exerciseType == ExerciseType.cardio,
                  ),
                ],
              ),
        ],
        updatedAt: DateTime.now(),
      ),
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't add the exercise. Try again.")),
    );
    return;
  }
  messenger.showSnackBar(
    SnackBar(duration: kSnackBarDuration, persist: false, content: Text('${exercise.name} added to ${workout.name}')),
  );
}

/// Builds a custom workout starting from this exercise, then saves it into
/// the "My Workouts" program, creating that program if it does not exist.
Future<void> _addToCustomWorkout(
  BuildContext context,
  Exercise exercise,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final controller = ProgramScope.of(context, listen: false);

  final draft = Workout(
    id: generateId(),
    name: exercise.name,
    exercises: [
      PlannedExercise.withDefaults(
        exercise.id,
        isCardio: exercise.exerciseType == ExerciseType.cardio,
      ),
    ],
  );

  // The existing editor does the rest: name it, add more, reorder, prescribe.
  final saved = await navigator.push<Workout>(
    MaterialPageRoute<Workout>(
      builder: (_) => WorkoutEditorScreen(workout: draft, isNew: true),
    ),
  );
  if (saved == null || !context.mounted) return;

  try {
    await _saveCustomWorkout(controller, saved);
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't save the workout. Try again.")),
    );
    return;
  }
  messenger.showSnackBar(
    SnackBar(duration: kSnackBarDuration, persist: false,
      content: Text('${saved.name} saved to $kCustomWorkoutsProgramName'),
    ),
  );
}

/// Puts [workout] in the custom-workouts program, making it if needed.
Future<void> _saveCustomWorkout(
  ProgramController controller,
  Workout workout,
) async {
  final existing = controller.programs
      .where((p) => p.name == kCustomWorkoutsProgramName)
      .firstOrNull;

  if (existing == null) {
    final now = DateTime.now();
    await controller.saveProgram(
      TrainingProgram(
        id: generateId(),
        name: kCustomWorkoutsProgramName,
        workouts: [workout],
        createdAt: now,
        updatedAt: now,
      ),
    );
    return;
  }
  await controller.saveProgram(
    existing.copyWith(
      workouts: [...existing.workouts, workout],
      updatedAt: DateTime.now(),
    ),
  );
}
