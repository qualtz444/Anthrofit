import 'package:flutter/material.dart';

import '../models/models.dart';

/// A page: a title, an explanation, then its sections, scrolled.
class AdminPage extends StatelessWidget {
  const AdminPage({
    super.key,
    required this.title,
    required this.intro,
    required this.children,
    this.action,
  });

  final String title;
  final String intro;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: theme.textTheme.headlineSmall)),
            ?action,
          ],
        ),
        const SizedBox(height: 4),
        Text(intro, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }
}

/// A titled card.
class AdminSection extends StatelessWidget {
  const AdminSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                ...actions,
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// A highlighted note, for where values come from and what they are not.
class SourceNote extends StatelessWidget {
  const SourceNote(this.text, {super.key, this.warning = false});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warning ? scheme.errorContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            warning ? Icons.warning_amber : Icons.info_outline,
            size: 20,
            color: warning
                ? scheme.onErrorContainer
                : scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: warning
                    ? scheme.onErrorContainer
                    : scheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small coloured label: "Built-in", "Edited", "Hidden".
class AdminBadge extends StatelessWidget {
  const AdminBadge(this.label, {super.key, this.strong = false});

  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: strong ? scheme.tertiaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

/// Chips to pick any number of [options].
class MultiChips<T> extends StatelessWidget {
  const MultiChips({
    super.key,
    required this.options,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final List<T> options;
  final Set<T> selected;
  final String Function(T) label;
  final ValueChanged<Set<T>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final o in options)
          FilterChip(
            label: Text(label(o)),
            selected: selected.contains(o),
            onSelected: (on) {
              final next = {...selected};
              if (on) {
                next.add(o);
              } else {
                next.remove(o);
              }
              onChanged(next);
            },
          ),
      ],
    );
  }
}

/// A labelled dropdown for an enum.
class EnumDropdown<T> extends StatelessWidget {
  const EnumDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.text,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T) text;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          isExpanded: true,
          items: [
            for (final v in values)
              DropdownMenuItem(value: v, child: Text(text(v))),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

void showAdminMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
  );
}

Future<bool> confirmAdmin(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Confirm',
}) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(c).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(c).pop(true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return yes == true;
}

/// Runs a save and reports it, so every page says the same thing.
Future<bool> runSave(
  BuildContext context,
  Future<void> Function() save, {
  String done = 'Saved. Phones pick it up the next time the app starts.',
}) async {
  try {
    await save();
    if (context.mounted) showAdminMessage(context, done);
    return true;
  } catch (e) {
    if (context.mounted) showAdminMessage(context, 'Not saved: $e');
    return false;
  }
}

/// lower_snake_case from a name, for new ids.
String slugify(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

final RegExp kIdPattern = RegExp(r'^[a-z0-9_]{3,60}$');

/// Picks exercises from [all], with a search box. Returns the new
/// selection, or null when cancelled.
Future<List<String>?> pickExercises(
  BuildContext context, {
  required List<Exercise> all,
  required List<String> selected,
  bool single = false,
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) =>
        _ExercisePicker(all: all, selected: selected, single: single),
  );
}

class _ExercisePicker extends StatefulWidget {
  const _ExercisePicker({
    required this.all,
    required this.selected,
    required this.single,
  });

  final List<Exercise> all;
  final List<String> selected;
  final bool single;

  @override
  State<_ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends State<_ExercisePicker> {
  late final List<String> _picked = [...widget.selected];
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final e in widget.all)
        if (q.isEmpty ||
            e.name.toLowerCase().contains(q) ||
            e.id.contains(q))
          e,
    ]..sort((a, b) => a.name.compareTo(b.name));
    return AlertDialog(
      title: Text(widget.single ? 'Choose an exercise' : 'Choose exercises'),
      content: SizedBox(
        width: 480,
        height: 480,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by name or id',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final e in shown)
                    widget.single
                        ? ListTile(
                            dense: true,
                            title: Text(e.name),
                            subtitle: Text(e.id),
                            onTap: () => Navigator.of(context).pop([e.id]),
                          )
                        : CheckboxListTile(
                            dense: true,
                            value: _picked.contains(e.id),
                            title: Text(e.name),
                            subtitle: Text(e.id),
                            onChanged: (on) => setState(() {
                              if (on == true) {
                                _picked.add(e.id);
                              } else {
                                _picked.remove(e.id);
                              }
                            }),
                          ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (!widget.single)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_picked),
            child: Text('Use ${_picked.length}'),
          ),
      ],
    );
  }
}
