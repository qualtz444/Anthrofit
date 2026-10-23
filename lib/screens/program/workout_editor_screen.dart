import 'package:flutter/material.dart';

import '../../core/list_utils.dart';
import '../../core/set_labels.dart';
import '../../data/exercise_library.dart';
import '../../models/models.dart';
import '../exercises/exercise_library_screen.dart';
import 'planned_exercise_edit_screen.dart';

/// Creates or edits one workout template: name, focus, and its exercises
/// (add, remove, reorder, edit sets/reps/rest/note).
///
/// Nothing is saved to storage here. "Done" pops with the updated Workout and
/// the program planner keeps it in its draft until "Save program".
class WorkoutEditorScreen extends StatefulWidget {
  const WorkoutEditorScreen({
    super.key,
    required this.workout,
    this.isNew = false,
    this.notice,
  });

  final Workout workout;
  final bool isNew;

  /// Optional explanation shown above the exercises (e.g. why a template
  /// workout starts empty).
  final String? notice;

  @override
  State<WorkoutEditorScreen> createState() => _WorkoutEditorScreenState();
}

class _WorkoutEditorScreenState extends State<WorkoutEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _focus;
  late List<PlannedExercise> _exercises;
  bool _showErrors = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.workout.name);
    _focus = TextEditingController(text: widget.workout.focus);
    _exercises = List.of(widget.workout.exercises);
  }

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _addExercises() async {
    final picked = await Navigator.of(context).push<List<Exercise>>(
      MaterialPageRoute<List<Exercise>>(
        builder: (_) => const ExerciseLibraryScreen(pickMode: true),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _exercises = [
        ..._exercises,
        for (final exercise in picked)
          PlannedExercise.withDefaults(
            exercise.id,
            isCardio: exercise.exerciseType == ExerciseType.cardio,
          ),
      ];
    });
  }

  Future<void> _editExercise(int index) async {
    final updated = await Navigator.of(context).push<PlannedExercise>(
      MaterialPageRoute<PlannedExercise>(
        builder: (_) => PlannedExerciseEditScreen(planned: _exercises[index]),
      ),
    );
    if (updated == null || !mounted) return;
    final next = [..._exercises];
    next[index] = updated;
    setState(() => _exercises = next);
  }

  void _removeExercise(int index) {
    final next = [..._exercises];
    next.removeAt(index);
    setState(() => _exercises = next);
  }

  void _done() {
    final formOk = _formKey.currentState!.validate();
    if (!formOk || _exercises.isEmpty) {
      setState(() => _showErrors = true);
      return;
    }
    Navigator.of(context).pop(
      widget.workout.copyWith(
        name: _name.text.trim(),
        focus: _focus.text.trim(),
        exercises: _exercises,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'New workout' : 'Edit workout'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Workout name',
                    hintText: 'e.g. Upper A',
                    border: OutlineInputBorder(),
                  ),
                  validator: (text) => (text == null || text.trim().isEmpty)
                      ? 'Enter a workout name'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _focus,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Focus (optional)',
                    hintText: 'e.g. Upper body',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Exercises', style: theme.textTheme.titleMedium),
                if (widget.notice != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      widget.notice!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                if (_exercises.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No exercises yet.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    onReorderItem: (oldIndex, newIndex) {
                      setState(() {
                        _exercises = reorderList(
                          _exercises,
                          oldIndex,
                          newIndex,
                        );
                      });
                    },
                    children: [
                      for (var i = 0; i < _exercises.length; i++)
                        _ExerciseRow(
                          key: ValueKey(_exercises[i].id),
                          index: i,
                          planned: _exercises[i],
                          onTap: () => _editExercise(i),
                          onRemove: () => _removeExercise(i),
                        ),
                    ],
                  ),
                if (_showErrors && _exercises.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Add at least one exercise',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _addExercises,
                  icon: const Icon(Icons.add),
                  label: const Text('Add exercises'),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _done,
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({
    super.key,
    required this.index,
    required this.planned,
    required this.onTap,
    required this.onRemove,
  });

  final int index;
  final PlannedExercise planned;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final name =
        ExerciseLibrary.byId(planned.exerciseId)?.name ?? 'Unknown exercise';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(plannedSetsSummary(planned.plannedSets)),
            if (planned.note.isNotEmpty) Text(planned.note),
          ],
        ),
        trailing: IconButton(
          tooltip: 'Remove exercise',
          icon: const Icon(Icons.close),
          onPressed: onRemove,
        ),
        onTap: onTap,
      ),
    );
  }
}
