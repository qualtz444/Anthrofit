import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../state/exercise_library_scope.dart';
import 'exercise_editor_screen.dart';
import '../../core/snack_bar_timing.dart';

/// Add, edit, duplicate and remove exercises.
///
/// Everything here goes through ExerciseLibraryController, so a change shows
/// up immediately everywhere the library is read, and is saved on the device.
class ManageExercisesScreen extends StatefulWidget {
  const ManageExercisesScreen({super.key});

  @override
  State<ManageExercisesScreen> createState() => _ManageExercisesScreenState();
}

class _ManageExercisesScreenState extends State<ManageExercisesScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openEditor({Exercise? existing}) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ExerciseEditorScreen(existing: existing),
      ),
    );
  }

  Future<void> _duplicate(Exercise exercise) async {
    final messenger = ScaffoldMessenger.of(context);
    final library = ExerciseLibraryScope.of(context, listen: false);
    try {
      final copy = await library.duplicate(exercise);
      messenger.showSnackBar(SnackBar(duration: kSnackBarDuration, persist: false, content: Text('Created ${copy.name}')));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't duplicate the exercise.")),
      );
    }
  }

  /// Only the user's own exercises can be deleted: the built-in catalogue is
  /// fixed, so those have no Delete option at all.
  Future<void> _confirmRemove(Exercise exercise) async {
    final messenger = ScaffoldMessenger.of(context);
    final library = ExerciseLibraryScope.of(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${exercise.name}?'),
        content: const Text(
          'This exercise will be deleted. Any workout that already uses it '
          'will show it as unknown.',
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
      await library.remove(exercise.id);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't delete the exercise.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = ExerciseLibraryScope.of(context);
    final q = _query.trim().toLowerCase();
    final shown = library.all
        .where((e) => q.isEmpty || e.name.toLowerCase().contains(q))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Manage exercises')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-exercise-fab',
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add exercise'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search exercises',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '${shown.length} exercises',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final exercise in shown)
            Card(
              key: ValueKey('manage-${exercise.id}'),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: ListTile(
                title: Text(
                  exercise.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${exercise.exerciseType.label} · '
                  '${exercise.movementPattern.label}'
                  '${library.isCustom(exercise.id) ? ' · yours' : ''}',
                ),
                onTap: () => _openEditor(existing: exercise),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Exercise options',
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        _openEditor(existing: exercise);
                      case 'duplicate':
                        _duplicate(exercise);
                      case 'remove':
                        _confirmRemove(exercise);
                    }
                  },
                  itemBuilder: (_) => [
                    // Editing a built-in makes a copy; only your own
                    // exercises can be deleted.
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(
                        library.isCustom(exercise.id)
                            ? 'Edit'
                            : 'Edit as a copy',
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'duplicate',
                      child: Text('Duplicate'),
                    ),
                    if (library.isCustom(exercise.id))
                      const PopupMenuItem(
                        value: 'remove',
                        child: Text('Delete'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
