import 'package:flutter/material.dart';

import '../../composition/composition_visuals.dart';
import '../../core/format.dart';
import '../../models/models.dart';
import 'composition_compare_screen.dart';
import 'composition_result_screen.dart';

/// A saved body composition scan, reopened from Body analysis, laid out like
/// its result screen (see [CompositionRecordSummary]), with the way into
/// comparing it with another scan.
class CompositionRecordScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final store = visualStore ?? CompositionVisualStore();
    return Scaffold(
      appBar: AppBar(
        title: Text(formatDate(record.takenAt, today: DateTime.now())),
      ),
      body: FutureBuilder<CompositionVisuals>(
        future: store
            .load(record.id)
            .catchError((Object _) => CompositionVisuals.none),
        builder: (context, snapshot) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // The numbers straight away; the outline once it has loaded.
            CompositionRecordSummary(
              record: record,
              visuals: snapshot.data ?? CompositionVisuals.none,
              visualsLoaded: snapshot.connectionState == ConnectionState.done,
            ),
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
