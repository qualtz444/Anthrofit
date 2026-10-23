import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/training_stats.dart';
import '../../models/models.dart';
import '../../state/program_scope.dart';
import '../../state/session_scope.dart';
import '../program/create_program_screen.dart';
import '../program/workout_detail_screen.dart';
import '../session/start_workout.dart';
import 'empty_state.dart';
import 'first_scan_prompt.dart';

/// "What do I do today?" Shared by Home and the Program tab.
///
///  1. A workout is unfinished        -> Resume workout (any workout)
///  2. No active program              -> No active program / Create program
///  3. Nothing scheduled for today    -> Rest day
///  4. A workout is scheduled today   -> its summary and Start workout
///
/// Today is the weekday of [now]. Another day's workout is never shown here.
class TodayWorkoutCard extends StatelessWidget {
  const TodayWorkoutCard({
    super.key,
    required this.now,
    this.offerCreate = true,
  });

  final DateTime now;

  /// Whether the "no active program" state shows a Create program button.
  final bool offerCreate;

  @override
  Widget build(BuildContext context) {
    final program = ProgramScope.of(context).activeProgram;
    final sessions = SessionScope.of(context);
    final active = sessions.activeSession;

    if (active != null) {
      return _CardShell(
        label: 'Workout in progress',
        title: active.workoutName,
        subtitle: '${pluralize(active.completedSetCount, 'set')} logged',
        action: FilledButton(
          onPressed: () => openActiveSession(context),
          child: const Text('Resume workout'),
        ),
      );
    }

    if (program == null) {
      // New here: a scan first, not "Create program".
      if (offerCreate && isFirstTimeUser(context)) {
        return const Card(
          margin: EdgeInsets.zero,
          child: Center(child: FirstScanPrompt(title: 'No active program')),
        );
      }
      final hasPrograms = ProgramScope.of(context).programs.isNotEmpty;
      return Card(
        margin: EdgeInsets.zero,
        child: EmptyState(
          title: 'No active program',
          message: hasPrograms
              ? 'Activate one of your programs, or create a new one.'
              : 'Create a program to plan your training week.',
          actionLabel: offerCreate ? 'Create program' : null,
          onAction: offerCreate ? () => startProgramCreation(context) : null,
          actionKey: const ValueKey('create-program'),
        ),
      );
    }

    final todaysWorkouts = program.workoutsForDay(Weekday.fromDateTime(now));
    if (todaysWorkouts.isEmpty) {
      return _CardShell(
        label: "Today's workout",
        title: 'Rest day',
        subtitle: 'Nothing is scheduled in ${program.name} today.',
      );
    }

    // A day can hold more than one workout. The first one not yet done is
    // the one offered; once they are all done, the last is shown as
    // completed rather than nothing at all.
    bool isDone(Workout w) => sessions.completedSessions.any(
      (s) => s.workoutId == w.id && sessionDate(s) == dateOnly(now),
    );
    final remaining = todaysWorkouts.where((w) => !isDone(w)).toList();
    final workout = remaining.isEmpty ? todaysWorkouts.last : remaining.first;
    final doneToday = remaining.isEmpty;
    final position = todaysWorkouts.length > 1
        ? ' · ${todaysWorkouts.indexOf(workout) + 1} of '
              '${todaysWorkouts.length} today'
        : '';

    return _CardShell(
      label: "Today's workout",
      title: workout.name,
      subtitle:
          '${pluralize(workout.exerciseCount, 'exercise')} · ${pluralize(workout.totalSets, 'set')}$position',
      note: doneToday
          ? (todaysWorkouts.length > 1
                ? 'All of today\'s workouts are done'
                : 'Completed today')
          : null,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WorkoutDetailScreen(
              programId: program.id,
              workoutId: workout.id,
            ),
          ),
        );
      },
      action: FilledButton(
        onPressed: workout.exercises.isEmpty
            ? null
            : () => startOrResumeWorkout(
                context,
                program: program,
                workout: workout,
              ),
        child: const Text('Start workout'),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.label,
    required this.title,
    this.subtitle,
    this.note,
    this.onTap,
    this.action,
  });

  final String label;
  final String title;
  final String? subtitle;
  final String? note;
  final VoidCallback? onTap;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null) Text(subtitle!),
              if (note != null)
                Text(
                  note!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              if (action != null) ...[
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: action),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
