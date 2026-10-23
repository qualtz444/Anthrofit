import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/set_labels.dart';
import '../../data/training_stats.dart';
import '../../models/models.dart';
import '../../state/session_scope.dart';
import '../../core/snack_bar_timing.dart';

/// Record of one completed workout: what the user ACTUALLY did. The whole
/// workout, or one exercise in it, can be deleted (logged by mistake); sets
/// are never edited.
/// The "Target" line is the plan as it was when the workout started (saved
/// inside the session). It is shown separately and never mixed with actuals.
/// Nothing here looks at the current program or the exercise library.
class WorkoutHistoryDetailScreen extends StatelessWidget {
  const WorkoutHistoryDetailScreen({super.key, required this.session});

  final WorkoutSession session;

  /// Deletes this workout after asking, then goes back to the history.
  Future<void> _confirmDelete(BuildContext context) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete workout?'),
        content: Text(
          '${session.workoutName} on '
          '${formatDate(sessionDate(session), today: DateTime.now())} will be '
          'removed from your history and Progress. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SessionScope.of(
        context,
        listen: false,
      ).deleteCompletedSession(session.id);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't delete the workout. Try again.")),
      );
      return;
    }
    navigator.pop();
    messenger.showSnackBar(const SnackBar(duration: kSnackBarDuration, persist: false, content: Text('Workout deleted')));
  }

  /// Deletes one exercise after asking. The last exercise with sets takes
  /// the whole workout with it, and the dialog says so.
  Future<void> _confirmDeleteExercise(
    BuildContext context,
    WorkoutSession current,
    ExerciseLog log,
  ) async {
    final theme = Theme.of(context);
    final isLast = !current.exerciseLogs.any(
      (l) => l.id != log.id && l.completedSets.isNotEmpty,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${log.exerciseName}?'),
        content: Text(
          isLast
              ? 'It is the only exercise in this workout, so the whole '
                    'workout will be removed from your history and Progress. '
                    'This cannot be undone.'
              : 'Its sets will be removed from this workout, your history '
                    'and Progress. The rest of the workout stays. This cannot '
                    'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final bool removedWorkout;
    try {
      removedWorkout = await SessionScope.of(
        context,
        listen: false,
      ).deleteCompletedExercise(sessionId: current.id, exerciseLogId: log.id);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          duration: kSnackBarDuration,
          persist: false,
          content: Text("Couldn't delete the exercise. Try again."),
        ),
      );
      return;
    }
    if (removedWorkout) navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        duration: kSnackBarDuration,
        persist: false,
        content: Text(
          removedWorkout ? 'Workout deleted' : '${log.exerciseName} deleted',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The saved version, so a deleted exercise disappears straight away.
    final session = SessionScope.of(context).completedSessions.firstWhere(
      (s) => s.id == this.session.id,
      orElse: () => this.session,
    );
    final summary = summarize([session]);
    final duration = session.duration ?? Duration.zero;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout'),
        actions: [
          IconButton(
            tooltip: 'Delete workout',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            session.workoutName,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            formatDate(sessionDate(session), today: DateTime.now()),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          // The facts fold away: one line when closed, every detail open.
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              key: const ValueKey('history-details'),
              shape: const Border(),
              collapsedShape: const Border(),
              leading: Icon(
                Icons.info_outline,
                color: theme.colorScheme.primary,
              ),
              title: const Text('Workout details'),
              subtitle: Text(
                [
                  formatDuration(duration),
                  pluralize(session.completedSetCount, 'set'),
                  if (summary.weightedSets > 0) formatVolume(summary.volumeKg),
                ].join(' · '),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The program's name as it was when the workout was done.
                if (session.programName.isNotEmpty)
                  _LabeledValue(label: 'Program', value: session.programName),
                _LabeledValue(
                  label: 'Duration',
                  value: formatDuration(duration),
                ),
                _LabeledValue(
                  label: 'Completed',
                  value:
                      '${pluralize(exerciseCountOf(session), 'exercise')} · '
                      '${pluralize(session.completedSetCount, 'set')}',
                ),
                if (summary.weightedSets > 0)
                  _LabeledValue(
                    label: 'Total volume',
                    value: formatVolume(summary.volumeKg),
                  ),
                if (summary.bodyweightSets > 0)
                  _LabeledValue(
                    label: 'No weight logged',
                    value:
                        '${pluralize(summary.bodyweightSets, 'set')} · '
                        '${summary.bodyweightReps} reps',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Exercises', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final log in session.exerciseLogs)
            if (log.completedSets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ExerciseLogCard(
                  log: log,
                  onDelete: () =>
                      _confirmDeleteExercise(context, session, log),
                ),
              ),
        ],
      ),
    );
  }
}

class _ExerciseLogCard extends StatelessWidget {
  const _ExerciseLogCard({required this.log, required this.onDelete});

  final ExerciseLog log;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    log.exerciseName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (log.skipped)
                  Chip(
                    label: const Text('Skipped'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: theme.colorScheme.errorContainer,
                    labelStyle: TextStyle(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                IconButton(
                  key: ValueKey('delete-exercise-${log.id}'),
                  tooltip: 'Delete exercise',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: onDelete,
                ),
              ],
            ),
            // What it stood in for, when the exercise was swapped mid-session.
            if (log.wasSubstituted)
              Text(
                'Instead of ${log.substitutedForName}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Actual',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < log.sets.length; i++)
              if (log.sets[i].isCompleted)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Set ${log.sets[i].setNumber} · ${log.sets[i].setType.shortLabel}',
                            ),
                          ),
                          Text(
                            formatSetLog(log.sets[i]),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      // The plan as it was when this workout started.
                      if (log.plannedSetFor(i) != null)
                        Text(
                          'Target: ${plannedTargetLabel(log.plannedSetFor(i)!)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _LabeledValue extends StatelessWidget {
  const _LabeledValue({required this.label, required this.value});

  final String label;
  final String value;

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
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
