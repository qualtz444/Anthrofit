import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../state/program_scope.dart';
import '../../core/snack_bar_timing.dart';

/// Editing the training days of one program, and nothing else.
///
/// Reached from the pencil beside Schedule on Program Detail. The program's
/// name and its workouts are edited from their own places, so this screen
/// cannot change either.
class ScheduleEditScreen extends StatefulWidget {
  const ScheduleEditScreen({super.key, required this.program});

  final TrainingProgram program;

  @override
  State<ScheduleEditScreen> createState() => _ScheduleEditScreenState();
}

class _ScheduleEditScreenState extends State<ScheduleEditScreen> {
  /// Which workouts run on each day. A day that is not a key is a rest day;
  /// a day with an empty list is chosen but not filled in yet.
  ///
  /// A list, not a single id: a day can hold two sessions, or a lift and
  /// some cardio.
  late Map<Weekday, List<String>> _byDay;
  bool _showErrors = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _byDay = {};
    for (final entry in widget.program.schedule) {
      _byDay.putIfAbsent(entry.day, () => []).add(entry.workoutId);
    }
  }

  List<Workout> get _workouts => widget.program.workouts;

  /// Days chosen but with no workout picked yet.
  List<Weekday> get _unassigned => [
    for (final day in Weekday.values)
      if (_byDay[day]?.isEmpty ?? false) day,
  ];

  void _toggleDay(Weekday day, bool isOn) {
    setState(() {
      if (isOn) {
        // One workout: assign it straight away, so one tap is enough.
        _byDay[day] = _workouts.length == 1 ? [_workouts.single.id] : [];
      } else {
        _byDay.remove(day);
      }
      _showErrors = false;
    });
  }

  Future<void> _save() async {
    if (_unassigned.isNotEmpty) {
      setState(() => _showErrors = true);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final controller = ProgramScope.of(context, listen: false);

    setState(() => _saving = true);
    try {
      await controller.saveProgram(
        widget.program.copyWith(
          schedule: [
            for (final day in Weekday.values)
              for (final workoutId in _byDay[day] ?? const <String>[])
                ScheduledWorkout(day: day, workoutId: workoutId),
          ],
          updatedAt: DateTime.now(),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't save the schedule. Try again.")),
      );
      return;
    }
    if (!mounted) return;
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chosen = [
      for (final day in Weekday.values)
        if (_byDay.containsKey(day)) day,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Edit schedule')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Training days', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Pick the days you train, then choose which workouts run on '
              'each. A day can have more than one.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final day in Weekday.values)
                  FilterChip(
                    label: Text(day.compactLabel),
                    selected: _byDay.containsKey(day),
                    onSelected: (isOn) => _toggleDay(day, isOn),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            if (_workouts.isEmpty)
              Text(
                'This program has no workouts yet, so there is nothing to '
                'schedule. Add one first.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else if (chosen.isEmpty)
              Text(
                'No training days chosen. Every day is a rest day.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final day in chosen)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
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
                              selected:
                                  _byDay[day]?.contains(workout.id) ?? false,
                              onSelected: (isOn) => setState(() {
                                final onDay = _byDay[day] ??= [];
                                if (isOn) {
                                  // Appended, so the order on the day is the
                                  // order they were chosen.
                                  onDay.add(workout.id);
                                } else {
                                  onDay.remove(workout.id);
                                }
                                _showErrors = false;
                              }),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            if (_showErrors && _unassigned.isNotEmpty)
              Text(
                'Choose a workout for '
                '${_unassigned.map((d) => d.label).join(', ')}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Save schedule'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
