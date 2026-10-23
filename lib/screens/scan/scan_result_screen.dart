import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/measurement_labels.dart';
import '../../models/measurement.dart';
import '../../state/measurement_scope.dart';
import '../composition/body_composition_screen.dart';
import '../widgets/empty_state.dart';
import 'personalize_program_screen.dart';
import '../../core/snack_bar_timing.dart';

/// What one finished scan measured.
///
/// Read-only, and shows exactly what the pipeline reported: the ratios, how
/// steady each one was, and how many frames it used. Nothing is recalculated
/// here and nothing is interpreted: there is no "good" or "bad" proportion,
/// only the numbers and how repeatable they were.
///
/// Every value is unitless. There is no metric calibration in the pipeline,
/// so none of these are lengths in centimetres.
class ScanResultScreen extends StatelessWidget {
  const ScanResultScreen({
    super.key,
    required this.measurement,
    this.saved = true,
  });

  final Measurement measurement;

  /// False when the scan could not be saved, so the screen can say so rather
  /// than implying it was kept.
  final bool saved;

  Future<void> _confirmDelete(BuildContext context) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete scan?'),
        content: Text(
          'Are you sure you want to delete the scan from '
          '${formatDate(measurement.takenAt, today: DateTime.now())}? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final controller = MeasurementScope.of(context, listen: false);
      await controller.delete(measurement.id);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(duration: kSnackBarDuration, persist: false, content: Text('Scan deleted')));
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan result'),
        actions: [
          if (saved)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete scan',
              onPressed: () => _confirmDelete(context),
            ),
        ],
      ),
      body: ScanResultBody(measurement: measurement, saved: saved),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // An explicit choice: a scan never builds a program on its own.
              // Offered only when the scan measured something.
              if (!measurement.isEmpty) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            PersonalizeProgramScreen(measurement: measurement),
                      ),
                    ),
                    child: const Text('Personalize My Program'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              // Offered as a next step, not a second choice up front: most
              // people came here for the proportion scan, so this is easy
              // to skip with Done rather than something to decide between
              // first.
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BodyCompositionScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.accessibility_new),
                  label: const Text('Next: check body composition'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The proportions and capture-quality content, with no screen chrome of its
/// own, so the guided scan flow's combined results screen can show it next
/// to the composition section.
class ScanResultBody extends StatelessWidget {
  const ScanResultBody({
    super.key,
    required this.measurement,
    this.saved = true,
    this.scrollable = true,
  });

  final Measurement measurement;

  /// False lays the content out in a plain column, for a screen that puts it
  /// inside its own scrolling list (the guided scan's combined results).
  final bool scrollable;

  /// False when the scan could not be saved, so this says so rather than
  /// implying it was kept.
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final readings = readingsFor(measurement);
    final skeleton = readings.where((r) => !r.fromSilhouette).toList();
    final outline = readings.where((r) => r.fromSilhouette).toList();
    final unknown = unknownRatioKeys(measurement);

    if (readings.isEmpty && unknown.isEmpty) {
      return const EmptyState(
        title: 'This scan produced no measurements.',
        message: 'Try scanning again with your whole body in frame.',
      );
    }
    final children = <Widget>[
      _CaptureSummary(measurement: measurement),
      if (!saved)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            "This scan wasn't saved, so it will be gone when you "
            'close this screen.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      const SizedBox(height: 24),
      if (skeleton.isNotEmpty) ...[
        Text('Body proportions', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Each number compares two parts of your body, so it has no '
          'unit. A scan does not measure you in centimetres.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        for (final reading in skeleton) _RatioCard(reading: reading),
        const SizedBox(height: 16),
      ],
      if (outline.isNotEmpty) ...[
        Text('From the body outline', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Measured from your silhouette rather than your joints, so '
          'loose clothing changes these more.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        for (final reading in outline) _RatioCard(reading: reading),
        const SizedBox(height: 16),
      ],
      if (unknown.isNotEmpty)
        Text(
          'Not shown: ${pluralize(unknown.length, 'measurement')} '
          'this version of the app has no description for.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
    ];
    if (!scrollable) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return ListView(padding: const EdgeInsets.all(16), children: children);
  }
}

/// How the capture itself went: when, how many frames, and how steady.
class _CaptureSummary extends StatelessWidget {
  const _CaptureSummary({required this.measurement});

  final Measurement measurement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quality = measurement.captureQuality;
    final note = captureQualityNote(quality);
    final isUnsteady = quality == 'unstable';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatDate(measurement.takenAt, today: DateTime.now()),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  isUnsteady ? Icons.info_outline : Icons.check_circle_outline,
                  size: 20,
                  color: isUnsteady
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  captureQualityLabel(quality),
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            if (note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  note,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isUnsteady
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              '${measurement.framesUsed} of ${measurement.framesTotal} frames '
              'were usable · widest spread '
              '${measurement.worstIqrPct.toStringAsFixed(1)}%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One ratio: its value, what it compares, and how much it moved.
class _RatioCard extends StatelessWidget {
  const _RatioCard({required this.reading});

  final RatioReading reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spread = reading.spreadPct;

    return Card(
      key: ValueKey('ratio-${reading.key}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    reading.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  reading.valueLabel,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              reading.note,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (spread != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Varied by ${spread.toStringAsFixed(1)}% across frames',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
