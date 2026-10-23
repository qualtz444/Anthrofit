import 'package:flutter/material.dart';

import '../../composition/composition_visuals.dart';
import '../../core/format.dart';
import '../../core/units.dart';
import '../../models/models.dart';
import '../../state/profile_scope.dart';
import '../composition/composition_compare_screen.dart';
import '../progress/progress_screen.dart';

/// The scan just taken next to the one before it: body fat, fat-free mass
/// and weight, with a way into the full comparison and into Progress.
///
/// Closes the loop scan → program → workouts → scan → progress. Read from
/// the saved composition history, so it only shows saved scans. Nothing new
/// is estimated: the numbers are the two saved estimates.
class ScanChangeCard extends StatelessWidget {
  const ScanChangeCard({
    super.key,
    required this.currentId,
    this.visualStore,
  });

  /// The scan just taken (its composition record id).
  final String currentId;
  final CompositionVisualStore? visualStore;

  /// [current] and the latest record before it, or null for the earlier one
  /// when [current] is the first. Null overall when [currentId] is not saved.
  static ({CompositionRecord current, CompositionRecord? previous})? pairFor(
    List<CompositionRecord> log,
    String currentId,
  ) {
    CompositionRecord? current;
    for (final r in log) {
      if (r.id == currentId) current = r;
    }
    if (current == null) return null;
    CompositionRecord? previous;
    for (final r in log) {
      if (r.id == current.id || !r.takenAt.isBefore(current.takenAt)) continue;
      if (previous == null || r.takenAt.isAfter(previous.takenAt)) previous = r;
    }
    return (current: current, previous: previous);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final units = unitsOf(context);
    final log =
        ProfileScope.of(context).profile?.compositionLog ??
        const <CompositionRecord>[];
    final pair = pairFor(log, currentId);
    if (pair == null) return const SizedBox.shrink();
    final current = pair.current;
    final previous = pair.previous;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    void open(Widget screen) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));

    final progressButton = OutlinedButton.icon(
      key: const ValueKey('scan-see-progress'),
      onPressed: () => open(const ProgressScreen(initialTab: 2)),
      icon: const Icon(Icons.trending_up),
      label: const Text('See your progress'),
    );

    if (previous == null) {
      return Card(
        key: const ValueKey('scan-change-first'),
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Your first scan', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'This is your starting point. Train with your program, then '
                'scan again to see what changed.',
              ),
              const SizedBox(height: 12),
              progressButton,
            ],
          ),
        ),
      );
    }

    final today = DateTime.now();
    final days = DateTime(
      current.takenAt.year,
      current.takenAt.month,
      current.takenAt.day,
    ).difference(
      DateTime(
        previous.takenAt.year,
        previous.takenAt.month,
        previous.takenAt.day,
      ),
    ).inDays;
    final fatChange = current.bodyFatPct - previous.bodyFatPct;
    // The same reading the comparison screen uses: when the two 80% ranges
    // overlap, the estimate cannot reliably tell the two apart.
    final overlap =
        current.bodyFatLow <= previous.bodyFatHigh &&
        previous.bodyFatLow <= current.bodyFatHigh;

    String signed(double v, String Function(double) f) =>
        v == 0 ? 'no change' : '${v > 0 ? '+' : '−'}${f(v.abs())}';
    String pct(double v) => '${v.toStringAsFixed(1)}%';

    Widget row(String label, String before, String after, String change) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(child: Text(label)),
              Text('$before → $after', style: theme.textTheme.bodyMedium),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: Text(
                  change,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );

    return Card(
      key: const ValueKey('scan-change'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Since your last scan', style: theme.textTheme.titleMedium),
            Text(
              '${formatDate(previous.takenAt, today: today)} · '
              '${days == 0 ? 'same day' : '$days ${days == 1 ? 'day' : 'days'} ago'}',
              style: muted,
            ),
            const SizedBox(height: 8),
            row(
              'Body fat',
              pct(previous.bodyFatPct),
              pct(current.bodyFatPct),
              signed(fatChange, (v) => '${v.toStringAsFixed(1)} pts'),
            ),
            row(
              'Fat-free mass',
              formatWeight(previous.fatFreeMassKg, units),
              formatWeight(current.fatFreeMassKg, units),
              signed(
                current.fatFreeMassKg - previous.fatFreeMassKg,
                (v) => formatWeight(v, units),
              ),
            ),
            row(
              'Weight',
              formatWeight(previous.weightKg, units),
              formatWeight(current.weightKg, units),
              signed(
                current.weightKg - previous.weightKg,
                (v) => formatWeight(v, units),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              overlap
                  ? 'The two body fat estimates overlap within their 80% '
                        'ranges, so this may not be a real change.'
                  : 'The two body fat estimates do not overlap within their 80% '
                        'ranges, but they are still camera estimates.',
              key: const ValueKey('scan-change-note'),
              style: muted,
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: const ValueKey('scan-compare-last'),
              onPressed: () => open(
                CompositionCompareScreen(
                  records: log,
                  focusId: current.id,
                  visualStore: visualStore,
                ),
              ),
              icon: const Icon(Icons.compare_arrows),
              label: const Text('Compare in detail'),
            ),
            const SizedBox(height: 8),
            progressButton,
          ],
        ),
      ),
    );
  }
}
