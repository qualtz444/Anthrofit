import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/program_labels.dart';
import '../../models/models.dart';
import '../../state/measurement_scope.dart';
import '../../state/program_scope.dart';
import '../library/library_screen.dart';
import '../exercises/manage_exercises_screen.dart';
import '../scan/personalize_program_screen.dart';
import '../scan/scan_choice_screen.dart';
import '../widgets/empty_state.dart';
import '../widgets/first_scan_prompt.dart';
import '../widgets/today_workout_card.dart';
import 'program_detail_screen.dart';
import 'create_program_screen.dart';
import 'week_row.dart';

/// Program tab:
///  - no program yet  -> empty state with Create program
///  - otherwise       -> today's workout, the active program's weekly
///                       schedule, and all saved programs
/// The Exercise Library is always one tap away.
class ProgramScreen extends StatelessWidget {
  const ProgramScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ProgramScope.of(context);
    final programs = controller.programs;
    final active = controller.activeProgram;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final latestScan = context
        .dependOnInheritedWidgetOfExactType<MeasurementScope>()
        ?.notifier
        ?.latest;

    return Scaffold(
      appBar: AppBar(title: const Text('Program')),
      floatingActionButton: programs.isEmpty
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('create-program'),
              heroTag: 'create-program-fab',
              onPressed: () => startProgramCreation(context),
              icon: const Icon(Icons.add),
              label: const Text('Create program'),
            ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: const Text('Library'),
            subtitle: const Text('Ready-made programs and exercises'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const LibraryScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: const Text('Manage exercises'),
            subtitle: const Text('Add, edit or remove your own exercises'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ManageExercisesScreen(),
                ),
              );
            },
          ),
          // The Personalized Plan, any time: built from the latest body
          // proportion scan. Nothing is saved until it is confirmed there.
          ListTile(
            key: const ValueKey('open-personalized-plan'),
            leading: const Icon(Icons.auto_awesome),
            title: const Text('Personalized plan'),
            subtitle: Text(
              latestScan == null
                  ? 'Do a body scan to get a plan built for you'
                  : 'Training and nutrition from your scan of '
                        '${formatDate(latestScan.takenAt, today: now)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => latestScan == null
                    ? const ScanChoiceScreen()
                    : PersonalizeProgramScreen(measurement: latestScan),
              ),
            ),
          ),
          const Divider(height: 1),
          if (programs.isEmpty && isFirstTimeUser(context))
            // New here: a scan first, not "Create program".
            const FirstScanPrompt(title: 'No program yet.')
          else if (programs.isEmpty)
            EmptyState(
              title: 'No program yet.',
              message: 'Create a program to plan your training week.',
              actionLabel: 'Create program',
              onAction: () => startProgramCreation(context),
              actionKey: const ValueKey('create-program'),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TodayWorkoutCard(now: now, offerCreate: false),
            ),
            if (active != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: _WeeklySchedule(program: active, now: now),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text('My programs', style: theme.textTheme.titleMedium),
            ),
            for (final program in programs)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _ProgramCard(
                  program: program,
                  isActive: controller.activeProgramId == program.id,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// The active program's week, Monday to Sunday, as a row of boxes: each
/// shows the day and its workout, or "Rest". Today is outlined.
class _WeeklySchedule extends StatelessWidget {
  const _WeeklySchedule({required this.program, required this.now});

  final TrainingProgram program;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Active program: ${program.name}',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        WeekRow(program: program, now: now),
      ],
    );
  }
}

/// A program shown like a folder: its name, status and days, and how many
/// workouts it contains.
class _ProgramCard extends StatelessWidget {
  const _ProgramCard({required this.program, required this.isActive});

  final TrainingProgram program;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: isActive ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProgramDetailScreen(programId: program.id),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                program.archived
                    ? Icons.inventory_2_outlined
                    : Icons.folder_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      program.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(programStatusLine(program, isActive: isActive)),
                    Text(
                      pluralize(program.workouts.length, 'workout'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
