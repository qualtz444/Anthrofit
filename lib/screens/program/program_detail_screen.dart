import 'package:flutter/material.dart';

import '../../coaching/program_review.dart';
import '../../community/post_builder.dart';
import '../../core/format.dart';
import '../../core/program_labels.dart';
import '../../data/workout_summary.dart';
import '../../data/workout_templates.dart';
import '../../models/models.dart';
import '../../state/program_controller.dart';
import '../../state/profile_scope.dart';
import '../../state/program_scope.dart';
import '../../state/measurement_scope.dart';
import '../../state/session_scope.dart';
import '../community/share_to_friends.dart';
import '../scan/personalize_program_screen.dart';
import '../scan/scan_choice_screen.dart';
import '../widgets/chip_row.dart';
import '../widgets/rename_dialog.dart';
import 'schedule_edit_screen.dart';
import 'week_row.dart';
import 'template_picker_screens.dart';
import 'workout_detail_screen.dart';
import 'workout_editor_screen.dart';
import '../../core/snack_bar_timing.dart';

/// A program opened like a folder: goal, status, schedule, the workouts it
/// contains, and the actions that make sense for its current state.
///   Active:      Edit, Archive, Duplicate, Delete
///   Not active:  Edit, Activate, Archive, Duplicate, Delete
///   Archived:    Edit, Activate, Duplicate, Delete
class ProgramDetailScreen extends StatelessWidget {
  const ProgramDetailScreen({super.key, required this.programId});

  final String programId;

  /// Runs a program change, and tells the user if it could not be saved.
  Future<bool> _run(
    BuildContext context,
    Future<void> Function() action,
    String failure,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      return true;
    } catch (_) {
      messenger.showSnackBar(SnackBar(duration: kSnackBarDuration, persist: false, content: Text(failure)));
      return false;
    }
  }

  /// Renames the program and nothing else.
  Future<void> _rename(
    BuildContext context,
    ProgramController controller,
    TrainingProgram program,
  ) async {
    final name = await showRenameDialog(
      context,
      title: 'Program name',
      current: program.name,
    );
    if (name == null || !context.mounted) return;
    await _save(
      context,
      controller,
      program.copyWith(name: name, updatedAt: DateTime.now()),
    );
  }

  /// Adds a workout: choose a type, edit it, then it joins the program.
  ///
  /// The picker returns a WorkoutTemplate, not a Workout: the template is
  /// turned into a seeded workout here, exactly as the planner does.
  Future<void> _addWorkout(
    BuildContext context,
    ProgramController controller,
    TrainingProgram program,
  ) async {
    final template = await Navigator.of(context).push<WorkoutTemplate>(
      MaterialPageRoute<WorkoutTemplate>(
        builder: (_) => const WorkoutTemplateScreen(),
      ),
    );
    if (template == null || !context.mounted) return;

    final seeded = buildWorkoutFromTemplate(template);
    final startsEmptyByDesign =
        template != WorkoutTemplate.custom && seeded.exercises.isEmpty;
    final saved = await Navigator.of(context).push<Workout>(
      MaterialPageRoute<Workout>(
        builder: (_) => WorkoutEditorScreen(
          workout: seeded,
          isNew: true,
          notice: startsEmptyByDesign
              ? 'The exercise library has no ${template.label.toLowerCase()} '
                    'exercises yet, so this workout starts empty.'
              : null,
        ),
      ),
    );
    if (saved == null || !context.mounted) return;
    await _save(
      context,
      controller,
      program.copyWith(
        workouts: [...program.workouts, saved],
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _editWorkout(
    BuildContext context,
    ProgramController controller,
    TrainingProgram program,
    Workout workout,
  ) async {
    final saved = await Navigator.of(context).push<Workout>(
      MaterialPageRoute<Workout>(
        builder: (_) => WorkoutEditorScreen(workout: workout),
      ),
    );
    if (saved == null || !context.mounted) return;
    await _save(
      context,
      controller,
      program.copyWith(
        workouts: [
          for (final w in program.workouts) w.id == saved.id ? saved : w,
        ],
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Deletes a workout, and any scheduled day that pointed at it.
  Future<void> _deleteWorkout(
    BuildContext context,
    ProgramController controller,
    TrainingProgram program,
    Workout workout,
  ) async {
    final days = program.schedule
        .where((s) => s.workoutId == workout.id)
        .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${workout.name}?'),
        content: Text(
          days == 0
              ? 'This workout and its exercises will be removed from the '
                    'program. Workouts you have already logged are kept.'
              : 'This workout and its exercises will be removed, and '
                    '${pluralize(days, 'training day')} will become a rest day. '
                    'Workouts you have already logged are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _save(
      context,
      controller,
      program.copyWith(
        workouts: program.workouts.where((w) => w.id != workout.id).toList(),
        schedule: program.schedule
            .where((s) => s.workoutId != workout.id)
            .toList(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _save(
    BuildContext context,
    ProgramController controller,
    TrainingProgram program,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.saveProgram(program);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't save your changes. Try again.")),
      );
    }
  }

  /// Tapping the status turns the program on or off, after confirming.
  ///
  /// Only one program is followed at a time, so activating one stops
  /// another. The dialog says which, by name, before anything changes.
  /// Neither action touches any program's contents.
  Future<void> _toggleActive(
    BuildContext context,
    ProgramController controller,
    TrainingProgram program,
    bool isActive,
  ) async {
    final current = controller.activeProgram;
    final replacing = !isActive && current != null && current.id != program.id;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          isActive
              ? 'Stop following ${program.name}?'
              : 'Follow ${program.name}?',
        ),
        content: Text(
          isActive
              ? 'Home will stop showing its workouts. The program and its '
                    'history are kept, and you can start following it again at '
                    'any time.'
              : replacing
              ? 'This will stop following ${current.name}, because only '
                    'one program runs at a time. Nothing in either program '
                    'is changed.'
              : 'Home will show this program\'s workouts on their '
                    'training days.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(isActive ? 'Stop following' : 'Activate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final ok = await _run(
      context,
      () => isActive
          ? controller.deactivateProgram(program.id)
          : controller.setActiveProgram(program.id),
      "Couldn't change the active program. Try again.",
    );
    if (!ok) return;
    messenger.showSnackBar(
      SnackBar(duration: kSnackBarDuration, persist: false,
        content: Text(
          isActive
              ? 'No program is active now'
              : '${program.name} is now active',
        ),
      ),
    );
  }

  Future<void> _activate(
    BuildContext context,
    ProgramController controller,
    TrainingProgram program,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _run(
      context,
      () => controller.setActiveProgram(program.id),
      "Couldn't change the active program. Try again.",
    );
    if (ok) {
      messenger.showSnackBar(
        SnackBar(duration: kSnackBarDuration, persist: false, content: Text('${program.name} is now active')),
      );
    }
  }

  Future<void> _archive(
    BuildContext context,
    ProgramController controller,
    TrainingProgram program,
    bool wasActive,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _run(
      context,
      () => controller.archiveProgram(program.id),
      "Couldn't archive the program. Try again.",
    );
    if (ok) {
      messenger.showSnackBar(
        SnackBar(duration: kSnackBarDuration, persist: false,
          content: Text(
            wasActive
                ? '${program.name} archived. No program is active now.'
                : '${program.name} archived',
          ),
        ),
      );
    }
  }

  Future<void> _duplicate(
    BuildContext context,
    ProgramController controller,
    TrainingProgram program,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    TrainingProgram? copy;
    final ok = await _run(context, () async {
      copy = await controller.duplicateProgram(program.id);
    }, "Couldn't duplicate the program. Try again.");
    final created = copy;
    if (ok && created != null) {
      messenger.showSnackBar(
        SnackBar(duration: kSnackBarDuration, persist: false, content: Text('Created ${created.name}')),
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ProgramController controller,
    TrainingProgram program,
  ) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final sessions = SessionScope.of(context, listen: false);

    // An unfinished workout from this program cannot outlive it.
    final hasUnfinished = sessions.activeSession?.programId == program.id;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this program?'),
        content: Text(
          hasUnfinished
              ? 'This will remove the program and its workouts, and discard '
                    'the workout you have in progress. Completed workout '
                    'history will be kept.'
              : 'This will remove the program and its workouts. '
                    'Completed workout history will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      // The unfinished workout goes first: if deleting the program failed
      // afterwards, an orphaned session would be worse than a lost one.
      await sessions.discardSessionForProgram(program.id);
      await controller.deleteProgram(program.id);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false,
          content: Text("Couldn't delete the program. Try again."),
        ),
      );
      return;
    }
    navigator.pop();
  }

  /// Rebuilds this program from its own settings and the latest body
  /// proportion scan, then previews it; saving updates it in place.
  /// Null when there is no profile to compare with (a test harness, say).
  ProgramReview? _reviewFor(BuildContext context, TrainingProgram program) {
    final profile = context
        .dependOnInheritedWidgetOfExactType<ProfileScope>()
        ?.notifier
        ?.profile;
    if (profile == null) return null;
    final sessions =
        context
            .dependOnInheritedWidgetOfExactType<SessionScope>()
            ?.notifier
            ?.completedSessions ??
        const <WorkoutSession>[];
    return reviewProgram(
      program: program,
      profile: profile,
      history: sessions,
    );
  }

  static String _reviewSummary(ProgramReview r) => [
    if (r.proposed != null) 'Goal changed in your profile',
    if (r.notes.isNotEmpty) 'Schedule or session length differs',
    if (r.unscheduledWorkouts.isNotEmpty || r.unplannedMuscles.isNotEmpty)
      'Some muscles get no sets this week',
    if (r.missingEquipment.isNotEmpty) 'Equipment no longer in your profile',
    if (r.struggling.isNotEmpty)
      '${r.struggling.length} exercise${r.struggling.length == 1 ? '' : 's'} '
          'below target lately',
  ].join(' · ');

  /// The preview. Only the re-prescription can be applied from here, and
  /// only on approval; everything else is advice the user acts on.
  Future<void> _showReview(
    BuildContext context,
    ProgramController controller,
    ProgramReview review,
  ) async {
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final proposed = review.proposed;
    final goal = review.goalChange;
    final apply = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Suggested changes'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              if (proposed != null && goal != null) ...[
                Text(
                  'Goal: ${goal.$1?.label ?? 'not set'} → ${goal.$2.label}',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Your exercises, sets, loads and history stay. Only reps and '
                  'rest change to fit the new goal.',
                ),
                for (final c in review.changes)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${c.exerciseName}: ${c.before} → ${c.after}'),
                  ),
                if (review.changes.isEmpty)
                  const Text('Reps and rest already match; only the goal '
                      'label changes.'),
                const SizedBox(height: 12),
              ],
              for (final n in review.notes) ...[
                Text(n),
                const SizedBox(height: 8),
              ],
              if (review.unscheduledWorkouts.isNotEmpty) ...[
                Text(
                  'Not on any training day: '
                  '${review.unscheduledWorkouts.join(', ')}. Use Schedule '
                  'to give ${review.unscheduledWorkouts.length == 1 ? 'it' : 'them'} '
                  'a day.',
                ),
                const SizedBox(height: 8),
              ],
              if (review.unplannedMuscles.isNotEmpty) ...[
                Text(
                  'Your workouts include ${review.unplannedMuscles.join(', ')}, '
                  'but the week as scheduled gives '
                  '${review.unplannedMuscles.length == 1 ? 'it' : 'them'} '
                  '0 direct sets.',
                ),
                const SizedBox(height: 4),
                Text(
                  'Direct sets a week: ${[
                    for (final e in review.weeklySets.entries)
                      if (e.value > 0) '${e.key.label} ${e.value}',
                  ].join(', ')}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
              ],
              if (review.missingEquipment.isNotEmpty) ...[
                Text(
                  'Need equipment your profile no longer lists: '
                  '${review.missingEquipment.join(', ')}. Replace them in '
                  'the workout editor. Nothing is changed for you.',
                ),
                const SizedBox(height: 8),
              ],
              if (review.struggling.isNotEmpty) ...[
                Text(
                  'Below the rep range in the last $kStruggleSessions '
                  'sessions: ${review.struggling.join(', ')}. Consider a '
                  'lighter load or replacing the exercise. Nothing is '
                  'changed for you.',
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(proposed == null ? 'Close' : 'Not now'),
          ),
          if (proposed != null)
            FilledButton(
              key: const ValueKey('apply-review'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Apply new reps and rest'),
            ),
        ],
      ),
    );
    if (apply != true || proposed == null) return;
    await controller.saveProgram(proposed);
    messenger.showSnackBar(
      const SnackBar(duration: kSnackBarDuration, persist: false, content: Text('Program updated. Your history is unchanged.')),
    );
  }

  void _personalize(BuildContext context, TrainingProgram program) {
    final latest = context
        .getInheritedWidgetOfExactType<MeasurementScope>()
        ?.notifier
        ?.latest;
    if (latest == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false,
          content: Text(
            'Do a body proportion scan first: tap the scan button, then '
            'Body proportion scan.',
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PersonalizeProgramScreen(measurement: latest, baseProgram: program),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ProgramScope.of(context);
    final program = controller.programById(programId);
    final theme = Theme.of(context);

    if (program == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Program')),
        body: const Center(child: Text('This program no longer exists.')),
      );
    }

    final isActive = controller.activeProgramId == program.id;
    final days = program.trainingDays;

    return Scaffold(
      appBar: AppBar(
        title: Text(program.name),
        actions: [
          IconButton(
            tooltip: 'Rename program',
            icon: const Icon(Icons.edit),
            onPressed: () => _rename(context, controller, program),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isActive)
            Row(
              children: [
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Text('Active program'),
              ],
            ),
          if (isActive) const SizedBox(height: 16),
          // The short facts go two to a row in boxes, so four of them cost
          // two rows instead of four.
          _FactGrid(
            facts: [
              _Fact(
                'Status',
                programStatusLabel(program, isActive: isActive),
                onTap: () =>
                    _toggleActive(context, controller, program, isActive),
              ),
              _Fact('Goal', program.goal?.label ?? 'Not set'),
              if (program.setup != null) ...[
                _Fact('Session length', program.setup!.sessionDuration.label),
                _Fact('Focus', program.setup!.focus.label),
              ],
            ],
          ),
          const SizedBox(height: 16),
          // Whether the app built this from a body scan. Unknown for
          // programs made by hand or saved before it was recorded.
          if (program.usedScan != null) ...[
            _ScanBasis(program: program),
            const SizedBox(height: 16),
          ],
          // Worked out from the exercises actually in the program, so adding
          // or removing one changes these straight away. The setup answers
          // above say what was ASKED for; these say what it now contains.
          _LabeledChips(
            label: 'Muscles',
            labels: [for (final m in programMuscles(program)) m.label],
            emptyText: 'No exercises yet',
          ),
          _LabeledChips(
            label: 'Equipment',
            labels: [for (final e in programEquipment(program)) e.label],
            emptyText: 'No exercises yet',
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Schedule by day',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Edit schedule',
                icon: const Icon(Icons.edit),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ScheduleEditScreen(program: program),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          // The week as a row of day boxes, as on the Program tab.
          WeekRow(program: program, now: DateTime.now()),
          if (days.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'No training days yet. Use the pencil above to choose them.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text('Workouts', style: theme.textTheme.titleMedium),
              ),
              TextButton.icon(
                onPressed: () => _addWorkout(context, controller, program),
                icon: const Icon(Icons.add),
                label: const Text('Add workout'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (program.workouts.isEmpty)
            Text(
              'This program has no workouts yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          for (final workout in program.workouts)
            Card(
              key: ValueKey('workout-card-${workout.id}'),
              margin: const EdgeInsets.only(bottom: 8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
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
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              workout.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (workout.focus.isNotEmpty) Text(workout.focus),
                            const SizedBox(height: 4),
                            Text(
                              '${pluralize(workout.exerciseCount, 'exercise')} · ${pluralize(workout.totalSets, 'set')}',
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _daysText(program, workout),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit ${workout.name}',
                        icon: const Icon(Icons.edit),
                        onPressed: () =>
                            _editWorkout(context, controller, program, workout),
                      ),
                      IconButton(
                        tooltip: 'Delete ${workout.name}',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteWorkout(
                          context,
                          controller,
                          program,
                          workout,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_reviewFor(context, program) case final review?
              when !review.isEmpty && !program.archived) ...[
            const SizedBox(height: 16),
            Card(
              key: const ValueKey('program-review-card'),
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Suggested changes for this program'),
                subtitle: Text(_reviewSummary(review)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showReview(context, controller, review),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!isActive)
                FilledButton(
                  onPressed: () => _activate(context, controller, program),
                  child: const Text('Activate'),
                ),
              if (!program.archived)
                OutlinedButton(
                  onPressed: () =>
                      _archive(context, controller, program, isActive),
                  child: const Text('Archive'),
                ),
              OutlinedButton(
                onPressed: () => _duplicate(context, controller, program),
                child: const Text('Duplicate'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('personalize-with-scan'),
            onPressed: () => _personalize(context, program),
            icon: const Icon(Icons.center_focus_strong),
            label: const Text('Personalize with my latest scan'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('share-program'),
            onPressed: () => shareToFriends(
              context,
              what: 'this program',
              preview:
                  '"${program.name}": ${program.workouts.length} workouts with '
                  'their exercises, sets, reps, rest and schedule. Friends '
                  'can copy it. Its setup and exercise notes stay private.',
              build: (me, friends) => buildProgramPost(
                program: program,
                author: me,
                friendUids: friends,
              ),
            ),
            icon: const Icon(Icons.ios_share),
            label: const Text('Share with friends'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: () => _confirmDelete(context, controller, program),
              child: const Text('Delete program'),
            ),
          ),
        ],
      ),
    );
  }

  static String _daysText(TrainingProgram program, Workout workout) {
    final days = program.daysForWorkout(workout.id);
    if (days.isEmpty) return 'Not scheduled';
    return days.map((d) => d.shortLabel).join(' · ');
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

/// One short label-and-value fact.
class _Fact {
  const _Fact(this.label, this.value, {this.onTap});

  final String label;
  final String value;

  /// Makes the box tappable. Only the status uses this.
  final VoidCallback? onTap;
}

/// Lays short facts out two to a row, each in its own box.
///
/// Two columns rather than a Wrap, so the boxes line up in a grid whatever
/// the text length. An odd number leaves the last box half width, which
/// looks deliberate next to a full row above it.
class _FactGrid extends StatelessWidget {
  const _FactGrid({required this.facts});

  final List<_Fact> facts;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < facts.length; i += 2) {
      final left = facts[i];
      final right = i + 1 < facts.length ? facts[i + 1] : null;
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i + 2 < facts.length ? 8 : 0),
          // IntrinsicHeight gives the row a bounded height, which stretch
          // needs: inside a ListView the height is unbounded, and stretching
          // against that throws during layout.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _FactBox(fact: left)),
                const SizedBox(width: 8),
                Expanded(
                  child: right == null
                      ? const SizedBox.shrink()
                      : _FactBox(fact: right),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

class _FactBox extends StatelessWidget {
  const _FactBox({required this.fact});

  final _Fact fact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final box = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                fact.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (fact.onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.edit,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(fact.value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: fact.onTap == null ? box : InkWell(onTap: fact.onTap, child: box),
    );
  }
}

/// Says whether the app built this program from a body scan, and when that
/// scan was taken. Without one, offers a scan.
class _ScanBasis extends StatelessWidget {
  const _ScanBasis({required this.program});

  final TrainingProgram program;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final used = program.usedScan == true;
    final taken = program.scanTakenAt;
    final from = taken == null ? '' : ' from ${formatShortDate(taken)}';
    // Unknown (older programs) reads as before: built using the scan.
    final changed = program.scanChanged != false;
    return Card(
      key: const ValueKey('program-scan-basis'),
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Icon(
              used ? Icons.center_focus_strong : Icons.person_outline,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                !used
                    ? 'Not based on a body scan'
                    : changed
                    ? 'Built using your body scan$from'
                    : "Your body scan$from was checked but didn't change "
                          'this program',
              ),
            ),
            if (!used)
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ScanChoiceScreen(),
                  ),
                ),
                child: const Text('Scan now'),
              ),
          ],
        ),
      ),
    );
  }
}
