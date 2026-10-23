import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../recommendation/exercise_scorer.dart';
import '../../recommendation/recommendation_weights.dart';
import '../admin_data.dart';
import '../admin_widgets.dart';

/// Labels for the weights, in [RecommendationWeights.toJson] order.
const Map<String, (String, String)> kWeightLabels = {
  'goalRelevance': ('Goal relevance', 'The exercise suits the goal.'),
  'primaryMuscleMatch': (
    'Primary muscle match',
    'Per chosen muscle it trains as a main mover.',
  ),
  'secondaryMuscleMatch': (
    'Secondary muscle match',
    'Per chosen muscle it trains as a helper.',
  ),
  'patternCoverage': (
    'Pattern coverage',
    'It adds a movement pattern the workout does not have yet.',
  ),
  'equipmentFit': ('Equipment fit', 'A flat reward: eligible means it fits.'),
  'experienceFit': ('Experience fit', 'Its level suits the user.'),
  'complexityFit': ('Complexity fit', 'How demanding it is, for the user.'),
  'proportionFit': (
    'Proportion fit',
    'The most a proportion rule can move a score.',
  ),
  'priorityMuscleMatch': (
    'Priority muscle match',
    'Per muscle the user singled out that it trains as a main mover.',
  ),
};

class RecommendationPage extends StatelessWidget {
  const RecommendationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = AdminScope.of(context);
    return AdminPage(
      title: 'Recommendation',
      intro:
          'How exercises are ranked in a personalised program. Eligibility is '
          'set on each exercise; these settings only change the order.',
      children: [
        _WeightsSection(
          key: ValueKey(data.config.updatedAt),
          current: data.config.weights,
        ),
        _GoalFitSection(data: data),
      ],
    );
  }
}

class _WeightsSection extends StatefulWidget {
  const _WeightsSection({super.key, required this.current});

  /// Null when the built-in weights are in use.
  final RecommendationWeights? current;

  @override
  State<_WeightsSection> createState() => _WeightsSectionState();
}

class _WeightsSectionState extends State<_WeightsSection> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields = {
    for (final e
        in (widget.current ?? RecommendationWeights.standard).toJson().entries)
      e.key: TextEditingController(text: _fmt(e.value)),
  };

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final data = AdminScope.of(context);
    final weights = RecommendationWeights.fromJson({
      for (final e in _fields.entries) e.key: double.parse(e.value.text.trim()),
    });
    await runSave(
      context,
      () => data.service.updateConfig((c) => c.copyWith(weights: weights)),
    );
  }

  Future<void> _reset() async {
    final data = AdminScope.of(context);
    await runSave(
      context,
      () => data.service.updateConfig((c) => c.copyWith(clearWeights: true)),
    );
  }

  @override
  Widget build(BuildContext context) {
    const standard = RecommendationWeights.standard;
    final defaults = standard.toJson();
    return AdminSection(
      title: 'Ranking weights',
      subtitle: widget.current == null
          ? 'Built-in weights in use.'
          : 'Your weights are in use.',
      actions: [
        if (widget.current != null)
          TextButton(onPressed: _reset, child: const Text('Back to built-in')),
        const SizedBox(width: 8),
        FilledButton(
          key: const ValueKey('admin-save-weights'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
      child: Form(
        key: _form,
        child: Column(
          children: [
            const SourceNote(
              'These weights are app design choices. Note why you change them.',
            ),
            for (final e in _fields.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(kWeightLabels[e.key]?.$1 ?? e.key),
                          Text(
                            '${kWeightLabels[e.key]?.$2 ?? ''} '
                            'Built-in: ${_fmt(defaults[e.key] ?? 0)}.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120,
                      child: TextFormField(
                        key: ValueKey('weight-${e.key}'),
                        controller: e.value,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: (v) {
                          final n = double.tryParse((v ?? '').trim());
                          if (n == null || n < 0 || n > 1000) {
                            return '0 to 1000';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GoalFitSection extends StatelessWidget {
  const _GoalFitSection({required this.data});

  final AdminData data;

  @override
  Widget build(BuildContext context) {
    final fits = data.config.goalFit;
    return AdminSection(
      title: 'Goal fit per exercise',
      subtitle:
          'Goal fit normally comes from a rule of thumb. Set it here for one '
          'exercise.',
      actions: [
        FilledButton.icon(
          key: const ValueKey('admin-add-goal-fit'),
          onPressed: () async {
            final picked = await pickExercises(
              context,
              all: data.allExercises,
              selected: const [],
              single: true,
            );
            if (picked == null || picked.isEmpty || !context.mounted) return;
            await _edit(context, picked.single);
          },
          icon: const Icon(Icons.add),
          label: const Text('Set for an exercise'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SourceNote(
            'The built-in goal fit is an implementation heuristic, not a '
            'measured finding. A value you set is also an app design choice.',
          ),
          if (fits.isEmpty) const Text('None set. The rule of thumb applies.'),
          for (final e in fits.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(data.exerciseName(e.key)),
              subtitle: Text(
                e.value.entries
                    .map(
                      (g) =>
                          '${_goalLabel(g.key)} ${g.value.toStringAsFixed(1)}',
                    )
                    .join(' · '),
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _edit(context, e.key),
            ),
        ],
      ),
    );
  }

  static String _goalLabel(String name) {
    for (final g in TrainingGoal.values) {
      if (g.name == name) return g.label;
    }
    return name;
  }

  Future<void> _edit(BuildContext context, String exerciseId) async {
    final exercise = data.exerciseById(exerciseId);
    if (exercise == null) return;
    final result = await showDialog<Map<String, double>>(
      context: context,
      builder: (_) => _GoalFitDialog(
        exercise: exercise,
        current: data.config.goalFit[exerciseId] ?? const {},
      ),
    );
    if (result == null || !context.mounted) return;
    await runSave(
      context,
      () => data.service.updateConfig((c) {
        final next = {...c.goalFit};
        if (result.isEmpty) {
          next.remove(exerciseId);
        } else {
          next[exerciseId] = result;
        }
        return c.copyWith(goalFit: next);
      }),
    );
  }
}

class _GoalFitDialog extends StatefulWidget {
  const _GoalFitDialog({required this.exercise, required this.current});

  final Exercise exercise;
  final Map<String, double> current;

  @override
  State<_GoalFitDialog> createState() => _GoalFitDialogState();
}

class _GoalFitDialogState extends State<_GoalFitDialog> {
  late final Map<String, double> _values = {...widget.current};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Goal fit: ${widget.exercise.name}'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '0 means it does not suit the goal at all, 1 means it suits it '
              'fully. Untick a goal to keep the rule of thumb for it.',
            ),
            const SizedBox(height: 12),
            for (final g in TrainingGoal.values)
              Builder(
                builder: (context) {
                  final builtIn = builtInGoalFit(widget.exercise, g);
                  final chosen = _values[g.name];
                  return Row(
                    children: [
                      Checkbox(
                        value: chosen != null,
                        onChanged: (on) => setState(() {
                          if (on == true) {
                            _values[g.name] = builtIn;
                          } else {
                            _values.remove(g.name);
                          }
                        }),
                      ),
                      SizedBox(
                        width: 170,
                        child: Text(g.label, style: theme.textTheme.bodySmall),
                      ),
                      Expanded(
                        child: Slider(
                          value: chosen ?? builtIn,
                          divisions: 10,
                          label: (chosen ?? builtIn).toStringAsFixed(1),
                          onChanged: chosen == null
                              ? null
                              : (v) => setState(() => _values[g.name] = v),
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(
                          chosen == null
                              ? 'Rule ${builtIn.toStringAsFixed(1)}'
                              : '${chosen.toStringAsFixed(1)} '
                                    '(rule ${builtIn.toStringAsFixed(1)})',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(<String, double>{}),
          child: const Text('Clear all'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_values),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
