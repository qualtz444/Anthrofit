import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/list_utils.dart';
import '../../core/set_labels.dart';
import '../../data/exercise_library.dart';
import '../../data/workout_summary.dart';
import '../../models/models.dart';
import '../../state/program_controller.dart';
import '../../state/program_scope.dart';
import '../../state/session_scope.dart';
import '../exercises/exercise_card.dart';
import '../exercises/exercise_detail_screen.dart';
import '../session/start_workout.dart';
import '../widgets/chip_row.dart';
import '../widgets/rename_dialog.dart';
import 'workout_editor_screen.dart';
import '../widgets/muscle_image.dart';
import '../../core/snack_bar_timing.dart';

/// VIEWING a workout, and running it.
///
///   tap an exercise        -> what it is: muscles, equipment, instructions
///   long-press and drag    -> reorder, saved straight away
///   Edit workout           -> add, remove, rename and prescribe
///   Start workout          -> the one way into performing it
///
/// Changing WHAT the workout contains lives in one place, the workout
/// editor, rather than being spread across per-row buttons here. Reordering
/// stays because it is a direct manipulation of what is already on screen.
///
/// Everything is read from the saved program, so it updates after an edit:
///   workout name/focus/exercises  <- Workout and PlannedExercise
///   scheduled days                <- TrainingProgram.schedule
///   exercise name/type/muscles    <- the exercise library, by exerciseId
class WorkoutDetailScreen extends StatelessWidget {
  const WorkoutDetailScreen({
    super.key,
    required this.programId,
    required this.workoutId,
  });

  final String programId;
  final String workoutId;

  /// Reuses the Phase 4 workout editor, then saves the result into the program.
  /// Renames the workout and nothing else. Its exercises are changed by
  /// tapping them, dragging them, or Add exercise.
  Future<void> _rename(
    BuildContext context,
    ProgramController controller,
    Workout workout,
  ) async {
    final name = await showRenameDialog(
      context,
      title: 'Workout name',
      current: workout.name,
    );
    if (name == null || !context.mounted) return;
    await _saveWorkout(context, controller, workout.copyWith(name: name));
  }

  /// Everything structural lives in one place: adding, removing, reordering
  /// and prescribing. This screen reads and runs the workout, and can
  /// reorder it in place.
  Future<void> _editWorkout(
    BuildContext context,
    ProgramController controller,
    Workout workout,
  ) async {
    final saved = await Navigator.of(context).push<Workout>(
      MaterialPageRoute<Workout>(
        builder: (_) => WorkoutEditorScreen(workout: workout),
      ),
    );
    if (saved == null || !context.mounted) return;
    await _saveWorkout(context, controller, saved);
  }

  /// Writes [workout] back into its program.
  Future<void> _saveWorkout(
    BuildContext context,
    ProgramController controller,
    Workout workout,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    // Read the program again in case it changed while a screen was open.
    final current = controller.programById(programId);
    if (current == null) return;
    try {
      await controller.saveProgram(
        current.copyWith(
          workouts: [
            for (final w in current.workouts) w.id == workout.id ? workout : w,
          ],
          updatedAt: DateTime.now(),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't save your changes. Try again.")),
      );
    }
  }

  /// Tapping an exercise shows what it is: muscles, equipment, instructions.
  /// How it is prescribed here is edited from the pencil instead.
  void _openExerciseDetail(BuildContext context, PlannedExercise planned) {
    final exercise = ExerciseLibrary.byId(planned.exerciseId);
    if (exercise == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExerciseDetailScreen(
          exercise: exercise,
          planned: planned,
          // Already inside a program; starting a loose session from here
          // would be confusing.
          canStart: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ProgramScope.of(context);
    final sessions = SessionScope.of(context);
    final program = controller.programById(programId);
    final workout = program?.workoutById(workoutId);
    final theme = Theme.of(context);

    if (program == null || workout == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workout')),
        body: const Center(child: Text('This workout no longer exists.')),
      );
    }

    final days = program.daysForWorkout(workout.id);
    final muscles = primaryMusclesOf(workout);
    final active = sessions.activeSession;
    final resumesThis = active != null && active.workoutId == workout.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout'),
        actions: [
          IconButton(
            tooltip: 'Rename workout',
            icon: const Icon(Icons.edit),
            onPressed: () => _rename(context, controller, workout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            workout.name,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (workout.focus.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(workout.focus, style: theme.textTheme.titleMedium),
            ),
          const SizedBox(height: 16),
          _LabeledChips(
            label: 'Scheduled',
            labels: [for (final d in days) d.label],
            emptyText: 'Not scheduled',
          ),
          Text(
            'Muscles worked',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          MuscleGallery(muscles: muscles, emptyText: 'No exercises yet'),
          const SizedBox(height: 12),
          _LabeledChips(
            label: 'Equipment',
            labels: [for (final e in equipmentOf(workout)) e.label],
            emptyText: 'None needed',
          ),
          Text(
            '${pluralize(workout.exerciseCount, 'exercise')} · ${pluralize(workout.totalSets, 'set')}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Text(
            'Tap an exercise to read about it, or long-press and drag to '
            'reorder. Use Edit workout to add, remove or prescribe.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorderItem: (oldIndex, newIndex) {
              _saveWorkout(
                context,
                controller,
                workout.copyWith(
                  exercises: reorderList(workout.exercises, oldIndex, newIndex),
                ),
              );
            },
            children: [
              for (final planned in workout.exercises)
                Padding(
                  key: ValueKey('planned-${planned.id}'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PlannedExerciseCard(
                    planned: planned,
                    onTap: () => _openExerciseDetail(context, planned),
                  ),
                ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          _editWorkout(context, controller, workout),
                      child: const Text('Edit workout'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: workout.exercises.isEmpty
                          ? null
                          : () => startOrResumeWorkout(
                              context,
                              program: program,
                              workout: workout,
                            ),
                      child: Text(
                        resumesThis ? 'Resume workout' : 'Start workout',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One planned exercise: the library's exercise card plus this workout's
/// prescription (from PlannedExercise) underneath.
class _PlannedExerciseCard extends StatelessWidget {
  const _PlannedExerciseCard({required this.planned, required this.onTap});

  final PlannedExercise planned;

  /// Opens the exercise's own screen: what it trains, how to do it.
  /// Adding, removing and prescribing all live in Edit workout.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final exercise = ExerciseLibrary.byId(planned.exerciseId);

    // One compact line per set: "Working   8–12 reps · 40 kg · Rest 90s".
    final footer = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final set in planned.plannedSets)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 76,
                  child: Text(
                    set.setType.shortLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(child: Text(plannedSetDetails(set))),
              ],
            ),
          ),
        if (planned.note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(planned.note),
          ),
      ],
    );

    // Only possible if an exercise id is no longer in the library.
    if (exercise == null) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          title: const Text('Unknown exercise'),
          subtitle: footer,
          onTap: onTap,
        ),
      );
    }

    return ExerciseCard(exercise: exercise, footer: footer, onTap: onTap);
  }
}

/// A label with a single scrolling row of chips under it.
class _LabeledChips extends StatelessWidget {
  const _LabeledChips({
    required this.label,
    required this.labels,
    this.emptyText,
  });

  final String label;
  final List<String> labels;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          ChipRow(labels: labels, emptyText: emptyText),
        ],
      ),
    );
  }
}
