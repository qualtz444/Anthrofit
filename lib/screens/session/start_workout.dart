import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../state/profile_scope.dart';
import '../../state/session_scope.dart';
import '../program/planned_exercise_edit_screen.dart';
import 'workout_session_screen.dart';
import '../../core/snack_bar_timing.dart';

/// Before a workout starts: when the health answers call for medical
/// clearance and none has been reported, says so and lets the person stop.
/// Returns true to go ahead.
Future<bool> confirmHealthClearance(BuildContext context) async {
  final scope = context.getInheritedWidgetOfExactType<ProfileScope>();
  final controller = scope?.notifier;
  final profile = controller?.profile;
  if (controller == null || profile == null || !profile.needsClearance) {
    return true;
  }
  final cleared = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Medical clearance first'),
      content: Text(parqAdvice(ParqConcern.clearanceFirst)!),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          key: const ValueKey('clearance-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('A doctor has cleared me'),
        ),
      ],
    ),
  );
  if (cleared != true) return false;
  await controller.save(profile.copyWith(medicallyCleared: true));
  return true;
}

/// Opens the workout session screen for the session already in progress.
Future<void> openActiveSession(BuildContext context) async {
  await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(builder: (_) => const WorkoutSessionScreen()),
  );
}

/// Asks whether rep-based sets should open the existing guided set flow
/// automatically. Counts are still reviewed and logged in the workout screen.
Future<bool?> _chooseGuidedMode(BuildContext context) async => showDialog<bool>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: const Text('Choose workout mode'),
    content: const Text(
      'Use the camera to count reps? You can correct any count. Exercises '
      'without camera support use the tap counter.',
    ),
    actions: [
      TextButton(
        key: const ValueKey('start-manual-workout'),
        onPressed: () => Navigator.of(dialogContext).pop(false),
        child: const Text('Manual logging'),
      ),
      FilledButton(
        key: const ValueKey('start-guided-workout'),
        onPressed: () => Navigator.of(dialogContext).pop(true),
        child: const Text('Guided workout'),
      ),
    ],
  ),
);

/// The one way to start a workout (used by Workout Detail and Home).
/// Starts a new session, or resumes the one in progress. Only one session can
/// be in progress at a time, so if a different workout is unfinished the user
/// chooses what to do with it.
Future<void> startOrResumeWorkout(
  BuildContext context, {
  required TrainingProgram program,
  required Workout workout,
}) async {
  if (!await confirmHealthClearance(context) || !context.mounted) return;
  final sessions = SessionScope.of(context, listen: false);
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final active = sessions.activeSession;

  var shouldStart = true;
  var guidedMode = false;
  if (active != null) {
    if (active.workoutId == workout.id) {
      shouldStart = false; // resume this workout
      guidedMode = active.guidedMode;
    } else {
      final choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Workout in progress'),
          content: Text(
            'You have an unfinished ${active.workoutName} workout. '
            'Resume it, or discard it and start ${workout.name}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('discard'),
              child: const Text('Discard and start'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('resume'),
              child: const Text('Resume'),
            ),
          ],
        ),
      );
      if (choice == null || !context.mounted) return;
      shouldStart = choice == 'discard';
      if (!shouldStart) guidedMode = active.guidedMode;
    }
  }

  if (shouldStart) {
    final choice = await _chooseGuidedMode(context);
    if (choice == null || !context.mounted) return;
    guidedMode = choice;
    try {
      await sessions.startSession(program, workout, guidedMode: guidedMode);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          duration: kSnackBarDuration,
          persist: false,
          content: Text("Couldn't start the workout. Try again."),
        ),
      );
      return;
    }
  }
  await navigator.push<bool>(
    MaterialPageRoute<bool>(builder: (_) => const WorkoutSessionScreen()),
  );
}

/// Starts a one-exercise session with no program behind it.
///
/// The user sets it up first: how many sets, what reps, what load, how much
/// rest, in the same editor the planner uses. Backing out of that cancels
/// the whole thing, so nothing starts by accident.
///
/// Nothing is added to the user's programs: the session is made on the spot
/// and recorded in history like any other, with no program name.
/// If a different workout is unfinished, the user chooses what to do with it,
/// exactly as when starting a planned workout.
Future<void> startQuickWorkout(
  BuildContext context, {
  required Exercise exercise,
}) async {
  if (!await confirmHealthClearance(context) || !context.mounted) return;
  final sessions = SessionScope.of(context, listen: false);
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final active = sessions.activeSession;

  if (active != null) {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Workout in progress'),
        content: Text(
          'You have an unfinished ${active.workoutName} workout. '
          'Resume it, or discard it and start ${exercise.name}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('discard'),
            child: const Text('Discard and start'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('resume'),
            child: const Text('Resume'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'resume') {
      await navigator.push<bool>(
        MaterialPageRoute<bool>(builder: (_) => const WorkoutSessionScreen()),
      );
      return;
    }
  }

  // Set it up before starting: the defaults are only a starting point.
  final planned = await navigator.push<PlannedExercise>(
    MaterialPageRoute<PlannedExercise>(
      builder: (_) => PlannedExerciseEditScreen(
        planned: PlannedExercise.withDefaults(
          exercise.id,
          isCardio: exercise.exerciseType == ExerciseType.cardio,
        ),
        title: 'Set up ${exercise.name}',
        doneLabel: 'Start workout',
      ),
    ),
  );
  if (planned == null || !context.mounted) return;

  try {
    final guidedMode = await _chooseGuidedMode(context);
    if (guidedMode == null || !context.mounted) return;
    await sessions.startQuickSession(
      exercise,
      planned: planned,
      guidedMode: guidedMode,
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(
        duration: kSnackBarDuration,
        persist: false,
        content: Text("Couldn't start the workout. Try again."),
      ),
    );
    return;
  }
  await navigator.push<bool>(
    MaterialPageRoute<bool>(builder: (_) => const WorkoutSessionScreen()),
  );
}
