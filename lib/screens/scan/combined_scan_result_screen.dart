import 'package:flutter/material.dart';

import '../../composition/composition_visuals.dart';
import '../body_analysis/body_analysis_screen.dart';
import '../composition/composition_result_screen.dart';
import '../nutrition/nutrition_targets_screen.dart';
import 'guided_scan_screen.dart';
import 'personalize_program_screen.dart';
import 'scan_change_card.dart';
import 'scan_result_screen.dart';

/// The one results screen at the end of a guided scan: body proportions and
/// body composition in two sections, then three next steps.
///
/// Both sections reuse the standalone result screens' content. Proportion
/// and composition history stay separate; they are only shown together.
class CombinedScanResultScreen extends StatefulWidget {
  const CombinedScanResultScreen({
    super.key,
    required this.session,
    this.visualStore,
  });

  final GuidedScanFinished session;
  final CompositionVisualStore? visualStore;

  @override
  State<CombinedScanResultScreen> createState() =>
      _CombinedScanResultScreenState();
}

class _CombinedScanResultScreenState extends State<CombinedScanResultScreen> {
  late bool _saved = widget.session.saved;
  bool _saving = false;

  /// Same ids as the first attempt, so a retry replaces instead of adding.
  Future<void> _retrySave() async {
    if (_saving || _saved) return;
    setState(() => _saving = true);
    final s = widget.session;
    final ok = await saveGuidedScan(
      context,
      measurement: s.measurement,
      composition: s.composition,
      compositionId: s.compositionId,
      takenAt: s.takenAt,
      visualStore: widget.visualStore,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = ok;
    });
  }

  void _open(Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.session;

    return Scaffold(
      appBar: AppBar(title: const Text('Scan results')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_saved)
            Card(
              key: const ValueKey('guided-not-saved'),
              margin: const EdgeInsets.only(bottom: 16),
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "These results weren't saved. Nothing from this scan "
                      'was added to your history.',
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    TextButton(
                      onPressed: _saving ? null : _retrySave,
                      child: const Text('Try saving again'),
                    ),
                  ],
                ),
              ),
            ),
          // What changed since the last scan, once this one is saved.
          if (_saved)
            ScanChangeCard(
              currentId: s.compositionId,
              visualStore: widget.visualStore,
            ),
          Text(
            'Body proportions',
            key: const ValueKey('section-proportions'),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          ScanResultBody(
            measurement: s.measurement,
            // The card above already says when nothing was saved.
            scrollable: false,
          ),
          const Divider(height: 32),
          Text(
            'Body composition',
            key: const ValueKey('section-composition'),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Estimates from your outline, height, weight, age and sex, not '
            'direct measurements.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          CompositionResultBody(
            result: s.composition.result,
            input: s.composition.input,
            visuals: s.composition.visuals,
            saved: _saved,
            scrollable: false,
            takenAt: s.takenAt,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Opens the Personalized Plan (training and nutrition).
              // Nothing is saved, and the active program is not replaced,
              // until the user confirms on that screen.
              FilledButton.icon(
                key: const ValueKey('guided-next-program'),
                onPressed: () =>
                    _open(PersonalizeProgramScreen(measurement: s.measurement)),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Generate My Program'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('guided-next-nutrition'),
                onPressed: () => _open(const NutritionTargetsScreen()),
                icon: const Icon(Icons.restaurant_outlined),
                label: const Text('View nutrition plan'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('guided-next-analysis'),
                onPressed: () =>
                    _open(BodyAnalysisScreen(visualStore: widget.visualStore)),
                icon: const Icon(Icons.insights_outlined),
                label: const Text('Go to body analysis'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
