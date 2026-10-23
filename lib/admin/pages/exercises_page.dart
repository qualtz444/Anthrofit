import 'package:flutter/material.dart';

import '../../content/content_models.dart';
import '../../models/models.dart';
import '../admin_data.dart';
import '../admin_widgets.dart';

/// Every exercise the phone app offers: the built-in catalogue with the
/// admin's edits, and exercises the admin added.
class ExercisesPage extends StatefulWidget {
  const ExercisesPage({super.key});

  @override
  State<ExercisesPage> createState() => _ExercisesPageState();
}

class _ExercisesPageState extends State<ExercisesPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final data = AdminScope.of(context);
    final q = _query.trim().toLowerCase();
    final all = [
      for (final e in data.allExercises)
        if (q.isEmpty || e.name.toLowerCase().contains(q) || e.id.contains(q))
          e,
    ]..sort((a, b) => a.name.compareTo(b.name));

    return AdminPage(
      title: 'Exercises',
      intro:
          'Edit, add or hide exercises. An id never changes, and a hidden '
          'exercise still works in programs that use it.',
      action: FilledButton.icon(
        key: const ValueKey('admin-add-exercise'),
        onPressed: () => _open(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Add exercise'),
      ),
      children: [
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search by name or id',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 12),
        Text('${all.length} exercises'),
        const SizedBox(height: 4),
        Card(
          child: Column(
            children: [
              for (final e in all)
                ListTile(
                  key: ValueKey('admin-exercise-${e.id}'),
                  title: Row(
                    children: [
                      Flexible(child: Text(e.name)),
                      ..._badges(data, e.id),
                    ],
                  ),
                  subtitle: Text(
                    '${e.id} · ${e.movementPattern.label} · '
                    '${e.primaryMuscles.map((m) => m.label).join(', ')}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(context, e),
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _badges(AdminData data, String id) {
    final o = data.overrideOf(id);
    return [
      if (data.isBuiltIn(id))
        AdminBadge(o == null ? 'Built-in' : 'Built-in, edited', strong: o != null)
      else
        const AdminBadge('Added', strong: true),
      if (o?.hidden ?? false) const AdminBadge('Hidden'),
    ];
  }

  void _open(BuildContext context, Exercise? exercise) {
    final data = AdminScope.of(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminScope(
          data: data,
          child: ExerciseEditorPage(existing: exercise),
        ),
      ),
    );
  }
}

/// Edits one exercise, or creates one when [existing] is null.
class ExerciseEditorPage extends StatefulWidget {
  const ExerciseEditorPage({super.key, this.existing});

  final Exercise? existing;

  @override
  State<ExerciseEditorPage> createState() => _ExerciseEditorPageState();
}

class _ExerciseEditorPageState extends State<ExerciseEditorPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _id;
  late final TextEditingController _name;
  late final TextEditingController _instructions;
  late ExerciseType _type;
  late MovementPattern _pattern;
  late Set<MuscleGroup> _primary;
  late Set<MuscleGroup> _secondary;
  late Set<EquipmentItem> _equipment;
  late Set<String> _extra;
  late ExperienceLevel _experience;
  late Complexity _complexity;
  bool _hidden = false;
  bool _idEdited = false;
  bool _saving = false;
  bool _showErrors = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _id = TextEditingController(text: e?.id ?? '');
    _name = TextEditingController(text: e?.name ?? '');
    _instructions = TextEditingController(
      text: (e?.instructions ?? const []).join('\n'),
    );
    _type = e?.exerciseType ?? ExerciseType.freeWeight;
    _pattern = e?.movementPattern ?? MovementPattern.isolation;
    _primary = {...?e?.primaryMuscles};
    _secondary = {...?e?.secondaryMuscles};
    _equipment = {...?e?.equipment};
    _extra = {...?e?.extraEquipment};
    _experience = e?.experienceLevel ?? ExperienceLevel.beginner;
    _complexity = e?.complexity ?? Complexity.low;
  }

  bool _readHidden = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Once only: later Firestore updates must not undo the switch.
    if (_readHidden) return;
    _readHidden = true;
    final e = widget.existing;
    if (e != null) {
      _hidden = AdminScope.of(context).overrideOf(e.id)?.hidden ?? false;
    }
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Exercise _build() => Exercise(
    id: _id.text.trim(),
    name: _name.text.trim(),
    exerciseType: _type,
    movementPattern: _pattern,
    primaryMuscles: [
      for (final m in MuscleGroup.values)
        if (_primary.contains(m)) m,
    ],
    secondaryMuscles: [
      for (final m in MuscleGroup.values)
        if (_secondary.contains(m)) m,
    ],
    equipment: [
      for (final i in EquipmentItem.values)
        if (_equipment.contains(i)) i,
    ],
    extraEquipment: _extra.toList()..sort(),
    experienceLevel: _experience,
    complexity: _complexity,
    instructions: _instructions.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList(),
  );

  Future<void> _save() async {
    final data = AdminScope.of(context);
    final formOk = _form.currentState!.validate();
    if (!formOk || _primary.isEmpty || _equipment.isEmpty) {
      setState(() => _showErrors = true);
      return;
    }
    setState(() => _saving = true);
    final ok = await runSave(
      context,
      () => data.service.saveExercise(
        ExerciseOverride(_build(), hidden: _hidden),
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    final data = AdminScope.of(context);
    final e = widget.existing!;
    final builtIn = data.isBuiltIn(e.id);
    final yes = await confirmAdmin(
      context,
      title: builtIn ? 'Undo your edits?' : 'Delete ${e.name}?',
      message: builtIn
          ? 'The exercise goes back to exactly how it ships with the app.'
          : 'Programs that already use it will show it as unknown. Hiding it '
                'is usually safer: it disappears from the app but old '
                'programs keep working.',
      confirm: builtIn ? 'Undo edits' : 'Delete',
    );
    if (!yes || !mounted) return;
    final ok = await runSave(
      context,
      () => data.service.deleteExercise(e.id),
      done: builtIn ? 'Back to the built-in version.' : 'Deleted.',
    );
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final data = AdminScope.of(context);
    final theme = Theme.of(context);
    final existing = widget.existing;
    final hasOverride = existing != null && data.overrideOf(existing.id) != null;
    final builtIn = existing != null && data.isBuiltIn(existing.id);
    final error = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.error,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Add exercise' : 'Edit ${existing!.name}'),
        actions: [
          if (hasOverride)
            TextButton(
              onPressed: _saving ? null : _remove,
              child: Text(builtIn ? 'Undo edits' : 'Delete'),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FilledButton(
              key: const ValueKey('admin-save-exercise'),
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (builtIn)
              const SourceNote(
                'Built-in exercise. Saving replaces it on every phone, '
                'including in existing programs. Undo edits restores the '
                'original.',
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      if (_isNew && !_idEdited) _id.text = slugify(v);
                    },
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Enter a name'
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _id,
                    enabled: _isNew,
                    decoration: const InputDecoration(
                      labelText: 'Id (never changes)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _idEdited = true,
                    validator: (v) {
                      if (!_isNew) return null;
                      final id = (v ?? '').trim();
                      if (!kIdPattern.hasMatch(id)) {
                        return '3–60 lowercase letters, numbers or _';
                      }
                      if (data.exerciseById(id) != null) {
                        return 'An exercise already uses this id';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: EnumDropdown<ExerciseType>(
                    label: 'Type',
                    value: _type,
                    values: ExerciseType.values,
                    text: (v) => v.label,
                    onChanged: (v) => setState(() => _type = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: EnumDropdown<MovementPattern>(
                    label: 'Movement pattern',
                    value: _pattern,
                    values: MovementPattern.values,
                    text: (v) => v.label,
                    onChanged: (v) => setState(() => _pattern = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: EnumDropdown<ExperienceLevel>(
                    label: 'Experience level',
                    value: _experience,
                    values: ExperienceLevel.values,
                    text: (v) => v.label,
                    onChanged: (v) => setState(() => _experience = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: EnumDropdown<Complexity>(
                    label: 'Complexity',
                    value: _complexity,
                    values: Complexity.values,
                    text: (v) => v.label,
                    onChanged: (v) => setState(() => _complexity = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Experience level and complexity decide who is recommended this '
              'exercise: a beginner is never given one above their level, or '
              'one of high complexity.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Text('Primary muscles', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            MultiChips<MuscleGroup>(
              options: MuscleGroup.values,
              selected: _primary,
              label: (m) => m.label,
              onChanged: (v) => setState(() => _primary = v),
            ),
            if (_showErrors && _primary.isEmpty)
              Text('Choose at least one primary muscle', style: error),
            const SizedBox(height: 16),
            Text('Secondary muscles', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            MultiChips<MuscleGroup>(
              options: MuscleGroup.values,
              selected: _secondary,
              label: (m) => m.label,
              onChanged: (v) => setState(() => _secondary = v),
            ),
            const SizedBox(height: 16),
            Text('Equipment', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            MultiChips<EquipmentItem>(
              options: EquipmentItem.values,
              selected: _equipment,
              label: (i) => i.label,
              onChanged: (v) => setState(() => _equipment = v),
            ),
            if (_showErrors && _equipment.isEmpty)
              Text(
                'Choose at least one. Pick "None" for an exercise that needs '
                'nothing.',
                style: error,
              ),
            if (data.equipment.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Equipment you added',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              MultiChips<String>(
                options: [for (final e in data.equipment) e.id],
                selected: _extra,
                label: data.equipmentLabel,
                onChanged: (v) => setState(() => _extra = v),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'The app only recommends an exercise to someone who has every '
              'piece of equipment ticked here.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _instructions,
              minLines: 4,
              maxLines: 12,
              decoration: const InputDecoration(
                labelText: 'Instructions, one step per line',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              key: const ValueKey('admin-exercise-hidden'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Hide from the app'),
              subtitle: const Text(
                'Not shown when browsing and never recommended. Programs that '
                'already use it keep it.',
              ),
              value: _hidden,
              onChanged: (v) => setState(() => _hidden = v),
            ),
          ],
        ),
      ),
    );
  }
}
