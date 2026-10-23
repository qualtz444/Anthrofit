import 'package:flutter/material.dart';

import '../../composition/composition_visuals.dart';
import '../../core/format.dart';
import '../../core/measurement_labels.dart';
import '../../core/units.dart';
import '../../models/models.dart';
import '../../state/measurement_scope.dart';
import '../../state/profile_scope.dart';
import '../composition/composition_record_screen.dart';
import '../scan/scan_result_screen.dart';
import '../widgets/empty_state.dart';
import '../../core/snack_bar_timing.dart';

/// Body Analysis: what the scans measured, on two tabs.
///
///   Proportions   Current analysis (the latest proportion scan) and the
///                 earlier ones
///   Composition   Current analysis (the latest body composition scan) and
///                 the earlier ones; each opens like its result screen
///
/// Every scan can be deleted from its card.
///
/// Proportions describe structure, which training is not expected to change,
/// so proportion scans are never compared or trended. Body composition
/// trends are in Progress, on the Body Weight tab.
class BodyAnalysisScreen extends StatefulWidget {
  const BodyAnalysisScreen({super.key, this.visualStore});

  /// Where body composition outlines and photos are kept. Swapped in tests.
  final CompositionVisualStore? visualStore;

  @override
  State<BodyAnalysisScreen> createState() => _BodyAnalysisScreenState();
}

class _BodyAnalysisScreenState extends State<BodyAnalysisScreen> {
  void _open(Measurement scan) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ScanResultScreen(measurement: scan),
    ),
  );

  Future<void> _confirmDelete(BuildContext context, Measurement scan) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete scan?'),
        content: Text(
          'Are you sure you want to delete the scan from '
          '${formatDate(scan.takenAt, today: DateTime.now())}? '
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
      await controller.delete(scan.id);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(duration: kSnackBarDuration, persist: false, content: Text('Scan deleted')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Body analysis'),
          bottom: const TabBar(
            tabs: [
              Tab(key: ValueKey('tab-proportions'), text: 'Proportions'),
              Tab(key: ValueKey('tab-composition'), text: 'Composition'),
            ],
          ),
        ),
        body: TabBarView(
          children: [_proportions(context), _composition(context)],
        ),
      ),
    );
  }

  /// The latest proportion scan, then the earlier ones.
  Widget _proportions(BuildContext context) {
    final theme = Theme.of(context);
    final scans = MeasurementScope.of(context).measurements; // newest first
    final today = DateTime.now();
    if (scans.isEmpty) {
      return const EmptyState(
        title: 'No scans yet.',
        message:
            'Use the scan button to measure your body proportions. Saved '
            'scans appear here.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Current analysis', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _ScanCard(
          scan: scans.first,
          today: today,
          onTap: () => _open(scans.first),
          onDelete: () => _confirmDelete(context, scans.first),
          showReadings: true,
        ),
        const SizedBox(height: 24),
        Text('Scan history', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (scans.length == 1)
          const _Note('No earlier scans. When you scan again, this one moves here.')
        else
          for (final scan in scans.skip(1))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ScanCard(
                scan: scan,
                today: today,
                onTap: () => _open(scan),
                onDelete: () => _confirmDelete(context, scan),
              ),
            ),
      ],
    );
  }

  void _openComposition(
    BuildContext context,
    CompositionRecord record,
    List<CompositionRecord> all,
  ) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CompositionRecordScreen(
        record: record,
        allRecords: all,
        visualStore: widget.visualStore,
      ),
    ),
  );

  /// The latest body composition scan, then the earlier ones. Read from the
  /// profile.
  Widget _composition(BuildContext context) {
    final theme = Theme.of(context);
    final profile = context
        .dependOnInheritedWidgetOfExactType<ProfileScope>()
        ?.notifier
        ?.profile;
    final all = profile?.compositionLog ?? const <CompositionRecord>[];
    final records = [...all]..sort((a, b) => b.takenAt.compareTo(a.takenAt));
    final today = DateTime.now();
    if (records.isEmpty) {
      return const EmptyState(
        title: 'No body composition scans yet.',
        message:
            'Use the scan button. Saved body composition scans appear here.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Current analysis', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _CompositionCard(
          key: ValueKey('composition-record-${records.first.id}'),
          record: records.first,
          today: today,
          current: true,
          onTap: () => _openComposition(context, records.first, all),
          onDelete: () => _deleteComposition(context, records.first),
        ),
        const SizedBox(height: 24),
        Text('Scan history', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (records.length == 1)
          const _Note('No earlier scans. When you scan again, this one moves here.')
        else
          for (final r in records.skip(1))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CompositionCard(
                key: ValueKey('composition-record-${r.id}'),
                record: r,
                today: today,
                onTap: () => _openComposition(context, r, all),
                onDelete: () => _deleteComposition(context, r),
              ),
            ),
        const SizedBox(height: 8),
        const _Note(
          'Estimates, not measurements. Used for your suggested goal and '
          'nutrition targets. Trends are in Progress, on the Body Weight tab.',
        ),
      ],
    );
  }

  /// Removes a body composition scan: its numbers from the profile and its
  /// outlines and photos from this phone.
  Future<void> _deleteComposition(
    BuildContext context,
    CompositionRecord record,
  ) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete body composition scan?'),
        content: Text(
          'The scan from ${formatDate(record.takenAt, today: DateTime.now())} '
          'and its saved outlines and photos will be removed. This cannot be '
          'undone.',
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
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final controller = context
        .getInheritedWidgetOfExactType<ProfileScope>()
        ?.notifier;
    final profile = controller?.profile;
    if (controller == null || profile == null) return;
    try {
      await controller.save(
        profile.copyWith(
          compositionLog: [
            for (final r in profile.compositionLog)
              if (r.id != record.id) r,
          ],
        ),
      );
      await (widget.visualStore ?? CompositionVisualStore()).delete(record.id);
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text('Body composition scan deleted')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't delete the scan. Try again.")),
      );
    }
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({
    required this.scan,
    required this.today,
    required this.onTap,
    this.onDelete,
    this.showReadings = false,
  });

  final Measurement scan;
  final DateTime today;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final bool showReadings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final readings = readingsFor(scan);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      formatDate(scan.takenAt, today: today),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    captureQualityLabel(scan.captureQuality),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: 'Delete scan',
                      onPressed: onDelete,
                    )
                  else
                    const Icon(Icons.chevron_right),
                ],
              ),
              Text(
                pluralize(readings.length, 'measurement'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (showReadings) ...[
                const SizedBox(height: 8),
                for (final r in readings)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(child: Text(r.name)),
                        Text(
                          r.valueLabel,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// One body composition scan: date, body fat with its range, fat-free mass.
class _CompositionCard extends StatelessWidget {
  const _CompositionCard({
    super.key,
    required this.record,
    required this.today,
    required this.onTap,
    required this.onDelete,
    this.current = false,
  });

  final CompositionRecord record;
  final DateTime today;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// The latest scan: shown larger.
  final bool current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = record;
    final unit = unitsOf(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.donut_large,
                color: theme.colorScheme.primary,
                size: current ? 36 : 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatDate(r.takenAt, today: today),
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Body fat ${r.bodyFatPct.toStringAsFixed(1)}%',
                      style: current
                          ? theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            )
                          : theme.textTheme.bodyLarge,
                    ),
                    Text(
                      '80% range ${r.bodyFatLow.toStringAsFixed(1)}–'
                      '${r.bodyFatHigh.toStringAsFixed(1)}% · fat-free mass '
                      '${formatWeight(r.fatFreeMassKg, unit)}',
                      style: muted,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Delete body composition scan',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
