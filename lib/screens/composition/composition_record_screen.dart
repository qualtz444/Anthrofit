import 'package:flutter/material.dart';

import '../../composition/composition_visuals.dart';
import '../../core/format.dart';
import '../../core/snack_bar_timing.dart';
import '../../models/models.dart';
import 'composition_compare_screen.dart';
import 'composition_result_screen.dart';

/// A saved body composition scan, reopened from Body analysis, laid out like
/// its result screen (see [CompositionRecordSummary]), with the way into
/// comparing it with another scan, and a way to delete its photos while
/// keeping the scan.
class CompositionRecordScreen extends StatefulWidget {
  const CompositionRecordScreen({
    super.key,
    required this.record,
    required this.allRecords,
    this.visualStore,
  });

  final CompositionRecord record;

  /// Every saved scan, for the comparison.
  final List<CompositionRecord> allRecords;

  final CompositionVisualStore? visualStore;

  @override
  State<CompositionRecordScreen> createState() =>
      _CompositionRecordScreenState();
}

class _CompositionRecordScreenState extends State<CompositionRecordScreen> {
  late final CompositionVisualStore _store =
      widget.visualStore ?? CompositionVisualStore();
  late Future<CompositionVisuals> _visuals = _load();

  Future<CompositionVisuals> _load() => _store
      .load(widget.record.id)
      .catchError((Object _) => CompositionVisuals.none);

  Future<void> _deletePhotos() async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete scan photos?'),
        content: const Text(
          'The front and side photos are removed from this phone. The '
          'results and outline stay. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('record-delete-photos-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _store.deletePhotos(widget.record.id);
      messenger.showSnackBar(
        const SnackBar(
          duration: kSnackBarDuration,
          persist: false,
          content: Text('Scan photos deleted'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          duration: kSnackBarDuration,
          persist: false,
          content: Text("Couldn't delete the photos. Try again."),
        ),
      );
    }
    if (mounted) {
      setState(() {
        _visuals = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final allRecords = widget.allRecords;
    final visualStore = widget.visualStore;
    return Scaffold(
      appBar: AppBar(
        title: Text(formatDate(record.takenAt, today: DateTime.now())),
      ),
      body: FutureBuilder<CompositionVisuals>(
        future: _visuals,
        builder: (context, snapshot) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // The numbers straight away; the outline once it has loaded.
            CompositionRecordSummary(
              record: record,
              visuals: snapshot.data ?? CompositionVisuals.none,
              visualsLoaded: snapshot.connectionState == ConnectionState.done,
            ),
            if (snapshot.data?.hasPhotos ?? false) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const ValueKey('record-delete-photos'),
                onPressed: _deletePhotos,
                icon: const Icon(Icons.hide_image_outlined),
                label: const Text('Delete scan photos'),
              ),
            ],
            if (allRecords.length >= 2) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const ValueKey('record-compare'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CompositionCompareScreen(
                      records: allRecords,
                      visualStore: visualStore,
                      focusId: record.id,
                    ),
                  ),
                ),
                icon: const Icon(Icons.compare_arrows),
                label: const Text('Compare with another scan'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
