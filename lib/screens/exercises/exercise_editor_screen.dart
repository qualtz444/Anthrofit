import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../state/exercise_library_scope.dart';
import '../widgets/muscle_image.dart';
import '../../core/snack_bar_timing.dart';

/// Adds or edits one exercise, using the existing Exercise fields and nothing
/// else. Every list field is chips, so nothing has to be typed by hand except
/// the name and the instructions.
///
/// Editing one of the user's own exercises changes it in place, keeping its
/// id, so programs that use it follow the change. Editing a BUILT-IN one
/// saves a copy instead and leaves the original alone: the built-in catalogue
/// is fixed.
class ExerciseEditorScreen extends StatefulWidget {
  const ExerciseEditorScreen({super.key, this.existing});

  /// Null to create a new exercise.
  final Exercise? existing;

  @override
  State<ExerciseEditorScreen> createState() => _ExerciseEditorScreenState();
}

class _ExerciseEditorScreenState extends State<ExerciseEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _instructions;

  late ExerciseType _type;
  late MovementPattern _pattern;
  late Set<MuscleGroup> _primary;
  late Set<MuscleGroup> _secondary;
  late Set<EquipmentItem> _equipment;
  late ExperienceLevel _experience;
  late Complexity _complexity;

  bool _showErrors = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    // One instruction per line: the simplest thing that round-trips.
    _instructions = TextEditingController(
      text: (e?.instructions ?? const []).join('\n'),
    );
    _type = e?.exerciseType ?? ExerciseType.machine;
    _pattern = e?.movementPattern ?? MovementPattern.isolation;
    _primary = {...?e?.primaryMuscles};
    _secondary = {...?e?.secondaryMuscles};
    _equipment = {...?e?.equipment};
    _experience = e?.experienceLevel ?? ExperienceLevel.beginner;
    _complexity = e?.complexity ?? Complexity.low;
  }

  @override
  void dispose() {
    _name.dispose();
    _instructions.dispose();
    super.dispose();
  }

  /// A muscle is primary or secondary, never both.
  void _togglePrimary(MuscleGroup muscle, bool isOn) {
    setState(() {
      if (isOn) {
        _primary.add(muscle);
        _secondary.remove(muscle);
      } else {
        _primary.remove(muscle);
      }
    });
  }

  void _toggleSecondary(MuscleGroup muscle, bool isOn) {
    setState(() {
      if (isOn) {
        _secondary.add(muscle);
        _primary.remove(muscle);
      } else {
        _secondary.remove(muscle);
      }
    });
  }

  List<T> _ordered<T>(List<T> all, Set<T> chosen) =>
      all.where(chosen.contains).toList();

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final library = ExerciseLibraryScope.of(context, listen: false);

    final formOk = _formKey.currentState!.validate();
    if (!formOk || _primary.isEmpty || _equipment.isEmpty) {
      setState(() => _showErrors = true);
      return;
    }

    final draft = Exercise(
      id: widget.existing?.id ?? '',
      name: _name.text.trim(),
      exerciseType: _type,
      movementPattern: _pattern,
      primaryMuscles: _ordered(MuscleGroup.values, _primary),
      secondaryMuscles: _ordered(MuscleGroup.values, _secondary),
      equipment: _ordered(EquipmentItem.values, _equipment),
      // Admin-added equipment is not offered here; an edit keeps it.
      extraEquipment: widget.existing?.extraEquipment ?? const [],
      experienceLevel: _experience,
      complexity: _complexity,
      instructions: _instructions.text
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(),
    );

    final isBuiltIn =
        widget.existing != null && library.isBuiltIn(widget.existing!.id);

    setState(() => _saving = true);
    try {
      if (widget.existing == null) {
        await library.add(draft);
      } else {
        final saved = await library.update(draft);
        if (isBuiltIn) {
          messenger.showSnackBar(
            SnackBar(duration: kSnackBarDuration, persist: false, content: Text('Saved as ${saved.name}')),
          );
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't save the exercise. Try again.")),
      );
      return;
    }
    if (!mounted) return;
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = ExerciseLibraryScope.of(context);
    final isNew = widget.existing == null;
    final isBuiltIn = !isNew && library.isBuiltIn(widget.existing!.id);
    final errorStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.error,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isNew
              ? 'New exercise'
              : isBuiltIn
              ? 'Edit as a copy'
              : 'Edit exercise',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isBuiltIn) ...[
                  Card(
                    margin: EdgeInsets.zero,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Built-in exercises cannot be changed. Saving will '
                        'create your own copy and leave the original as it is.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (text) => (text == null || text.trim().isEmpty)
                      ? 'Enter a name'
                      : null,
                ),
                const SizedBox(height: 24),
                _Field(
                  label: 'Exercise type',
                  child: _SingleChoice<ExerciseType>(
                    options: ExerciseType.values,
                    selected: _type,
                    labelOf: (v) => v.label,
                    onChanged: (v) => setState(() => _type = v),
                  ),
                ),
                _Field(
                  label: 'Movement pattern',
                  child: _SingleChoice<MovementPattern>(
                    options: MovementPattern.values,
                    selected: _pattern,
                    labelOf: (v) => v.label,
                    onChanged: (v) => setState(() => _pattern = v),
                  ),
                ),
                _Field(
                  label: 'Primary muscles',
                  hint: 'The muscles this exercise trains most.',
                  error: _showErrors && _primary.isEmpty
                      ? 'Choose at least one primary muscle'
                      : null,
                  child: _MultiChoice<MuscleGroup>(
                    options: MuscleGroup.values,
                    selected: _primary,
                    labelOf: (v) => v.label,
                    avatarOf: (v) => MuscleImage(v, size: 24),
                    onChanged: _togglePrimary,
                  ),
                ),
                _Field(
                  label: 'Secondary muscles',
                  hint: 'Choosing one here removes it from primary.',
                  child: _MultiChoice<MuscleGroup>(
                    options: MuscleGroup.values,
                    selected: _secondary,
                    labelOf: (v) => v.label,
                    avatarOf: (v) => MuscleImage(v, size: 24),
                    onChanged: _toggleSecondary,
                  ),
                ),
                _Field(
                  label: 'Equipment',
                  hint: 'Choose "None" for an exercise that needs nothing.',
                  error: _showErrors && _equipment.isEmpty
                      ? 'Choose at least one piece of equipment'
                      : null,
                  child: _MultiChoice<EquipmentItem>(
                    options: EquipmentItem.values,
                    selected: _equipment,
                    labelOf: (v) => v.label,
                    onChanged: (item, isOn) => setState(() {
                      if (isOn) {
                        _equipment.add(item);
                      } else {
                        _equipment.remove(item);
                      }
                    }),
                  ),
                ),
                _Field(
                  label: 'Experience',
                  hint: 'Who this exercise is suitable for.',
                  child: _SingleChoice<ExperienceLevel>(
                    options: ExperienceLevel.values,
                    selected: _experience,
                    labelOf: (v) => v.label,
                    onChanged: (v) => setState(() => _experience = v),
                  ),
                ),
                _Field(
                  label: 'Complexity',
                  hint: 'How technically demanding it is.',
                  child: _SingleChoice<Complexity>(
                    options: Complexity.values,
                    selected: _complexity,
                    labelOf: (v) => v.label,
                    onChanged: (v) => setState(() => _complexity = v),
                  ),
                ),
                TextFormField(
                  controller: _instructions,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Instructions',
                    helperText: 'One step per line.',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_showErrors && (_primary.isEmpty || _equipment.isEmpty))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Fix the highlighted fields to save.',
                      style: errorStyle,
                    ),
                  ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('save-exercise'),
                    onPressed: _saving ? null : _save,
                    child: Text(
                      isNew
                          ? 'Add exercise'
                          : isBuiltIn
                          ? 'Save as my copy'
                          : 'Save changes',
                    ),
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

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.child,
    this.hint,
    this.error,
  });

  final String label;
  final Widget child;
  final String? hint;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.titleSmall),
          if (hint != null)
            Text(
              hint!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 8),
          child,
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SingleChoice<T> extends StatelessWidget {
  const _SingleChoice({
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final List<T> options;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(labelOf(option)),
            selected: selected == option,
            onSelected: (_) => onChanged(option),
          ),
      ],
    );
  }
}

class _MultiChoice<T> extends StatelessWidget {
  const _MultiChoice({
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.avatarOf,
  });

  final List<T> options;
  final Set<T> selected;
  final String Function(T) labelOf;
  final void Function(T value, bool isOn) onChanged;

  /// An optional picture before each label, such as a muscle's.
  final Widget Function(T)? avatarOf;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          FilterChip(
            avatar: avatarOf?.call(option),
            // The checkmark would cover the picture.
            showCheckmark: avatarOf == null,
            label: Text(labelOf(option)),
            selected: selected.contains(option),
            onSelected: (isOn) => onChanged(option, isOn),
          ),
      ],
    );
  }
}
