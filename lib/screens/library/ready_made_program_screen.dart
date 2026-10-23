import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/ready_made_programs.dart';
import '../../state/program_scope.dart';
import '../program/program_detail_screen.dart';
import '../widgets/chip_row.dart';
import '../../core/snack_bar_timing.dart';

/// What a ready-made program contains, before it is added.
///
/// Read-only: nothing here changes until "Add to my programs", which makes a
/// normal user-owned copy with its own ids. The recipe itself is const and
/// can never be edited.
class ReadyMadeProgramScreen extends StatefulWidget {
  const ReadyMadeProgramScreen({super.key, required this.recipe});

  final ReadyMadeProgram recipe;

  @override
  State<ReadyMadeProgramScreen> createState() => _ReadyMadeProgramScreenState();
}

class _ReadyMadeProgramScreenState extends State<ReadyMadeProgramScreen> {
  bool _adding = false;

  Future<void> _add() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final programs = ProgramScope.of(context, listen: false);

    setState(() => _adding = true);
    final program = programFromReadyMade(widget.recipe);
    try {
      await programs.saveProgram(program);
    } catch (_) {
      if (!mounted) return;
      setState(() => _adding = false);
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't add the program. Try again.")),
      );
      return;
    }
    if (!mounted) return;

    messenger.showSnackBar(
      SnackBar(duration: kSnackBarDuration, persist: false, content: Text('${program.name} added to your programs')),
    );
    // Straight to the copy, which behaves like any other program from here.
    navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ProgramDetailScreen(programId: program.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recipe = widget.recipe;
    final workouts = workoutsFor(recipe);

    return Scaffold(
      appBar: AppBar(title: Text(recipe.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(recipe.summary, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          _Labelled(label: 'Goal', value: recipe.goal.label),
          _Labelled(label: 'Suits', value: recipe.experience.label),
          _Labelled(
            label: 'Training days',
            value: '${recipe.days.length} a week',
          ),
          const SizedBox(height: 8),
          Text('Days', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          ChipRow(labels: [for (final d in recipe.days) d.label]),
          const SizedBox(height: 16),
          Text('Muscles trained', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          ChipRow(
            labels: [for (final m in musclesOf(recipe)) m.label],
            emptyText: 'Nothing yet',
          ),
          const SizedBox(height: 24),
          Text('Workouts', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (workouts.isEmpty)
            Text(
              'This program starts empty, for you to fill in.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          for (final workout in workouts)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                  workout.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${pluralize(workout.exerciseCount, 'exercise')} · '
                  '${pluralize(workout.totalSets, 'set')}',
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _adding ? null : _add,
              child: const Text('Add to my programs'),
            ),
          ),
        ),
      ),
    );
  }
}

class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
