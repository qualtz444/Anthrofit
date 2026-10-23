import 'package:flutter/material.dart';

import '../../content/content_models.dart';
import '../../models/models.dart';
import '../admin_data.dart';
import '../admin_widgets.dart';

/// Built-in equipment (fixed) and equipment the admin added.
class EquipmentPage extends StatelessWidget {
  const EquipmentPage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = AdminScope.of(context);
    String places(Iterable<EquipmentCategory> c) =>
        c.map((x) => x.label).join(', ');

    return AdminPage(
      title: 'Equipment',
      intro:
          'Added equipment shows in program setup for the places you tick. '
          'Built-in equipment cannot be changed here.',
      action: FilledButton.icon(
        key: const ValueKey('admin-add-equipment'),
        onPressed: () => _edit(context, data, null),
        icon: const Icon(Icons.add),
        label: const Text('Add equipment'),
      ),
      children: [
        AdminSection(
          title: 'Added equipment',
          child: data.equipment.isEmpty
              ? const Text('None yet.')
              : Column(
                  children: [
                    for (final e in data.equipment)
                      ListTile(
                        key: ValueKey('admin-equipment-${e.id}'),
                        contentPadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            Flexible(child: Text(e.label)),
                            if (e.hidden) const AdminBadge('Hidden'),
                          ],
                        ),
                        subtitle: Text('${e.id} · ${places(e.categories)}'),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => _edit(context, data, e),
                      ),
                  ],
                ),
        ),
        AdminSection(
          title: 'Built-in equipment',
          child: Column(
            children: [
              for (final item in EquipmentItem.values)
                if (item != EquipmentItem.none)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(item.label),
                    subtitle: Text(places(item.categories)),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    AdminData data,
    EquipmentDef? existing,
  ) async {
    final usedBy = existing == null
        ? const <String>[]
        : [
            for (final e in data.allExercises)
              if (e.extraEquipment.contains(existing.id)) e.name,
          ];
    final result = await showDialog<_EquipmentResult>(
      context: context,
      builder: (_) => _EquipmentDialog(
        existing: existing,
        takenIds: {
          for (final e in data.equipment) e.id,
          for (final i in EquipmentItem.values) i.name,
        },
        usedBy: usedBy,
      ),
    );
    if (result == null || !context.mounted) return;
    if (result.delete) {
      await runSave(
        context,
        () => data.service.deleteEquipment(existing!.id),
        done: 'Deleted.',
      );
    } else {
      await runSave(context, () => data.service.saveEquipment(result.item!));
    }
  }
}

class _EquipmentResult {
  const _EquipmentResult.save(EquipmentDef this.item) : delete = false;
  const _EquipmentResult.delete() : item = null, delete = true;

  final EquipmentDef? item;
  final bool delete;
}

class _EquipmentDialog extends StatefulWidget {
  const _EquipmentDialog({
    required this.existing,
    required this.takenIds,
    required this.usedBy,
  });

  final EquipmentDef? existing;
  final Set<String> takenIds;
  final List<String> usedBy;

  @override
  State<_EquipmentDialog> createState() => _EquipmentDialogState();
}

class _EquipmentDialogState extends State<_EquipmentDialog> {
  final _form = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.existing?.label);
  late final _id = TextEditingController(text: widget.existing?.id);
  late Set<EquipmentCategory> _categories = {
    ...?widget.existing?.categories,
  };
  late bool _hidden = widget.existing?.hidden ?? false;
  bool _idEdited = false;
  bool _showErrors = false;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _label.dispose();
    _id.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate() || _categories.isEmpty) {
      setState(() => _showErrors = true);
      return;
    }
    Navigator.of(context).pop(
      _EquipmentResult.save(
        EquipmentDef(
          id: _id.text.trim(),
          label: _label.text.trim(),
          categories: _categories,
          hidden: _hidden,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_isNew ? 'Add equipment' : 'Edit ${widget.existing!.label}'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(labelText: 'Name'),
                onChanged: (v) {
                  if (_isNew && !_idEdited) _id.text = slugify(v);
                },
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter a name' : null,
              ),
              TextFormField(
                controller: _id,
                enabled: _isNew,
                decoration: const InputDecoration(
                  labelText: 'Id (never changes)',
                ),
                onChanged: (_) => _idEdited = true,
                validator: (v) {
                  if (!_isNew) return null;
                  final id = (v ?? '').trim();
                  if (!kIdPattern.hasMatch(id)) {
                    return '3–60 lowercase letters, numbers or _';
                  }
                  if (widget.takenIds.contains(id)) return 'Already used';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Text('Where it is found', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              MultiChips<EquipmentCategory>(
                options: EquipmentCategory.values,
                selected: _categories,
                label: (c) => c.label,
                onChanged: (v) => setState(() => _categories = v),
              ),
              if (_showErrors && _categories.isEmpty)
                Text(
                  'Choose at least one place',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hide from program setup'),
                value: _hidden,
                onChanged: (v) => setState(() => _hidden = v),
              ),
              if (widget.usedBy.isNotEmpty)
                Text(
                  'Required by: ${widget.usedBy.join(', ')}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (!_isNew)
          TextButton(
            // Deleting equipment an exercise still needs would make that
            // exercise impossible to recommend; hide it instead.
            onPressed: widget.usedBy.isEmpty
                ? () => Navigator.of(
                    context,
                  ).pop(const _EquipmentResult.delete())
                : null,
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
