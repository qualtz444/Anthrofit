import 'package:flutter/material.dart';

import '../../data/setup_options.dart';
import '../../models/models.dart';
import '../widgets/muscle_image.dart';

/// Picks individual muscles within one training focus.
///
/// Opened by long-pressing a focus (or by tapping "Choose muscles"), so the
/// focus chips stay a one-tap choice and customising is deliberate.
///
/// It only ever offers the muscles that [focus] covers, from
/// musclesForFocus(). There is no second muscle model: the result is a plain
/// List&lt;MuscleGroup&gt; that goes straight into ProgramSetup.muscles.
///
/// Returns the chosen muscles, or null if the sheet was dismissed.
Future<List<MuscleGroup>?> showMusclePicker(
  BuildContext context, {
  required TrainingFocus focus,
  required List<MuscleGroup> selected,
}) {
  return showModalBottomSheet<List<MuscleGroup>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _MusclePickerSheet(focus: focus, selected: selected),
  );
}

class _MusclePickerSheet extends StatefulWidget {
  const _MusclePickerSheet({required this.focus, required this.selected});

  final TrainingFocus focus;
  final List<MuscleGroup> selected;

  @override
  State<_MusclePickerSheet> createState() => _MusclePickerSheetState();
}

class _MusclePickerSheetState extends State<_MusclePickerSheet> {
  late Set<MuscleGroup> _chosen;

  /// The muscles this focus covers, in their own order. The result is always
  /// returned in this order, so it never depends on tap order.
  late final List<MuscleGroup> _available = musclesForFocus(widget.focus);

  @override
  void initState() {
    super.initState();
    _chosen = widget.selected.where(_available.contains).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allOn = _chosen.length == _available.length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.focus == TrainingFocus.chooseMuscles
                  ? 'Choose muscles'
                  : '${widget.focus.label} muscles',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pick the ones this program should train.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('muscle-picker-toggle-all'),
                onPressed: () => setState(() {
                  _chosen = allOn ? {} : _available.toSet();
                }),
                child: Text(allOn ? 'Clear all' : 'Select all'),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final muscle in _available)
                      FilterChip(
                        // Pictured, so the user sees which muscle it is.
                        label: MuscleTileLabel(muscle, size: 56),
                        showCheckmark: false,
                        padding: const EdgeInsets.all(4),
                        selected: _chosen.contains(muscle),
                        onSelected: (isOn) => setState(() {
                          if (isOn) {
                            _chosen.add(muscle);
                          } else {
                            _chosen.remove(muscle);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('muscle-picker-done'),
                onPressed: () => Navigator.of(
                  context,
                ).pop(_available.where(_chosen.contains).toList()),
                child: Text('Done (${_chosen.length} selected)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
