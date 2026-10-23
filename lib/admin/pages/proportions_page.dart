import 'package:flutter/material.dart';

import '../../content/content_models.dart';
import '../../models/models.dart';
import '../../recommendation/proportion_rules.dart';
import '../admin_data.dart';
import '../admin_widgets.dart';

/// The ratios the rules use, with what the built-in cut-offs are based on
/// (from proportion_rules.dart).
const Map<String, (String, String)> kRatios = {
  RatioKeys.femurToTorso: ('Femur : torso', 'median'),
  RatioKeys.armToTorso: ('Arm : torso', 'median'),
  RatioKeys.upperBodyToStature: ('Upper body : stature', 'Q1 / Q3'),
  RatioKeys.shoulderToHip: ('Shoulder : hip', 'Q1 / Q3'),
};

String ratioLabel(String key) => kRatios[key]?.$1 ?? key;

String classLabel(ProportionClass c) => switch (c) {
  ProportionClass.low => 'Low (at or below the lower cut-off)',
  ProportionClass.typical => 'Typical (between the cut-offs)',
  ProportionClass.high => 'High (at or above the upper cut-off)',
  ProportionClass.unknown => 'Unknown',
};

class ProportionsPage extends StatelessWidget {
  const ProportionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = AdminScope.of(context);
    return AdminPage(
      title: 'Proportions',
      intro:
          'The cut-offs that sort a body ratio into low, typical or high, '
          'and the rules that nudge exercises up or down for each.',
      children: [
        const SourceNote(
          'Built-in cut-offs come from this project\'s own participants. Ratios '
          'must be computed the same way as the scan (Measurement.kt).',
          warning: true,
        ),
        _CutoffsSection(data: data),
        _BuiltInRulesSection(data: data),
        _AdminRulesSection(data: data),
      ],
    );
  }
}

String _num(double v) => v.toStringAsFixed(3);

class _CutoffsSection extends StatelessWidget {
  const _CutoffsSection({required this.data});

  final AdminData data;

  @override
  Widget build(BuildContext context) {
    final overrides = data.config.thresholds;
    return AdminSection(
      title: 'Cut-offs',
      child: Column(
        children: [
          for (final e in kRatios.entries)
            Builder(
              builder: (context) {
                final builtIn = ProportionThresholds.participants.byRatio[e.key];
                final o = overrides[e.key];
                return ListTile(
                  key: ValueKey('admin-cutoff-${e.key}'),
                  contentPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Text(e.value.$1),
                      if (o != null) const AdminBadge('Replaced', strong: true),
                    ],
                  ),
                  subtitle: Text(
                    [
                      if (builtIn != null)
                        'Built-in: ${_num(builtIn.low)} / ${_num(builtIn.high)} '
                            '(${e.value.$2} of this project\'s participants)',
                      if (o != null)
                        'In use: ${_num(o.low)} / ${_num(o.high)}. '
                            'Source: ${o.source}',
                    ].join('\n'),
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _edit(context, e.key, o, builtIn),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    String key,
    ThresholdOverride? current,
    RatioThreshold? builtIn,
  ) async {
    final result = await showDialog<_CutoffResult>(
      context: context,
      builder: (_) => _CutoffDialog(
        title: ratioLabel(key),
        current: current,
        builtIn: builtIn,
      ),
    );
    if (result == null || !context.mounted) return;
    await runSave(
      context,
      () => data.service.updateConfig((c) {
        final next = {...c.thresholds};
        final value = result.value;
        if (value == null) {
          next.remove(key);
        } else {
          next[key] = value;
        }
        return c.copyWith(thresholds: next);
      }),
    );
  }
}

class _CutoffResult {
  const _CutoffResult(this.value);

  /// Null means back to the built-in cut-off.
  final ThresholdOverride? value;
}

class _CutoffDialog extends StatefulWidget {
  const _CutoffDialog({
    required this.title,
    required this.current,
    required this.builtIn,
  });

  final String title;
  final ThresholdOverride? current;
  final RatioThreshold? builtIn;

  @override
  State<_CutoffDialog> createState() => _CutoffDialogState();
}

class _CutoffDialogState extends State<_CutoffDialog> {
  final _form = GlobalKey<FormState>();
  late final _low = TextEditingController(
    text: (widget.current?.low ?? widget.builtIn?.low)?.toString(),
  );
  late final _high = TextEditingController(
    text: (widget.current?.high ?? widget.builtIn?.high)?.toString(),
  );
  late final _source = TextEditingController(text: widget.current?.source);

  @override
  void dispose() {
    _low.dispose();
    _high.dispose();
    _source.dispose();
    super.dispose();
  }

  String? _number(String? v) {
    final n = double.tryParse((v ?? '').trim());
    if (n == null || n <= 0 || n > 10) return 'A ratio between 0 and 10';
    return null;
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.of(context).pop(
      _CutoffResult(
        ThresholdOverride(
          low: double.parse(_low.text.trim()),
          high: double.parse(_high.text.trim()),
          source: _source.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.title} cut-offs'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'At or below the lower value is low, at or above the upper '
                'value is high. For a median split, enter the median in both.',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const ValueKey('cutoff-low'),
                      controller: _low,
                      decoration: const InputDecoration(labelText: 'Lower'),
                      validator: _number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      key: const ValueKey('cutoff-high'),
                      controller: _high,
                      decoration: const InputDecoration(labelText: 'Upper'),
                      validator: (v) {
                        final bad = _number(v);
                        if (bad != null) return bad;
                        final low = double.tryParse(_low.text.trim());
                        final high = double.parse(v!.trim());
                        if (low != null && high < low) {
                          return 'Must be at least the lower value';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              TextFormField(
                key: const ValueKey('cutoff-source'),
                controller: _source,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Source (required)',
                  helperText:
                      'Where these numbers come from: a paper, or your own '
                      'sample and how it was split.',
                ),
                validator: (v) => (v ?? '').trim().length < 5
                    ? 'Say where these numbers come from'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.current != null)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const _CutoffResult(null)),
            child: const Text('Back to built-in'),
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

class _BuiltInRulesSection extends StatelessWidget {
  const _BuiltInRulesSection({required this.data});

  final AdminData data;

  @override
  Widget build(BuildContext context) {
    final disabled = data.config.disabledRules;
    return AdminSection(
      title: 'Built-in rules',
      subtitle:
          'Practical setup observations, not findings: the direction is a '
          'coaching convention and the size of each nudge is small by design.',
      child: Column(
        children: [
          for (final rule in kProportionRules)
            SwitchListTile(
              key: ValueKey('admin-rule-${rule.name}'),
              contentPadding: EdgeInsets.zero,
              title: Text(rule.name),
              subtitle: Text(
                [
                  for (final a in rule.advice.entries)
                    '${ratioLabel(rule.ratioKey)} ${a.key.name}: '
                        '${a.value.scoreDelta >= 0 ? '+' : ''}'
                        '${a.value.scoreDelta}',
                ].join(' · '),
              ),
              value: !disabled.contains(rule.name),
              onChanged: (on) => runSave(
                context,
                () => data.service.updateConfig((c) {
                  final next = {...c.disabledRules};
                  if (on) {
                    next.remove(rule.name);
                  } else {
                    next.add(rule.name);
                  }
                  return c.copyWith(disabledRules: next);
                }),
              ),
            ),
        ],
      ),
    );
  }
}

class _AdminRulesSection extends StatelessWidget {
  const _AdminRulesSection({required this.data});

  final AdminData data;

  @override
  Widget build(BuildContext context) {
    final rules = data.config.proportionRules;
    return AdminSection(
      title: 'Your rules',
      subtitle:
          'A rule picks exercises, a ratio and a class, and moves their score '
          'by -1 to 1 (scaled by the Proportion fit weight).',
      actions: [
        FilledButton.icon(
          key: const ValueKey('admin-add-rule'),
          onPressed: () => _edit(context, null),
          icon: const Icon(Icons.add),
          label: const Text('Add rule'),
        ),
      ],
      child: rules.isEmpty
          ? const Text('None yet.')
          : Column(
              children: [
                for (final r in rules)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Row(
                      children: [
                        Flexible(child: Text(r.name)),
                        if (!r.enabled) const AdminBadge('Off'),
                      ],
                    ),
                    subtitle: Text(
                      '${ratioLabel(r.ratioKey)} ${r.whenClass.name} → '
                      '${r.scoreDelta >= 0 ? '+' : ''}${r.scoreDelta} on '
                      '${r.exerciseIds.map(data.exerciseName).join(', ')}',
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _edit(context, r),
                  ),
              ],
            ),
    );
  }

  Future<void> _edit(BuildContext context, AdminProportionRule? existing) async {
    final result = await showDialog<_RuleResult>(
      context: context,
      builder: (_) =>
          _RuleDialog(existing: existing, all: data.allExercises, data: data),
    );
    if (result == null || !context.mounted) return;
    await runSave(
      context,
      () => data.service.updateConfig((c) {
        final next = [
          for (final r in c.proportionRules)
            if (r.id != existing?.id) r else if (!result.delete) result.rule!,
          if (existing == null && !result.delete) result.rule!,
        ];
        return c.copyWith(proportionRules: next);
      }),
    );
  }
}

class _RuleResult {
  const _RuleResult.save(AdminProportionRule this.rule) : delete = false;
  const _RuleResult.delete() : rule = null, delete = true;
  final AdminProportionRule? rule;
  final bool delete;
}

class _RuleDialog extends StatefulWidget {
  const _RuleDialog({
    required this.existing,
    required this.all,
    required this.data,
  });

  final AdminProportionRule? existing;
  final List<Exercise> all;
  final AdminData data;

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _cue = TextEditingController(text: widget.existing?.cue);
  late final _reason = TextEditingController(text: widget.existing?.reason);
  late final _rationale = TextEditingController(
    text: widget.existing?.rationale,
  );
  late String _ratio = widget.existing?.ratioKey ?? RatioKeys.femurToTorso;
  late ProportionClass _class =
      widget.existing?.whenClass ?? ProportionClass.high;
  late double _delta = widget.existing?.scoreDelta ?? 0;
  late List<String> _exercises = [...?widget.existing?.exerciseIds];
  late bool _enabled = widget.existing?.enabled ?? true;
  bool _showErrors = false;

  @override
  void dispose() {
    _name.dispose();
    _cue.dispose();
    _reason.dispose();
    _rationale.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate() ||
        _exercises.isEmpty ||
        _delta == 0) {
      setState(() => _showErrors = true);
      return;
    }
    Navigator.of(context).pop(
      _RuleResult.save(
        AdminProportionRule(
          id:
              widget.existing?.id ??
              'rule_${DateTime.now().millisecondsSinceEpoch}',
          name: _name.text.trim(),
          ratioKey: _ratio,
          whenClass: _class,
          scoreDelta: _delta,
          exerciseIds: _exercises,
          rationale: _rationale.text.trim(),
          cue: _cue.text.trim().isEmpty ? null : _cue.text.trim(),
          reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
          enabled: _enabled,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = TextStyle(color: theme.colorScheme.error);
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add rule' : 'Edit rule'),
      content: SizedBox(
        width: 560,
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: EnumDropdown<String>(
                        label: 'Ratio',
                        value: _ratio,
                        values: kRatios.keys.toList(),
                        text: ratioLabel,
                        onChanged: (v) => setState(() => _ratio = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: EnumDropdown<ProportionClass>(
                        label: 'When it is',
                        value: _class,
                        values: const [
                          ProportionClass.low,
                          ProportionClass.typical,
                          ProportionClass.high,
                        ],
                        text: classLabel,
                        onChanged: (v) => setState(() => _class = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Score nudge: ${_delta >= 0 ? '+' : ''}'
                  '${_delta.toStringAsFixed(1)}',
                ),
                Slider(
                  value: _delta,
                  min: -1,
                  max: 1,
                  divisions: 20,
                  label: _delta.toStringAsFixed(1),
                  onChanged: (v) => setState(() => _delta = v),
                ),
                if (_showErrors && _delta == 0)
                  Text('A rule with no nudge changes nothing', style: error),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _exercises.isEmpty
                            ? 'No exercises chosen'
                            : _exercises
                                  .map(widget.data.exerciseName)
                                  .join(', '),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final picked = await pickExercises(
                          context,
                          all: widget.all,
                          selected: _exercises,
                        );
                        if (picked != null) {
                          setState(() => _exercises = picked);
                        }
                      },
                      child: const Text('Choose exercises'),
                    ),
                  ],
                ),
                if (_showErrors && _exercises.isEmpty)
                  Text('Choose at least one exercise', style: error),
                TextFormField(
                  controller: _cue,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(
                    labelText: 'Setup cue shown with the exercise (optional)',
                  ),
                ),
                TextFormField(
                  controller: _reason,
                  decoration: const InputDecoration(
                    labelText:
                        'Reason, finishing "Recommended because it…" '
                        '(optional)',
                  ),
                ),
                TextFormField(
                  controller: _rationale,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Why this rule exists (required)',
                    helperText:
                        'A source, or say plainly it is a coaching '
                        'convention. Never shown to users.',
                  ),
                  validator: (v) => (v ?? '').trim().length < 5
                      ? 'Say why this rule exists'
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('On'),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
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
                Navigator.of(context).pop(const _RuleResult.delete()),
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
