import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/set_labels.dart';
import '../../models/models.dart';
import '../../recommendation/personalization_service.dart';
import '../../recommendation/prescription_rules.dart';
import '../../recommendation/program_recommender.dart';
import '../../recommendation/recommendation_engine.dart';
import '../../recommendation/weekly_volume.dart';
import '../../state/profile_scope.dart';
import '../../state/program_scope.dart';
import '../nutrition/nutrition_targets_card.dart';
import '../nutrition/sample_day_screen.dart';
import '../program/program_detail_screen.dart';
import '../widgets/chip_row.dart';
import 'scan_choice_screen.dart';
import '../../core/snack_bar_timing.dart';

/// The Personalized Plan: a generated program and the nutrition targets that
/// go with it, on two tabs of one page.
///
///   Training   the weekly schedule, each workout's exercises with sets,
///              reps and rest, and swaps for each exercise. From the usual
///              recommender (see personalize_program_screen.dart).
///   Nutrition  daily calories and macros from the nutrition service, and
///              example meals. Read from the profile, which the scan has
///              already updated; not part of the program.
///
/// Nothing exists in the user's programs until Confirm. The active program
/// stays active unless the user picks "Replace current" (and is then
/// archived, not deleted). After confirming, the page stays open so both
/// tabs can still be read; "Open program" or "Done" leave it.
class PersonalizedPlanScreen extends StatefulWidget {
  const PersonalizedPlanScreen({
    super.key,
    required this.recommended,
    required this.source,
    this.updateProgramId,
  });

  final RecommendedProgram recommended;
  final SetupSource source;

  /// When set, this plan rebuilds an existing program: confirming replaces
  /// that program's workouts, schedule and setup in place, keeping its id,
  /// name, status and workout history.
  final String? updateProgramId;

  @override
  State<PersonalizedPlanScreen> createState() => _PersonalizedPlanScreenState();
}

class _PersonalizedPlanScreenState extends State<PersonalizedPlanScreen> {
  bool _saving = false;

  /// With a program already active: replace it (it is archived, not
  /// deleted) or add this one alongside it. Adding is the default, because
  /// it changes nothing the user already has.
  bool _replace = false;

  /// Set once confirmed: the saved program, and what happened to it.
  String? _savedProgramId;
  String? _savedMessage;

  bool get _confirmed => _savedProgramId != null;

  /// Writes the rebuilt workouts into the existing program.
  Future<void> _update(String programId) async {
    final messenger = ScaffoldMessenger.of(context);
    final programs = ProgramScope.of(context, listen: false);
    final existing = programs.programById(programId);
    if (existing == null) return;
    final rebuilt = widget.recommended.program;

    setState(() => _saving = true);
    try {
      await programs.saveProgram(
        existing
            .copyWith(
              goal: rebuilt.goal,
              setup: rebuilt.setup,
              workouts: rebuilt.workouts,
              schedule: rebuilt.schedule,
              updatedAt: DateTime.now(),
            )
            .withScanBasis(
              used: rebuilt.usedScan ?? false,
              takenAt: rebuilt.scanTakenAt,
              changed: rebuilt.scanChanged,
            ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false,
          content: Text("Couldn't update the program. Try again."),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _savedProgramId = programId;
      _savedMessage = '${existing.name} updated.';
    });
  }

  Future<void> _confirm() async {
    final messenger = ScaffoldMessenger.of(context);
    final programs = ProgramScope.of(context, listen: false);
    final program = widget.recommended.program;
    final previous = programs.activeProgram;

    setState(() => _saving = true);
    String message;
    try {
      // The usual save. The first program ever saved becomes active by the
      // existing rule.
      await programs.saveProgram(program);
      if (previous != null && _replace) {
        // Replace: the new program is followed from now on, and the old one
        // is archived. Archived, not deleted: its workouts and history stay,
        // and it can be made active again.
        await programs.setActiveProgram(program.id);
        await programs.archiveProgram(previous.id);
        message =
            '${program.name} is now your active program. '
            '${previous.name} was archived.';
      } else if (programs.activeProgramId == null ||
          programs.activeProgramId == program.id) {
        // With nothing active (for example after deactivating), the program
        // the user just asked for is the one to follow.
        await programs.setActiveProgram(program.id);
        message = '${program.name} is now your active program.';
      } else {
        // "Add as new": the active one is left alone.
        message =
            '${program.name} was added. ${previous?.name ?? 'Your current '
                    'program'} is still your active program.';
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't save the program. Try again.")),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _savedProgramId = program.id;
      _savedMessage = message;
    });
  }

  /// Out of the scan flow entirely, then into the program, so Back from it
  /// lands on Home rather than on a scan that is already finished.
  void _openProgram() {
    final navigator = Navigator.of(context);
    final id = _savedProgramId!;
    navigator.popUntil((route) => route.isFirst);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ProgramDetailScreen(programId: id),
      ),
    );
  }

  void _backToHome() =>
      Navigator.of(context).popUntil((route) => route.isFirst);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final updateTarget = widget.updateProgramId == null
        ? null
        : ProgramScope.of(context).programById(widget.updateProgramId!);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Your personalized plan'),
          bottom: const TabBar(
            tabs: [
              Tab(
                key: ValueKey('plan-tab-training'),
                icon: Icon(Icons.fitness_center),
                text: 'Training',
              ),
              Tab(
                key: ValueKey('plan-tab-nutrition'),
                icon: Icon(Icons.restaurant_outlined),
                text: 'Nutrition',
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            if (_confirmed)
              Material(
                key: const ValueKey('plan-confirmed'),
                color: theme.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _savedMessage!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _TrainingTab(
                    recommended: widget.recommended,
                    source: widget.source,
                    saveChoice: _confirmed
                        ? const SizedBox.shrink()
                        : _saveChoice(theme, updateTarget),
                  ),
                  const _NutritionTab(),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _confirmed
                ? Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const ValueKey('plan-done'),
                          onPressed: _backToHome,
                          child: const Text('Done'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          key: const ValueKey('plan-open-program'),
                          onPressed: _openProgram,
                          child: const Text('Open program'),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(
                        key: const ValueKey('plan-confirm'),
                        onPressed: _saving
                            ? null
                            : updateTarget != null
                            ? () => _update(updateTarget.id)
                            : _confirm,
                        child: Text(
                          updateTarget != null
                              ? 'Update ${updateTarget.name}'
                              : 'Confirm program',
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _saving ? null : _backToHome,
                        child: const Text('Back to Home'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// Add or replace, or what updating in place does. Shown at the end of the
  /// Training tab until the plan is confirmed.
  Widget _saveChoice(ThemeData theme, TrainingProgram? updateTarget) {
    final note = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (updateTarget != null) {
      return Text(
        'Updating ${updateTarget.name} replaces its workouts and schedule, '
        'including your manual edits. Its name and history stay.',
        key: const ValueKey('update-note'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      );
    }
    final activeProgram = ProgramScope.of(context).activeProgram;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (activeProgram != null) ...[
          Text(
            'You already follow ${activeProgram.name}',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            key: const ValueKey('save-mode'),
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Add as new'),
                icon: Icon(Icons.add),
              ),
              ButtonSegment(
                value: true,
                label: Text('Replace current'),
                icon: Icon(Icons.swap_horiz),
              ),
            ],
            selected: {_replace},
            onSelectionChanged: _saving
                ? null
                : (choice) => setState(() => _replace = choice.first),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          activeProgram == null
              ? 'It will become your active program.'
              : _replace
              ? 'This becomes your active program. ${activeProgram.name} is '
                    'archived, not deleted: its workouts and history stay, '
                    'and you can make it active again.'
              : '${activeProgram.name} stays your active program. You can '
                    'switch from the status on this program\'s page.',
          key: const ValueKey('save-mode-note'),
          style: note,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Training
// ---------------------------------------------------------------------------

class _TrainingTab extends StatelessWidget {
  const _TrainingTab({
    required this.recommended,
    required this.source,
    required this.saveChoice,
  });

  final RecommendedProgram recommended;
  final SetupSource source;
  final Widget saveChoice;

  /// ACSM 2009's weekly frequency for the user's experience, beside the days
  /// they chose. Guidance only: the user's choice is kept either way.
  List<Widget> _frequencyGuidance(BuildContext context, int days) {
    final experience = context
        .dependOnInheritedWidgetOfExactType<ProfileScope>()
        ?.notifier
        ?.profile
        ?.experience;
    if (experience == null || days == 0) return const [];
    final (low, high) = acsmDaysPerWeek(experience);
    final inRange = days >= low && days <= high;
    final theme = Theme.of(context);
    return [
      const SizedBox(height: 6),
      Text(
        'Suggested: $low–$high days a week at the '
        '${experience.label.toLowerCase()} level.'
        '${inRange ? '' : ' You chose $days; you can change this in your profile.'}',
        key: const ValueKey('acsm-frequency'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: inRange
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.error,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final program = recommended.program;
    final influence = describeScanInfluence(
      usedProportions: recommended.usedProportions,
      tipExercises: recommended.scanTipExercises,
      changedPicks: recommended.scanChangedPicks,
    );
    // Muscles with direct weekly sets, most first.
    final volume = weeklyDirectSets(program).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      key: const PageStorageKey('plan-training'),
      padding: const EdgeInsets.all(16),
      children: [
        // What the program was really built from. Taken from
        // usedProportions, never assumed.
        Card(
          margin: EdgeInsets.zero,
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  influence.usedScan
                      ? Icons.center_focus_strong
                      : Icons.person_outline,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        influence.headline,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(influence.detail, style: theme.textTheme.bodyMedium),
                      if (!influence.usedScan) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          key: const ValueKey('plan-scan-now'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ScanChoiceScreen(),
                            ),
                          ),
                          icon: const Icon(Icons.center_focus_strong),
                          label: const Text('Scan now'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(program.name, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          source == SetupSource.activeProgram
              ? 'Using the settings from your current program.'
              : 'Using your profile settings.',
          style: muted,
        ),
        const SizedBox(height: 12),
        ChipRow(labels: [for (final t in recommended.tags) t.label]),
        const SizedBox(height: 20),
        Text('Weekly schedule', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _WeeklySchedule(program: program),
        ..._frequencyGuidance(context, program.trainingDays.length),
        const SizedBox(height: 16),
        Text('Weekly sets per muscle', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        ChipRow(
          key: const ValueKey('weekly-volume'),
          labels: [for (final e in volume) '${e.key.label} ${e.value}'],
          emptyText: 'No direct sets',
        ),
        const SizedBox(height: 4),
        Text(
          'Direct working sets a week, where the muscle is a main mover. '
          'More weekly sets tended to mean more muscle growth',
          style: muted,
        ),
        if (recommended.note != null) ...[
          const SizedBox(height: 12),
          Text(
            recommended.note!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text('Workouts', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final session in recommended.workouts)
          _WorkoutCard(session: session, program: program),
        const SizedBox(height: 16),
        saveChoice,
      ],
    );
  }
}

/// Monday to Sunday, with the workout on each day or Rest.
class _WeeklySchedule extends StatelessWidget {
  const _WeeklySchedule({required this.program});

  final TrainingProgram program;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('weekly-schedule'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            for (final day in Weekday.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: Text(
                        day.shortLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final workouts = program.workoutsForDay(day);
                          return Text(
                            workouts.isEmpty
                                ? 'Rest'
                                : workouts.map((w) => w.name).join(' + '),
                            style: workouts.isEmpty
                                ? theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  )
                                : theme.textTheme.bodyMedium,
                          );
                        },
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

/// One workout: when it is, and each exercise with its prescription and
/// swaps.
class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({required this.session, required this.program});

  final RecommendedWorkout session;
  final TrainingProgram program;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final workout = session.workout;
    final days = program.daysForWorkout(workout.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              workout.name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (days.isNotEmpty) days.map((d) => d.shortLabel).join(', '),
                pluralize(workout.exerciseCount, 'exercise'),
                pluralize(workout.totalSets, 'set'),
              ].join(' · '),
              style: muted,
            ),
            const SizedBox(height: 8),
            ChipRow(labels: [for (final t in session.tags) t.label]),
            for (final e in session.exercises) _ExerciseRow(exercise: e),
          ],
        ),
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.exercise});

  final RecommendedExercise exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final sets = exercise.planned.plannedSets;
    final subs = exercise.substitutions;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(exercise.exercise.name, style: theme.textTheme.bodyLarge),
          if (sets.isNotEmpty)
            Text(
              // "3 sets · 8–12 reps · Rest 90s"
              '${plannedSetsSummary(sets)} · ${plannedSetDetails(sets.first)}',
              key: ValueKey('prescription-${exercise.exercise.id}'),
              style: theme.textTheme.bodyMedium,
            ),
          if (subs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.swap_horiz,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Swap for: ${subs.map((s) => s.name).join(' or ')}',
                      key: ValueKey('substitutions-${exercise.exercise.id}'),
                      style: muted,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          ChipRow(labels: [for (final t in exercise.tags) t.label]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Nutrition
// ---------------------------------------------------------------------------

/// The nutrition service's targets for the current profile, then example
/// meals. Both read the profile live, so answering the activity question
/// here updates them at once.
class _NutritionTab extends StatefulWidget {
  const _NutritionTab();

  @override
  State<_NutritionTab> createState() => _NutritionTabState();
}

class _NutritionTabState extends State<_NutritionTab> {
  int _day = SampleDayView.today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = context
        .dependOnInheritedWidgetOfExactType<ProfileScope>()
        ?.notifier
        ?.profile;

    // A plain scroll view, not a lazy list: the page is short, and a lazy
    // list rebuilt the targets card each time it scrolled back into view.
    return SingleChildScrollView(
      key: const PageStorageKey('plan-nutrition'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Daily targets from your profile and your latest body composition '
            'estimate. They do not change with the program you choose.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          const NutritionTargetsCard(showExampleMealsLink: false),
          if (profile != null) ...[
            const SizedBox(height: 24),
            Text('Sample meals', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            // The targets are in the card above; only the meals here.
            SampleDayView(profile: profile, dayIndex: _day, showTargets: false),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('plan-another-day'),
                onPressed: () => setState(() => _day++),
                icon: const Icon(Icons.refresh),
                label: const Text('Show another example'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
