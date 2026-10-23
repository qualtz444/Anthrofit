import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/exercise_library.dart';
import '../../models/models.dart';
import '../widgets/empty_state.dart';
import 'exercise_card.dart';
import 'exercise_detail_screen.dart';
import 'manage_exercises_screen.dart';

/// Browse, search, and filter the exercise library.
/// Search + exercise type + movement pattern all combine.
///
/// [pickMode] = true turns it into an exercise picker for Planning:
/// tapping a card selects it, and the bottom button returns the chosen
/// exercises (in tap order) as a `List<Exercise>`.
class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({super.key, this.pickMode = false});

  final bool pickMode;

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  ExerciseType? _type; // null = All
  MovementPattern? _pattern; // null = All
  final List<String> _selectedIds = []; // pick mode only, in tap order

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearAll() {
    _searchController.clear();
    setState(() {
      _query = '';
      _type = null;
      _pattern = null;
    });
  }

  void _onCardTap(Exercise exercise) {
    if (widget.pickMode) {
      setState(() {
        if (_selectedIds.contains(exercise.id)) {
          _selectedIds.remove(exercise.id);
        } else {
          _selectedIds.add(exercise.id);
        }
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExerciseDetailScreen(exercise: exercise),
      ),
    );
  }

  void _finishPicking() {
    final picked = <Exercise>[];
    for (final id in _selectedIds) {
      final exercise = ExerciseLibrary.byId(id);
      if (exercise != null) picked.add(exercise);
    }
    Navigator.of(context).pop<List<Exercise>>(picked);
  }

  @override
  Widget build(BuildContext context) {
    final results = ExerciseLibrary.filter(
      query: _query,
      exerciseType: _type,
      movementPattern: _pattern,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pickMode ? 'Add exercises' : 'Exercise Library'),
        actions: [
          // Not offered while picking exercises for a workout: that is a
          // different job and the extra button would only get in the way.
          if (!widget.pickMode)
            IconButton(
              tooltip: 'Manage exercises',
              icon: const Icon(Icons.edit_note),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ManageExercisesScreen(),
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search by name or muscle',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          _FilterRow<ExerciseType>(
            label: 'Type',
            options: ExerciseType.values,
            selected: _type,
            labelOf: (t) => t.label,
            onSelected: (t) => setState(() => _type = t),
          ),
          _FilterRow<MovementPattern>(
            label: 'Movement pattern',
            options: MovementPattern.values,
            selected: _pattern,
            labelOf: (p) => p.label,
            onSelected: (p) => setState(() => _pattern = p),
          ),
          Expanded(
            child: results.isEmpty
                ? EmptyState(
                    title: 'No exercises match your filters.',
                    actionLabel: 'Clear search and filters',
                    onAction: _clearAll,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final exercise = results[index];
                      return ExerciseCard(
                        exercise: exercise,
                        selected: widget.pickMode
                            ? _selectedIds.contains(exercise.id)
                            : null,
                        onTap: () => _onCardTap(exercise),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: widget.pickMode
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _selectedIds.isEmpty ? null : _finishPicking,
                  child: Text(
                    _selectedIds.isEmpty
                        ? 'Select exercises'
                        : 'Add ${pluralize(_selectedIds.length, 'exercise')}',
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

/// One horizontally scrolling row of single-select chips with an "All" chip.
/// `selected == null` means All.
class _FilterRow<T> extends StatelessWidget {
  const _FilterRow({
    required this.label,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final String label;
  final List<T> options;
  final T? selected;
  final String Function(T) labelOf;
  final ValueChanged<T?> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Center(
                child: ChoiceChip(
                  label: const Text('All'),
                  selected: selected == null,
                  onSelected: (_) => onSelected(null),
                ),
              ),
              for (final option in options)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Center(
                    child: ChoiceChip(
                      label: Text(labelOf(option)),
                      selected: selected == option,
                      onSelected: (_) => onSelected(option),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
