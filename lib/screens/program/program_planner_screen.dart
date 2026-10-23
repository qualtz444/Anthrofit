import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/id.dart';
import '../../core/list_utils.dart';
import '../../data/exercise_library.dart';
import '../../data/workout_templates.dart';
import '../../models/models.dart';
import '../../state/profile_scope.dart';
import '../../state/program_scope.dart';
import 'template_picker_screens.dart';
import 'workout_editor_screen.dart';
import '../../core/snack_bar_timing.dart';

/// PLANNING: create a new program, or edit a saved one.
///
/// For a new program, [template] decides which workouts are created for the
/// user to review (Push Pull Legs, Upper Lower, Full Body, or none for
/// Custom). No weekdays are assigned: the user chooses the training days.
///
/// Everything here is a draft until "Save program". The saved result is a
/// TrainingProgram (see Program screens).
///
/// Rules enforced on save:
///  - a program name
///  - at least one training day, and at least one workout
///  - every training day has a workout (one workout per day)
/// A workout may be used on several days, or on none.
class ProgramPlannerScreen extends StatefulWidget {
  const ProgramPlannerScreen({
    super.key,
    this.program,
    this.template,
    this.goal,
    this.initialName,
    this.setup,
  });

  /// Null = create a new program.
  final TrainingProgram? program;

  /// Used only when [program] is null.
  final ProgramTemplate? template;

  /// The goal chosen for a NEW program (when [program] is null).
  final TrainingGoal? goal;

  /// The name chosen for a NEW program. Defaults to the template's name.
  final String? initialName;

  /// The setup answers for a NEW program (goal, session length, muscles,
  /// equipment). Recorded on the program for the future generator.
  final ProgramSetup? setup;

  @override
  State<ProgramPlannerScreen> createState() => _ProgramPlannerScreenState();
}

class _ProgramPlannerScreenState extends State<ProgramPlannerScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final String _programId;
  late final DateTime _createdAt;

  TrainingGoal? _goal;
  ProgramSetup? _setup;
  final Set<Weekday> _days = {};

  /// Which workouts run on each day. A day can hold more than one: two
  /// sessions, or a lift and some cardio.
  final Map<Weekday, List<String>> _assignments = {};
  List<Workout> _workouts = [];

  bool _showErrors = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final program = widget.program;
    _programId = program?.id ?? generateId();
    _createdAt = program?.createdAt ?? DateTime.now();
    _name = TextEditingController(text: program?.name ?? '');
    final template = widget.template;
    if (program == null) {
      _goal = widget.goal;
      _setup = widget.setup;
      if (template != null) {
        _name.text = widget.initialName ?? template.defaultName;
        _workouts = buildWorkoutsForProgram(template);
      } else if (widget.initialName != null) {
        _name.text = widget.initialName!;
      }
    }
    if (program != null) {
      _goal = program.goal;
      _setup = program.setup;
      _workouts = List.of(program.workouts);
      for (final slot in program.schedule) {
        _days.add(slot.day);
        (_assignments[slot.day] ??= []).add(slot.workoutId);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<Weekday> get _selectedDays =>
      Weekday.values.where(_days.contains).toList();

  bool get _hasProblems =>
      _days.isEmpty ||
      _workouts.isEmpty ||
      _selectedDays.any((d) => (_assignments[d] ?? const []).isEmpty);

  void _toggleDay(Weekday day, bool isOn) {
    setState(() {
      if (isOn) {
        _days.add(day);
      } else {
        _days.remove(day);
        _assignments.remove(day);
      }
    });
  }

  /// Choose a workout type, seed it from the template, then let the user edit.
  Future<void> _addWorkout() async {
    final template = await Navigator.of(context).push<WorkoutTemplate>(
      MaterialPageRoute<WorkoutTemplate>(
        builder: (_) => const WorkoutTemplateScreen(),
      ),
    );
    if (template == null || !mounted) return;

    final seeded = buildWorkoutFromTemplate(template);
    final startsEmptyByDesign =
        template != WorkoutTemplate.custom && seeded.exercises.isEmpty;
    final result = await Navigator.of(context).push<Workout>(
      MaterialPageRoute<Workout>(
        builder: (_) => WorkoutEditorScreen(
          workout: seeded,
          isNew: true,
          notice: startsEmptyByDesign
              ? 'The exercise library has no ${template.label.toLowerCase()} '
                    'exercises yet, so this workout starts empty.'
              : null,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _workouts = [..._workouts, result]);
  }

  Future<void> _editWorkout(Workout workout) async {
    final result = await Navigator.of(context).push<Workout>(
      MaterialPageRoute<Workout>(
        builder: (_) => WorkoutEditorScreen(workout: workout),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _workouts = [for (final w in _workouts) w.id == result.id ? result : w];
    });
  }

  void _removeWorkout(Workout workout) {
    setState(() {
      _workouts = _workouts.where((w) => w.id != workout.id).toList();
      // A removed workout cannot stay on any day.
      for (final onDay in _assignments.values) {
        onDay.remove(workout.id);
      }
    });
  }

  Future<void> _save() async {
    final controller = ProgramScope.of(context, listen: false);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final nameOk = _formKey.currentState!.validate();
    if (!nameOk || _hasProblems) {
      setState(() => _showErrors = true);
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text('Fix the highlighted items to continue.')),
      );
      return;
    }

    final program = TrainingProgram(
      id: _programId,
      name: _name.text.trim(),
      goal: _goal,
      // Carried through unchanged: editing a program does not re-ask setup.
      setup: _setup,
      archived: widget.program?.archived ?? false,
      workouts: _workouts,
      schedule: [
        for (final day in _selectedDays)
          for (final workoutId in _assignments[day] ?? const <String>[])
            ScheduledWorkout(day: day, workoutId: workoutId),
      ],
      createdAt: _createdAt,
      updatedAt: DateTime.now(),
    );

    setState(() => _saving = true);
    try {
      await controller.saveProgram(program);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't save the program. Try again.")),
      );
      return;
    }
    if (!mounted) return;
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profileDays = ProfileScope.of(
      context,
    ).profile?.trainingFrequency.label;
    final errorStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.error,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.program == null ? 'New program' : 'Edit program'),
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
                    labelText: 'Program name',
                    hintText: 'e.g. 4-Day Hypertrophy',
                    border: OutlineInputBorder(),
                  ),
                  validator: (text) => (text == null || text.trim().isEmpty)
                      ? 'Enter a program name'
                      : null,
                ),

                // ---- Goal (this program's own) ----
                const SizedBox(height: 24),
                const _SectionTitle('Goal'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final goal in TrainingGoal.values)
                      ChoiceChip(
                        label: Text(goal.label),
                        selected: _goal == goal,
                        onSelected: (_) => setState(() => _goal = goal),
                      ),
                  ],
                ),

                // ---- Training days ----
                const SizedBox(height: 24),
                const _SectionTitle('Training days'),
                if (profileDays != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Your profile: $profileDays training days per week. '
                      'Choose the days you will actually train.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final day in Weekday.values)
                      FilterChip(
                        label: Text(day.shortLabel),
                        selected: _days.contains(day),
                        onSelected: (isOn) => _toggleDay(day, isOn),
                      ),
                  ],
                ),
                if (_showErrors && _days.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Choose at least one training day',
                      style: errorStyle,
                    ),
                  ),

                // ---- Workouts ----
                const SizedBox(height: 24),
                const _SectionTitle('Workouts'),
                const SizedBox(height: 8),
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorderItem: (oldIndex, newIndex) {
                    setState(() {
                      _workouts = reorderList(_workouts, oldIndex, newIndex);
                    });
                  },
                  children: [
                    for (var i = 0; i < _workouts.length; i++)
                      Card(
                        key: ValueKey('planner-workout-${_workouts[i].id}'),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: ReorderableDragStartListener(
                            index: i,
                            child: const Icon(Icons.drag_handle),
                          ),
                          title: Text(
                            _workouts[i].name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_workouts[i].focus.isNotEmpty)
                                Text(_workouts[i].focus),
                              Text(
                                '${pluralize(_workouts[i].exerciseCount, 'exercise')} · ${pluralize(_workouts[i].totalSets, 'set')}',
                              ),
                              if (_workouts[i].exercises.isNotEmpty)
                                Text(
                                  _workouts[i].exercises
                                      .map(
                                        (e) =>
                                            ExerciseLibrary.byId(
                                              e.exerciseId,
                                            )?.name ??
                                            'Unknown exercise',
                                      )
                                      .join(', '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                          trailing: IconButton(
                            tooltip: 'Remove workout',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _removeWorkout(_workouts[i]),
                          ),
                          onTap: () => _editWorkout(_workouts[i]),
                        ),
                      ),
                  ],
                ),
                if (_showErrors && _workouts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Add at least one workout', style: errorStyle),
                  ),
                OutlinedButton.icon(
                  onPressed: _addWorkout,
                  icon: const Icon(Icons.add),
                  label: const Text('Add workout'),
                ),

                // ---- Schedule ----
                if (_days.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const _SectionTitle('Schedule'),
                  const SizedBox(height: 4),
                  if (_workouts.isEmpty)
                    Text(
                      'Add a workout to schedule it.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    for (final day in _selectedDays)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(day.label, style: theme.textTheme.titleSmall),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final workout in _workouts)
                                  FilterChip(
                                    label: Text(workout.name),
                                    selected: (_assignments[day] ?? const [])
                                        .contains(workout.id),
                                    onSelected: (isOn) => setState(() {
                                      final onDay = _assignments[day] ??= [];
                                      if (isOn) {
                                        onDay.add(workout.id);
                                      } else {
                                        onDay.remove(workout.id);
                                      }
                                    }),
                                  ),
                              ],
                            ),
                            if (_showErrors && !_assignments.containsKey(day))
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Choose a workout',
                                  style: errorStyle,
                                ),
                              ),
                          ],
                        ),
                      ),
                ],

                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: const Text('Save program'),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium);
  }
}
