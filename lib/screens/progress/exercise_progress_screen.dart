import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/units.dart';
import '../../data/training_stats.dart';
import '../../intelligence/ai_explainer.dart';
import '../../models/models.dart';
import '../../progress/progress_analytics_service.dart';
import '../../state/profile_scope.dart';
import '../../state/session_scope.dart';
import '../widgets/ai_explain_button.dart';
import '../widgets/empty_state.dart';
import 'range_selector.dart';
import 'simple_line_chart.dart';

/// A visual, set-by-set view of one exercise's actual logged performance.
/// All summaries and chart points come from completed work sets only.
class ExerciseProgressScreen extends StatefulWidget {
  const ExerciseProgressScreen({
    super.key,
    required this.exerciseId,
    this.initialRange = ProgressRange.allTime,
  });

  final String exerciseId;
  final ProgressRange initialRange;

  @override
  State<ExerciseProgressScreen> createState() => _ExerciseProgressScreenState();
}

enum _ProgressMetric { weight, reps, volume }

class _ExerciseProgressScreenState extends State<ExerciseProgressScreen> {
  late ProgressRange _range = widget.initialRange;
  _ProgressMetric _metric = _ProgressMetric.weight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final units = unitsOf(context);
    final sessions = SessionScope.of(context).completedSessions;
    final today = DateTime.now();
    final all = exerciseHistory(sessions, widget.exerciseId);

    if (all.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Exercise progress')),
        body: const EmptyState(
          title: 'No recorded performance for this exercise yet.',
        ),
      );
    }

    final entries = all.where((e) => isInRange(e.date, _range, today)).toList();
    final newestFirstEntries = entries.reversed.toList();
    final bestWeight = _maxOrNull(
      entries.map((e) => e.heaviestKg).whereType<double>(),
    );
    final bestReps = _maxIntOrNull(entries.map((e) => e.mostReps));
    final totalVolume = entries.fold<double>(
      0,
      (sum, e) => sum + _sessionVolume(e),
    );
    final bestSet = _bestSet(entries);
    // The same one-line insight the Strength tab used to show, from the
    // app's rules, for the chosen chart.
    final trend = ProgressAnalytics(
      sessions: sessions,
      today: today,
    ).exerciseTrend(widget.exerciseId, _range);
    final insight = trend.isEmpty ? null : _insightFor(trend, units);
    final chartPoints = [
      for (final entry in entries)
        if (_valueFor(entry, units) != null)
          LinePoint(
            label: formatShortDate(entry.date),
            value: _valueFor(entry, units)!,
            valueLabel: _formatMetric(_valueFor(entry, units)!, units),
          ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(all.last.exerciseName)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text(
            'Your progress',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Based on sets you actually completed.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          RangeSelector(
            selected: _range,
            onChanged: (range) => setState(() => _range = range),
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No logged sets in this time range. Try a longer range.',
                ),
              ),
            )
          else ...[
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.55,
              children: [
                _SummaryCard(
                  label: 'Heaviest weight',
                  value: bestWeight == null
                      ? '—'
                      : formatWeight(bestWeight, units),
                  icon: Icons.fitness_center,
                ),
                _SummaryCard(
                  label: 'Sessions',
                  value: '${entries.length}',
                  icon: Icons.calendar_month_outlined,
                ),
                _SummaryCard(
                  label: 'Total volume',
                  value: totalVolume > 0
                      ? formatVolume(totalVolume, units)
                      : '—',
                  icon: Icons.stacked_bar_chart,
                ),
                _SummaryCard(
                  label: 'Best set',
                  value: bestSet == null ? '—' : _setLabel(bestSet, units),
                  icon: Icons.emoji_events_outlined,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Best set: the one set with the most weight × reps (most reps '
              'for bodyweight work). Volume adds up weight × reps.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Performance over time',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip(
                  label: 'Weight',
                  selected: _metric == _ProgressMetric.weight,
                  onTap: () => setState(() => _metric = _ProgressMetric.weight),
                ),
                _MetricChip(
                  label: 'Reps',
                  selected: _metric == _ProgressMetric.reps,
                  onTap: () => setState(() => _metric = _ProgressMetric.reps),
                ),
                _MetricChip(
                  label: 'Volume',
                  selected: _metric == _ProgressMetric.volume,
                  onTap: () => setState(() => _metric = _ProgressMetric.volume),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _metricTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _metricDescription(units),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Always drawn: an empty plot with a message, or one
                    // dot, rather than no chart at all.
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SimpleLineChart(
                          key: const ValueKey('exercise-chart'),
                          points: chartPoints,
                          height: 190,
                        ),
                        if (chartPoints.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 48,
                            ),
                            child: Text(
                              _emptyText,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (chartPoints.length == 1)
                      Text(
                        'Log this exercise in another session to see a '
                        'trend.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (insight != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        insight,
                        key: const ValueKey('exercise-insight'),
                        style: theme.textTheme.bodyMedium,
                      ),
                      AiExplainButton(
                        request: ExplainRequest(
                          kind: ExplainKind.insights,
                          facts: [
                            'Exercise: ${all.last.exerciseName}',
                            '$_metricTitle, ${_range.label}.',
                            insight,
                          ],
                        ),
                      ),
                    ],
                    if (_metric == _ProgressMetric.volume) ...[
                      const Divider(),
                      _KeyValueRow(
                        label: 'Total volume in range',
                        value: formatVolume(totalVolume, units),
                      ),
                    ],
                    if (_metric == _ProgressMetric.reps) ...[
                      const Divider(),
                      _KeyValueRow(
                        label: 'Most reps in one set',
                        value: bestReps == null ? '—' : '$bestReps reps',
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            _SessionPager(
              key: ValueKey('sessions-${_range.name}'),
              entries: newestFirstEntries,
              today: today,
              units: units,
            ),
          ],
        ],
      ),
    );
  }

  String get _metricTitle => switch (_metric) {
    _ProgressMetric.weight => 'Heaviest set each session',
    _ProgressMetric.reps => 'Most reps in one set',
    _ProgressMetric.volume => 'Training volume each session',
  };

  String _metricDescription(WeightUnit units) => switch (_metric) {
    _ProgressMetric.weight =>
      'The highest weight you logged for this exercise (${units.short}).',
    _ProgressMetric.reps =>
      'The highest rep count in a single set, including bodyweight sets.',
    _ProgressMetric.volume =>
      'Weight × reps summed across weighted working sets (${units.short}·reps).',
  };

  double? _valueFor(ExerciseEntry entry, WeightUnit units) => switch (_metric) {
    _ProgressMetric.weight =>
      entry.heaviestKg != null ? enteredFromKg(entry.heaviestKg!, units) : null,
    _ProgressMetric.reps =>
      entry.mostReps > 0 ? entry.mostReps.toDouble() : null,
    _ProgressMetric.volume =>
      _hasWeightedSets(entry)
          ? enteredFromKg(_sessionVolume(entry), units)
          : null,
  };

  String _formatMetric(double value, WeightUnit units) => switch (_metric) {
    _ProgressMetric.weight => '${formatNumber(value)} ${units.short}',
    _ProgressMetric.reps => '${formatNumber(value)} reps',
    _ProgressMetric.volume => formatVolume(kgFromEntered(value, units), units),
  };

  String get _emptyText => switch (_metric) {
    _ProgressMetric.weight =>
      'No weight logged for this exercise in this range. Reps shows its '
          'reps instead.',
    _ProgressMetric.reps => 'No reps logged for this exercise in this range.',
    _ProgressMetric.volume =>
      'No weighted sets logged for this exercise in this range.',
  };

  String _insightFor(List<ExerciseSession> trend, WeightUnit units) =>
      switch (_metric) {
        _ProgressMetric.weight => weightInsight(trend, units),
        _ProgressMetric.reps => repInsight(trend, units),
        _ProgressMetric.volume => volumeInsight(
          [
            for (final s in trend)
              if (s.volumeKg > 0) (date: s.date, volumeKg: s.volumeKg),
          ],
          units,
          noun: 'session volume',
        ),
      };
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
  );
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.entry,
    required this.today,
    required this.units,
  });

  final ExerciseEntry entry;
  final DateTime today;
  final WeightUnit units;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final volume = _sessionVolume(entry);
    final totalReps = entry.sets.fold<int>(
      0,
      (sum, set) => sum + (set.reps ?? 0),
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatDate(entry.date, today: today),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${entry.sets.length} sets · $totalReps reps',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (entry.heaviestKg != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Best ${formatWeight(entry.heaviestKg!, units)}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.45,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(width: 38, child: Text('SET')),
                  const Expanded(
                    child: Text('WEIGHT', textAlign: TextAlign.center),
                  ),
                  const Expanded(child: Text('REPS', textAlign: TextAlign.end)),
                ],
              ),
            ),
            for (var i = 0; i < entry.sets.length; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 38,
                      child: Text(
                        '${entry.sets[i].setNumber}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _weightLabel(entry.sets[i], units),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        entry.sets[i].reps == null
                            ? '—'
                            : '${entry.sets[i].reps}',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (i != entry.sets.length - 1)
                const Divider(height: 1, indent: 10, endIndent: 10),
            ],
            if (volume > 0) ...[
              const Divider(height: 20),
              _KeyValueRow(
                label: 'Weighted volume',
                value: formatVolume(volume, units),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ),
      Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    ],
  );
}

String _weightLabel(SetLog set, WeightUnit units) {
  final weight = set.weightKg;
  if (weight == null || weight <= 0) return 'Bodyweight';
  return formatWeight(weight, units);
}

bool _hasWeightedSets(ExerciseEntry entry) => entry.sets.any(isWeightedSet);

double _sessionVolume(ExerciseEntry entry) {
  var total = 0.0;
  for (final set in entry.sets) {
    if (isWeightedSet(set)) total += set.weightKg! * (set.reps ?? 0);
  }
  return total;
}

double? _maxOrNull(Iterable<double> values) {
  double? result;
  for (final value in values) {
    if (result == null || value > result) result = value;
  }
  return result;
}

int? _maxIntOrNull(Iterable<int> values) {
  int? result;
  for (final value in values) {
    if (result == null || value > result) result = value;
  }
  return result;
}

/// The single best set across [entries]: the most weight × reps among
/// weighted sets, the heavier one on a tie; with no weighted set, the one
/// with the most reps. Null when no set has reps.
SetLog? _bestSet(List<ExerciseEntry> entries) {
  SetLog? best;
  double score(SetLog s) => isWeightedSet(s) ? s.weightKg! * (s.reps ?? 0) : 0;
  final anyWeighted = entries.any((e) => e.sets.any(isWeightedSet));
  for (final e in entries) {
    for (final set in e.sets) {
      if ((set.reps ?? 0) <= 0) continue;
      if (anyWeighted && !isWeightedSet(set)) continue;
      if (best == null) {
        best = set;
        continue;
      }
      if (anyWeighted) {
        final a = score(set), b = score(best);
        if (a > b || (a == b && set.weightKg! > best.weightKg!)) best = set;
      } else if ((set.reps ?? 0) > (best.reps ?? 0)) {
        best = set;
      }
    }
  }
  return best;
}

/// "40 kg × 10", or "15 reps" for a bodyweight set.
String _setLabel(SetLog set, WeightUnit units) => isWeightedSet(set)
    ? '${formatWeight(set.weightKg!, units)} × ${set.reps}'
    : '${set.reps} reps';

/// The sessions one at a time, newest first: swipe sideways, or use the
/// arrows. Keeps the page short however many sessions there are.
class _SessionPager extends StatefulWidget {
  const _SessionPager({
    super.key,
    required this.entries,
    required this.today,
    required this.units,
  });

  final List<ExerciseEntry> entries;
  final DateTime today;
  final WeightUnit units;

  @override
  State<_SessionPager> createState() => _SessionPagerState();
}

class _SessionPagerState extends State<_SessionPager> {
  final ScrollController _scroll = ScrollController();
  double _width = 1;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final page = (_scroll.offset / _width).round();
      if (page != _page) setState(() => _page = page);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _go(int page) => _scroll.animateTo(
    page * _width,
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = widget.entries.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Session details',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('session-prev'),
              tooltip: 'Newer session',
              onPressed: _page > 0 ? () => _go(_page - 1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              '${_page + 1} of $count',
              key: const ValueKey('session-page'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            IconButton(
              key: const ValueKey('session-next'),
              tooltip: 'Older session',
              onPressed: _page < count - 1 ? () => _go(_page + 1) : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            _width = constraints.maxWidth;
            return SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              // Snaps a whole session at a time.
              physics: const PageScrollPhysics(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in widget.entries)
                    SizedBox(
                      width: constraints.maxWidth,
                      child: _SessionCard(
                        entry: entry,
                        today: widget.today,
                        units: widget.units,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        if (count > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Swipe for older sessions.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
