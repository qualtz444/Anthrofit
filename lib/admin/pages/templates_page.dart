import 'package:flutter/material.dart';

import '../../data/ready_made_programs.dart';
import '../../data/workout_templates.dart';
import '../../models/models.dart';
import '../admin_data.dart';
import '../admin_widgets.dart';

/// The workouts new programs start with, and the ready-made programs in the
/// app's Library.
class TemplatesPage extends StatelessWidget {
  const TemplatesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = AdminScope.of(context);
    final ready = data.config.readyMade ?? kReadyMadePrograms;
    final readyChanged = data.config.readyMade != null;

    return AdminPage(
      title: 'Templates',
      intro:
          'A template is the starting exercise list for a workout such as Push, '
          'Pull or Legs. A ready-made program adds a goal and training days. '
          'Existing user programs are not changed.',
      children: [
        const SourceNote(
          'Template exercises and days are common gym conventions. Note why you '
          'change them.',
        ),
        AdminSection(
          title: 'Workout templates',
          child: Column(
            children: [
              for (final t in WorkoutTemplate.values)
                if (t != WorkoutTemplate.custom) _templateTile(context, data, t),
            ],
          ),
        ),
        AdminSection(
          title: 'Ready-made programs',
          subtitle: readyChanged
              ? 'Your list replaces the built-in one.'
              : 'The built-in list. Saving any change makes it yours.',
          actions: [
            if (readyChanged)
              TextButton(
                onPressed: () => _resetReady(context, data),
                child: const Text('Back to built-in'),
              ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const ValueKey('admin-add-ready'),
              onPressed: () => _editReady(context, data, ready, null),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ],
          child: Column(
            children: [
              for (final r in ready)
                ListTile(
                  key: ValueKey('admin-ready-${r.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(r.name),
                  subtitle: Text(
                    '${r.template.label} · ${r.goal.label} · '
                    '${r.experience.label} · '
                    '${r.days.map((d) => d.shortLabel).join(' ')}\n'
                    '${r.summary}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editReady(context, data, ready, r),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _templateTile(
    BuildContext context,
    AdminData data,
    WorkoutTemplate t,
  ) {
    final ids = data.config.templateExercises[t.name] ?? t.exerciseIds;
    final changed = data.config.templateExercises.containsKey(t.name);
    return ListTile(
      key: ValueKey('admin-template-${t.name}'),
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Text(t.label),
          if (changed) const AdminBadge('Changed', strong: true),
        ],
      ),
      subtitle: Text(
        ids.isEmpty ? 'No exercises' : ids.map(data.exerciseName).join(' · '),
      ),
      trailing: const Icon(Icons.edit_outlined),
      onTap: () async {
        final result = await showDialog<_TemplateResult>(
          context: context,
          builder: (_) => _TemplateDialog(
            title: t.label,
            ids: ids,
            builtIn: t.exerciseIds,
            all: data.allExercises,
            nameOf: data.exerciseName,
          ),
        );
        if (result == null || !context.mounted) return;
        await runSave(
          context,
          () => data.service.updateConfig((c) {
            final next = {...c.templateExercises};
            if (result.reset) {
              next.remove(t.name);
            } else {
              next[t.name] = result.ids;
            }
            return c.copyWith(templateExercises: next);
          }),
        );
      },
    );
  }

  Future<void> _resetReady(BuildContext context, AdminData data) async {
    final yes = await confirmAdmin(
      context,
      title: 'Use the built-in ready-made programs?',
      message: 'Your list is removed and the app shows the built-in one.',
      confirm: 'Use built-in',
    );
    if (!yes || !context.mounted) return;
    await runSave(
      context,
      () => data.service.updateConfig((c) => c.copyWith(clearReadyMade: true)),
    );
  }

  Future<void> _editReady(
    BuildContext context,
    AdminData data,
    List<ReadyMadeProgram> list,
    ReadyMadeProgram? existing,
  ) async {
    final result = await showDialog<_ReadyResult>(
      context: context,
      builder: (_) => _ReadyDialog(existing: existing),
    );
    if (result == null || !context.mounted) return;
    final next = [
      for (final r in list)
        if (r.id != existing?.id) r else if (!result.delete) result.program!,
      if (existing == null && !result.delete) result.program!,
    ];
    await runSave(
      context,
      () => data.service.updateConfig((c) => c.copyWith(readyMade: next)),
    );
  }
}

class _TemplateResult {
  const _TemplateResult(this.ids, {this.reset = false});
  final List<String> ids;
  final bool reset;
}

class _TemplateDialog extends StatefulWidget {
  const _TemplateDialog({
    required this.title,
    required this.ids,
    required this.builtIn,
    required this.all,
    required this.nameOf,
  });

  final String title;
  final List<String> ids;
  final List<String> builtIn;
  final List<Exercise> all;
  final String Function(String) nameOf;

  @override
  State<_TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends State<_TemplateDialog> {
  late final List<String> _ids = [...widget.ids];

  void _move(int from, int to) {
    if (to < 0 || to >= _ids.length) return;
    setState(() {
      final id = _ids.removeAt(from);
      _ids.insert(to, id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.title} template'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'In the order the workout starts with. Users can change their '
              'own workouts afterwards.',
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < _ids.length; i++)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Text('${i + 1}'),
                      title: Text(widget.nameOf(_ids[i])),
                      subtitle: Text(_ids[i]),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            tooltip: 'Up',
                            icon: const Icon(Icons.arrow_upward, size: 18),
                            onPressed: i == 0 ? null : () => _move(i, i - 1),
                          ),
                          IconButton(
                            tooltip: 'Down',
                            icon: const Icon(Icons.arrow_downward, size: 18),
                            onPressed: i == _ids.length - 1
                                ? null
                                : () => _move(i, i + 1),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => _ids.removeAt(i)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                final picked = await pickExercises(
                  context,
                  all: widget.all,
                  selected: const [],
                );
                if (picked == null) return;
                setState(() {
                  for (final id in picked) {
                    if (!_ids.contains(id)) _ids.add(id);
                  }
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('Add exercises'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(_TemplateResult(widget.builtIn, reset: true)),
          child: const Text('Back to built-in'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_TemplateResult(_ids)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ReadyResult {
  const _ReadyResult.save(ReadyMadeProgram this.program) : delete = false;
  const _ReadyResult.delete() : program = null, delete = true;
  final ReadyMadeProgram? program;
  final bool delete;
}

class _ReadyDialog extends StatefulWidget {
  const _ReadyDialog({required this.existing});

  final ReadyMadeProgram? existing;

  @override
  State<_ReadyDialog> createState() => _ReadyDialogState();
}

class _ReadyDialogState extends State<_ReadyDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _summary = TextEditingController(text: widget.existing?.summary);
  late ProgramTemplate _template =
      widget.existing?.template ?? ProgramTemplate.fullBody;
  late TrainingGoal _goal = widget.existing?.goal ?? TrainingGoal.buildMuscle;
  late ExperienceLevel _experience =
      widget.existing?.experience ?? ExperienceLevel.beginner;
  late Set<Weekday> _days = {...?widget.existing?.days};
  bool _showErrors = false;

  @override
  void dispose() {
    _name.dispose();
    _summary.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate() || _days.isEmpty) {
      setState(() => _showErrors = true);
      return;
    }
    Navigator.of(context).pop(
      _ReadyResult.save(
        ReadyMadeProgram(
          id:
              widget.existing?.id ??
              'ready_${DateTime.now().millisecondsSinceEpoch}',
          name: _name.text.trim(),
          summary: _summary.text.trim(),
          template: _template,
          goal: _goal,
          experience: _experience,
          days: [
            for (final d in Weekday.values)
              if (_days.contains(d)) d,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Add ready-made program' : 'Edit program',
      ),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Enter a name' : null,
                ),
                TextFormField(
                  controller: _summary,
                  decoration: const InputDecoration(
                    labelText: 'One line on who it suits',
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Enter a summary' : null,
                ),
                const SizedBox(height: 16),
                EnumDropdown<ProgramTemplate>(
                  label: 'Structure',
                  value: _template,
                  values: [
                    for (final t in ProgramTemplate.values)
                      if (t != ProgramTemplate.custom) t,
                  ],
                  text: (t) => t.label,
                  onChanged: (t) => setState(() => _template = t),
                ),
                const SizedBox(height: 12),
                EnumDropdown<TrainingGoal>(
                  label: 'Goal',
                  value: _goal,
                  values: TrainingGoal.values,
                  text: (g) => g.label,
                  onChanged: (g) => setState(() => _goal = g),
                ),
                const SizedBox(height: 12),
                EnumDropdown<ExperienceLevel>(
                  label: 'Aimed at',
                  value: _experience,
                  values: ExperienceLevel.values,
                  text: (e) => e.label,
                  onChanged: (e) => setState(() => _experience = e),
                ),
                const SizedBox(height: 16),
                Text('Training days', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                MultiChips<Weekday>(
                  options: Weekday.values,
                  selected: _days,
                  label: (d) => d.shortLabel,
                  onChanged: (v) => setState(() => _days = v),
                ),
                if (_showErrors && _days.isEmpty)
                  Text(
                    'Choose at least one day',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const _ReadyResult.delete()),
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
