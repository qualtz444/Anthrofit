import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/list_utils.dart';
import '../../core/set_input.dart';
import '../../data/exercise_library.dart';
import '../../models/models.dart';

/// Edits HOW one exercise is prescribed inside a workout: its individual sets
/// and a note. Every set has its own type (Warm-up, Working Set, Failure),
/// rep target, target load and rest. Sets can be added, removed and reordered.
/// The exercise itself is not editable here. Pops with the updated
/// PlannedExercise.
class PlannedExerciseEditScreen extends StatefulWidget {
  const PlannedExerciseEditScreen({
    super.key,
    required this.planned,
    this.title = 'Edit exercise',
    this.doneLabel = 'Done',
  });

  final PlannedExercise planned;

  /// Wording for the screen, so the same editor can set up a quick workout
  /// as well as edit one inside a program.
  final String title;
  final String doneLabel;

  @override
  State<PlannedExerciseEditScreen> createState() =>
      _PlannedExerciseEditScreenState();
}

int _nextDraftId = 0;

/// The text boxes for one set while it is being edited.
class _SetDraft {
  _SetDraft({
    required this.type,
    String repMin = '',
    String repMax = '',
    String load = '',
    String rest = '',
    String minutes = '',
    String seconds = '',
  }) : id = _nextDraftId++,
       repMin = TextEditingController(text: repMin),
       repMax = TextEditingController(text: repMax),
       load = TextEditingController(text: load),
       rest = TextEditingController(text: rest),
       minutes = TextEditingController(text: minutes),
       seconds = TextEditingController(text: seconds);

  factory _SetDraft.fromPlanned(PlannedSet set) {
    final min = set.targetRepMin;
    final max = set.targetRepMax;
    final targetLoad = set.targetLoadKg;
    final duration = set.targetDurationSeconds;
    return _SetDraft(
      type: set.setType,
      minutes: duration == null ? '' : '${duration ~/ 60}',
      seconds: duration == null ? '' : '${duration % 60}',
      repMin: min == null ? '' : '$min',
      // A single number is shown in "Min reps" only.
      repMax: max == null || max == min ? '' : '$max',
      load: targetLoad == null ? '' : formatNumber(targetLoad),
      rest: '${set.restSeconds}',
    );
  }

  /// A new set copies reps and rest from the previous set. Its load is blank.
  /// A Failure set starts with no rep target ("To Failure").
  factory _SetDraft.added(SetType type, _SetDraft? previous) {
    final previousMin = previous?.repMin.text.trim() ?? '';
    final previousRest = previous?.rest.text.trim() ?? '';
    final reuseReps = type != SetType.failure;
    return _SetDraft(
      type: type,
      repMin: reuseReps
          ? (previousMin.isEmpty ? '${PlannedSet.defaultRepMin}' : previousMin)
          : '',
      repMax: reuseReps
          ? (previousMin.isEmpty
                ? '${PlannedSet.defaultRepMax}'
                : previous?.repMax.text.trim() ?? '')
          : '',
      rest: previousRest.isEmpty
          ? '${PlannedSet.defaultRestSeconds}'
          : previousRest,
      minutes: previous?.minutes.text.trim() ?? '',
      seconds: previous?.seconds.text.trim() ?? '',
    );
  }

  final int id;
  SetType type;
  final TextEditingController repMin;
  final TextEditingController repMax;
  final TextEditingController load;
  final TextEditingController rest;

  /// For a cardio set, which is prescribed as time rather than reps.
  final TextEditingController minutes;
  final TextEditingController seconds;

  /// The time typed in, in seconds, or null if neither box has a number.
  int? get durationSeconds {
    final m = int.tryParse(minutes.text.trim());
    final s = int.tryParse(seconds.text.trim());
    if (m == null && s == null) return null;
    return (m ?? 0) * 60 + (s ?? 0);
  }

  void dispose() {
    repMin.dispose();
    repMax.dispose();
    load.dispose();
    rest.dispose();
    minutes.dispose();
    seconds.dispose();
  }
}

class _PlannedExerciseEditScreenState extends State<PlannedExerciseEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _note;
  final List<_SetDraft> _drafts = [];

  /// Cardio is prescribed as time, so this screen asks for minutes and
  /// seconds instead of reps and load.
  bool get _isTimed =>
      ExerciseLibrary.byId(widget.planned.exerciseId)?.exerciseType ==
      ExerciseType.cardio;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController(text: widget.planned.note);
    for (final set in widget.planned.plannedSets) {
      _drafts.add(_SetDraft.fromPlanned(set));
    }
  }

  @override
  void dispose() {
    _note.dispose();
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _addSet(SetType type) {
    setState(() {
      _drafts.add(_SetDraft.added(type, _drafts.isEmpty ? null : _drafts.last));
    });
  }

  void _removeSet(int index) {
    if (_drafts.length <= 1) return; // an exercise needs at least one set
    final removed = _drafts[index];
    setState(() => _drafts.removeAt(index));
    // Dispose after the frame, once the text fields are gone from the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  void _reorder(int oldIndex, int newIndex) {
    final next = reorderList(_drafts, oldIndex, newIndex);
    setState(() {
      _drafts
        ..clear()
        ..addAll(next);
    });
  }

  // ---- validation ----

  String? _validateRepMin(_SetDraft d, String? text) {
    final t = (text ?? '').trim();
    if (t.isEmpty) {
      if (d.type != SetType.failure) return 'Enter reps';
      // A Failure set may have no rep target, but not half of one.
      return d.repMax.text.trim().isEmpty
          ? null
          : 'Enter min reps, or clear both';
    }
    final value = parseWholeNumber(t);
    return (value == null || value < 1)
        ? 'Enter a whole number, 1 or more'
        : null;
  }

  String? _validateRepMax(_SetDraft d, String? text) {
    final t = (text ?? '').trim();
    if (t.isEmpty) return null; // blank = same as min
    final value = parseWholeNumber(t);
    if (value == null || value < 1) return 'Enter a whole number, 1 or more';
    final min = parseWholeNumber(d.repMin.text);
    if (min != null && value < min) return 'Max reps must be at least min reps';
    return null;
  }

  String? _validateLoad(String? text) => parseOptionalWeight(text ?? '').error;

  /// A timed set needs a time. Shown on the Minutes box.
  String? _validateDuration(_SetDraft d) {
    final seconds = d.durationSeconds;
    return (seconds == null || seconds <= 0) ? 'Enter how long' : null;
  }

  String? _validateRest(String? text) => parseWholeNumber(text ?? '') == null
      ? 'Enter rest in seconds (0 or more)'
      : null;

  PlannedSet _toPlannedSet(_SetDraft d) {
    final rest = parseWholeNumber(d.rest.text) ?? PlannedSet.defaultRestSeconds;

    // A timed set has a duration and no rep target: one or the other, never
    // both.
    if (_isTimed) {
      final duration = d.durationSeconds;
      return PlannedSet(
        setType: d.type,
        targetDurationSeconds: duration != null && duration > 0
            ? duration
            : null,
        restSeconds: rest,
      );
    }

    final min = parseWholeNumber(d.repMin.text);
    final max = parseWholeNumber(d.repMax.text);
    final load = parseOptionalWeight(d.load.text).value;
    return PlannedSet(
      setType: d.type,
      targetRepMin: min,
      targetRepMax: min == null ? null : (max ?? min),
      // Blank or 0 means no target load.
      targetLoadKg: (load == null || load == 0) ? null : load,
      restSeconds: rest,
    );
  }

  void _done() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      widget.planned.copyWith(
        plannedSets: [for (final d in _drafts) _toPlannedSet(d)],
        note: _note.text.trim(),
      ),
    );
  }

  // ---- UI ----

  Widget _buildSetCard(int index) {
    final theme = Theme.of(context);
    final d = _drafts[index];
    final isFailure = d.type == SetType.failure;

    return Card(
      key: ValueKey('set-draft-${d.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Icons.drag_handle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Set ${index + 1}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove set',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _drafts.length > 1
                      ? () => _removeSet(index)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in SetType.values)
                  ChoiceChip(
                    label: Text(type.label),
                    selected: d.type == type,
                    onSelected: (_) => setState(() => d.type = type),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Cardio is prescribed as time; everything else as reps and load.
            if (_isTimed)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: d.minutes,
                      keyboardType: TextInputType.number,
                      inputFormatters: [LengthLimitingTextInputFormatter(3)],
                      decoration: const InputDecoration(
                        labelText: 'Minutes',
                        border: OutlineInputBorder(),
                      ),
                      validator: (_) => _validateDuration(d),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: d.seconds,
                      keyboardType: TextInputType.number,
                      inputFormatters: [LengthLimitingTextInputFormatter(2)],
                      decoration: const InputDecoration(
                        labelText: 'Seconds',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: d.repMin,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(kRepsInputMaxLength),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Min reps',
                        helperText: isFailure ? 'Blank = To Failure' : null,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (text) => _validateRepMin(d, text),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: d.repMax,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(kRepsInputMaxLength),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Max reps',
                        border: OutlineInputBorder(),
                      ),
                      validator: (text) => _validateRepMax(d, text),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A treadmill has no load to prescribe.
                if (!_isTimed) ...[
                  Expanded(
                    child: TextFormField(
                      controller: d.load,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(kWeightInputMaxLength),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Load (kg)',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validateLoad,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: TextFormField(
                    controller: d.rest,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(kRepsInputMaxLength),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Rest (sec)',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateRest,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name =
        ExerciseLibrary.byId(widget.planned.exerciseId)?.name ??
        'Unknown exercise';

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Text('Sets', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorderItem: _reorder,
                  children: [
                    for (var i = 0; i < _drafts.length; i++) _buildSetCard(i),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: const Text('Add warm-up set'),
                      onPressed: () => _addSet(SetType.warmUp),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: const Text('Add working set'),
                      onPressed: () => _addSet(SetType.working),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: const Text('Add failure set'),
                      onPressed: () => _addSet(SetType.failure),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _note,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _done,
                    child: Text(widget.doneLabel),
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
