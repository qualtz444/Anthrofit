import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../composition/body_composition.dart';
import '../../composition/composition_visuals.dart';
import '../../core/format.dart';
import '../../core/units.dart';
import '../../models/models.dart';
import '../../nutrition/body_fat_category.dart';
import '../../state/measurement_scope.dart';
import '../../state/profile_scope.dart';
import '../../state/program_scope.dart';
import '../progress/share_progress_sheet.dart';
import '../scan/body_size_check.dart';
import 'body_composition_screen.dart';
import '../scan/personalize_program_screen.dart';
import '../scan/scan_change_card.dart';
import 'composition_visuals_view.dart';
import '../../core/snack_bar_timing.dart';

/// Shows one body-composition estimate with its 80% range, the goal it
/// suggests, and the way into building a plan from it.
///
/// Never shown in Progress. The estimate is saved to the profile's
/// composition history by the capture screen before this opens.
class CompositionResultScreen extends StatelessWidget {
  const CompositionResultScreen({
    super.key,
    required this.result,
    required this.input,
    this.saved = false,
    this.visuals = CompositionVisuals.none,
    this.takenAt,
    this.recordId,
    this.visualStore,
  });

  final BodyCompositionResult result;
  final CompositionInput input;

  /// The saved record's id. When set, the screen opens with what changed
  /// since the previous scan. Null when the estimate was not saved.
  final String? recordId;
  final CompositionVisualStore? visualStore;

  /// When the scan was taken. Null means just now.
  final DateTime? takenAt;

  /// This scan's outlines, and photos if the user chose to keep them.
  final CompositionVisuals visuals;

  /// Whether the capture screen managed to save it.
  final bool saved;

  /// Saves [goal] as the profile's goal if it changed, then builds the plan:
  /// the goal from this estimate, the exercises from the latest proportion
  /// scan if there is one. The diet targets on the preview read the saved
  /// estimate.
  Future<void> _buildPlan(BuildContext context, TrainingGoal goal) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = context
        .getInheritedWidgetOfExactType<ProfileScope>()
        ?.notifier;
    final profile = controller?.profile;
    final latestScan = context
        .getInheritedWidgetOfExactType<MeasurementScope>()
        ?.notifier
        ?.latest;

    if (controller != null && profile != null && profile.goal != goal) {
      try {
        await controller.save(profile.copyWith(goal: goal));
      } catch (_) {
        messenger.showSnackBar(
          const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't save your goal. Try again.")),
        );
        return;
      }
    }
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PersonalizeProgramScreen(measurement: latestScan, goal: goal),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Body composition')),
      body: recordId == null
          ? CompositionResultBody(
              result: result,
              input: input,
              saved: saved,
              visuals: visuals,
              takenAt: takenAt,
              onBuild: (goal) => _buildPlan(context, goal),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ScanChangeCard(currentId: recordId!, visualStore: visualStore),
                CompositionResultBody(
                  result: result,
                  input: input,
                  saved: saved,
                  visuals: visuals,
                  takenAt: takenAt,
                  scrollable: false,
                  onBuild: (goal) => _buildPlan(context, goal),
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
              // Workout, scan, then flex: the scan ends by offering to share
              // it. Only a saved scan can be shared (its photos are kept with
              // it); Back or Done leaves without sharing.
              if (_savedRecord(context) != null)
                FilledButton.icon(
                  key: const ValueKey('share-scan-with-friends'),
                  onPressed: () => _share(context),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share with your friends'),
                ),
              if (_savedRecord(context) != null) const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('rescan'),
                onPressed: () => _rescan(context),
                icon: const Icon(Icons.refresh),
                label: const Text('Rescan'),
              ),
              const SizedBox(height: 4),
              if (_savedRecord(context) != null)
                TextButton(
                  key: const ValueKey('scan-done'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                )
              else
                FilledButton(
                  key: const ValueKey('scan-done'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Scans again. The new capture replaces this result, so Back still goes
  /// to wherever the scan was started from (the workout summary after a
  /// workout), not to this old result.
  Future<void> _rescan(BuildContext context) async {
    final navigator = Navigator.of(context);
    if (!await confirmHeightAndWeight(context) || !context.mounted) return;
    await navigator.pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const BodyCompositionScreen()),
    );
  }

  /// This scan's saved history record, or null when it was not saved.
  CompositionRecord? _savedRecord(BuildContext context) {
    final id = recordId;
    if (id == null) return null;
    final profile = context
        .getInheritedWidgetOfExactType<ProfileScope>()
        ?.notifier
        ?.profile;
    if (profile == null) return null;
    for (final r in profile.compositionLog) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Opens the share sheet for this scan: its original colour photos or a
  /// selfie, with or without the scan result.
  Future<void> _share(BuildContext context) async {
    final record = _savedRecord(context);
    if (record == null) return;
    await showShareProgressSheet(
      context,
      scans: [record],
      visualStore: visualStore,
    );
  }
}

/// The estimate itself: when it was taken and how sure it is, body fat as
/// a ring, the three masses, the outline with its circumferences, and a
/// breakdown with every range. Shared by [CompositionResultScreen] and the
/// guided scan's combined results.
class CompositionResultBody extends StatelessWidget {
  const CompositionResultBody({
    super.key,
    required this.result,
    required this.input,
    this.saved = false,
    this.visuals = CompositionVisuals.none,
    this.onBuild,
    this.scrollable = true,
    this.takenAt,
  });

  final BodyCompositionResult result;
  final CompositionInput input;
  final bool saved;
  final CompositionVisuals visuals;

  /// Builds a plan with the chosen goal. Null shows the suggested goal
  /// without its buttons (the guided flow has its own next steps).
  final ValueChanged<TrainingGoal>? onBuild;

  /// False lays the content out in a plain column inside a parent list.
  final bool scrollable;

  /// When the scan was taken. Null means just now.
  final DateTime? takenAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weightUnit = unitsOf(context);
    final bf = result.bodyFatPct;
    final alm = result.appendicularLeanKg;
    final taken = takenAt ?? DateTime.now();
    final category = bodyFatCategory(bf.value, isMale: input.isMale);

    String mass(double kg) => formatWeight(kg, weightUnit);
    String pct(double v) => '${v.toStringAsFixed(1)}%';

    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final children = <Widget>[
      // ---- When, and how sure ----
      Row(
        children: [
          Icon(Icons.event_outlined, size: 18, color: muted?.color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${formatDate(taken, today: DateTime.now())} · '
              '${_timeOf(taken)}',
              key: const ValueKey('composition-date'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_outlined, size: 18, color: muted?.color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Confidence: 80% range ${pct(bf.low)} to ${pct(bf.high)}.',
              key: const ValueKey('composition-confidence'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),

      // ---- The headline number ----
      Center(
        child: _BodyFatRing(
          value: bf.value,
          low: bf.low,
          high: bf.high,
        ),
      ),
      const SizedBox(height: 8),
      Center(
        child: Text(
          'Body fat range: ${category.label}',
          style: theme.textTheme.titleSmall,
        ),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'An estimate, not a measurement, made from your body outline, '
                'height, weight, age and sex.',
                key: const ValueKey('composition-disclaimer'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),

      // ---- Three masses ----
      Row(
        children: [
          Expanded(
            child: _MassTile(
              icon: Icons.water_drop_outlined,
              label: 'Fat mass',
              value: mass(result.fatMassKg),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MassTile(
              icon: Icons.fitness_center,
              label: 'Fat-free mass',
              value: mass(result.fatFreeMassKg),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MassTile(
              icon: Icons.accessibility_new,
              label: 'Arm & leg lean mass',
              value: mass(alm.value),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),

      // ---- The outline, and the circumferences read from it ----
      Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: CompositionVisualsView(visuals: visuals),
            ),
            _CircumferenceSection(
              measurements: result.measurements,
              waistSpreadCm: result.waistSpreadCm,
              frameCount: result.frameCount,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),

      // ---- Every number, with its range ----
      Text('Body composition breakdown', style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      Card(
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            _BreakdownRow(
              icon: Icons.donut_large,
              label: 'Body fat',
              value: pct(bf.value),
              detail:
                  '80% range: ${pct(bf.low)} to ${pct(bf.high)} · typical '
                  'error ±${bf.mae.toStringAsFixed(1)} points',
            ),
            const Divider(height: 1),
            _BreakdownRow(
              icon: Icons.water_drop_outlined,
              label: 'Fat mass',
              value: mass(result.fatMassKg),
              detail: 'Your weight × the body fat estimate',
            ),
            const Divider(height: 1),
            _BreakdownRow(
              icon: Icons.fitness_center,
              label: 'Fat-free mass',
              value: mass(result.fatFreeMassKg),
              detail: 'Your weight minus fat mass',
            ),
            const Divider(height: 1),
            _BreakdownRow(
              icon: Icons.accessibility_new,
              label: 'Arm & leg lean mass',
              value: mass(alm.value),
              detail:
                  '80% range: ${mass(alm.low)} to ${mass(alm.high)} · '
                  'typical error ±${mass(alm.mae)}',
            ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Fat mass and fat-free mass are worked out from the body fat '
        'estimate, so they share its uncertainty.',
        style: muted,
      ),
      const SizedBox(height: 16),
      _SuggestedGoal(result: result, input: input, onBuild: onBuild),
      if (!input.isInTrainingRange) ...[
        const SizedBox(height: 12),
        Text(
          'This estimate is made for ages '
          '${CompositionInput.minAge}-${CompositionInput.maxAge}, so treat it '
          'with extra caution.',
          key: const ValueKey('composition-age-warning'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ],
      const SizedBox(height: 16),
      Card(
        margin: EdgeInsets.zero,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'For fitness use only. Not a medical device or a diagnosis. It may '
            'be less accurate for people of Asian descent, and loose clothing '
            'makes results read higher.'
            '${saved ? ' Saved to your body composition history.' : ''}',
            style: theme.textTheme.bodySmall,
          ),
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

/// A saved scan, laid out like its result screen: the date, the 80% range,
/// the body fat ring, the three masses, the outline with its circumferences
/// and the breakdown.
///
/// Only what the history record keeps is shown. A record does not store the
/// models' test-set coverage, typical error, the arm and leg lean mass range,
/// or the age and sex used, so the coverage sentence, the error figures, the
/// suggested goal and the age warning of the result screen are left out
/// rather than filled in.
class CompositionRecordSummary extends StatelessWidget {
  const CompositionRecordSummary({
    super.key,
    required this.record,
    this.visuals = CompositionVisuals.none,
    this.visualsLoaded = true,
  });

  final CompositionRecord record;
  final CompositionVisuals visuals;
  final bool visualsLoaded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weightUnit = unitsOf(context);
    final r = record;
    String mass(double kg) => formatWeight(kg, weightUnit);
    String pct(double v) => '${v.toStringAsFixed(1)}%';
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.event_outlined, size: 18, color: muted?.color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${formatDate(r.takenAt, today: DateTime.now())} · '
                '${_timeOf(r.takenAt)}',
                key: const ValueKey('summary-date'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(Icons.verified_outlined, size: 18, color: muted?.color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Confidence: 80% range ${pct(r.bodyFatLow)} to '
                '${pct(r.bodyFatHigh)}',
                key: const ValueKey('summary-confidence'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Center(
          child: _BodyFatRing(
            value: r.bodyFatPct,
            low: r.bodyFatLow,
            high: r.bodyFatHigh,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'An estimate, not a measurement, made from your body '
                  'outline, height, weight, age and sex.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _MassTile(
                icon: Icons.water_drop_outlined,
                label: 'Fat mass',
                value: mass(r.fatMassKg),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MassTile(
                icon: Icons.fitness_center,
                label: 'Fat-free mass',
                value: mass(r.fatFreeMassKg),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MassTile(
                icon: Icons.accessibility_new,
                label: 'Arm & leg lean mass',
                value: mass(r.leanLimbKg),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (visualsLoaded)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: CompositionVisualsView(visuals: visuals),
                ),
              _CircumferenceSection(
                measurements: SilhouetteMeasurements(
                  waist: r.waistCm,
                  bicep: r.upperArmCm,
                  hip: r.hipCm,
                  chest: r.chestCm,
                  thigh: r.thighCm,
                ),
                waistSpreadCm: null,
                frameCount: r.frameCount,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Body composition breakdown', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              _BreakdownRow(
                icon: Icons.donut_large,
                label: 'Body fat',
                value: pct(r.bodyFatPct),
                detail:
                    '80% range: ${pct(r.bodyFatLow)} to ${pct(r.bodyFatHigh)}',
              ),
              const Divider(height: 1),
              _BreakdownRow(
                icon: Icons.water_drop_outlined,
                label: 'Fat mass',
                value: mass(r.fatMassKg),
                detail: 'Your weight × the body fat estimate',
              ),
              const Divider(height: 1),
              _BreakdownRow(
                icon: Icons.fitness_center,
                label: 'Fat-free mass',
                value: mass(r.fatFreeMassKg),
                detail: 'Your weight minus fat mass',
              ),
              const Divider(height: 1),
              _BreakdownRow(
                icon: Icons.accessibility_new,
                label: 'Arm & leg lean mass',
                value: mass(r.leanLimbKg),
                detail: 'Estimated from your measurements and profile',
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Worked out with a weight of ${mass(r.weightKg)}. Fat mass and '
          'fat-free mass come from the body fat estimate, so they share its '
          'uncertainty.',
          style: muted,
        ),
      ],
    );
  }
}

/// Body fat as a share of the whole ring (the ring is 100% of body weight),
/// with the 80% range as a lighter band behind it.
class _BodyFatRing extends StatelessWidget {
  const _BodyFatRing({
    required this.value,
    required this.low,
    required this.high,
  });

  final double value;
  final double low;
  final double high;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      key: const ValueKey('body-fat-ring'),
      width: 180,
      height: 180,
      child: CustomPaint(
        painter: _RingPainter(
          value: value / 100,
          low: low / 100,
          high: high / 100,
          track: theme.colorScheme.surfaceContainerHighest,
          band: theme.colorScheme.primary.withValues(alpha: 0.3),
          fill: theme.colorScheme.primary,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${value.toStringAsFixed(1)}%',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'estimated body fat',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.low,
    required this.high,
    required this.track,
    required this.band,
    required this.fill,
  });

  final double value;
  final double low;
  final double high;
  final Color track;
  final Color band;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    const start = -math.pi / 2; // 12 o'clock
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    Paint p(Color c, {double width = stroke}) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.butt;

    canvas.drawArc(rect, 0, math.pi * 2, false, p(track));
    final lo = low.clamp(0.0, 1.0), hi = high.clamp(0.0, 1.0);
    if (hi > lo) {
      canvas.drawArc(
        rect,
        start + lo * math.pi * 2,
        (hi - lo) * math.pi * 2,
        false,
        p(band, width: stroke + 6),
      );
    }
    canvas.drawArc(
      rect,
      start,
      value.clamp(0.0, 1.0) * math.pi * 2,
      false,
      p(fill),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.low != low || old.high != high;
}

/// One of the three masses, as a small tile with an icon.
class _MassTile extends StatelessWidget {
  const _MassTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              label,
              maxLines: 2,
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

/// The circumferences read from the outline, folded away by default, in
/// centimetres or inches.
class _CircumferenceSection extends StatefulWidget {
  const _CircumferenceSection({
    required this.measurements,
    required this.waistSpreadCm,
    required this.frameCount,
  });

  final SilhouetteMeasurements measurements;

  /// Null for a saved scan: its history record does not keep it.
  final double? waistSpreadCm;
  final int frameCount;

  @override
  State<_CircumferenceSection> createState() => _CircumferenceSectionState();
}

class _CircumferenceSectionState extends State<_CircumferenceSection> {
  bool? _metric; // null: follow the profile

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metric = _metric ?? heightUnitOf(context).isMetric;
    final m = widget.measurements;
    String length(double cm) => metric
        ? '${cm.toStringAsFixed(1)} cm'
        : '${inchesFromCm(cm).toStringAsFixed(1)} in';
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final spreadCm = widget.waistSpreadCm;
    final spread = spreadCm == null
        ? '.'
        : '; the waist varied by ${length(spreadCm)} between them.';

    return ExpansionTile(
      key: const ValueKey('circumferences'),
      shape: const Border(),
      leading: const Icon(Icons.straighten),
      title: const Text('Estimated circumferences'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: SegmentedButton<bool>(
            key: const ValueKey('circumference-unit'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: true, label: Text('cm')),
              ButtonSegment(value: false, label: Text('in')),
            ],
            selected: {metric},
            onSelectionChanged: (s) => setState(() => _metric = s.first),
          ),
        ),
        const SizedBox(height: 8),
        _Row('Waist', length(m.waist)),
        _Row('Chest', length(m.chest)),
        _Row('Hip', length(m.hip)),
        _Row('Thigh', length(m.thigh)),
        _Row('Upper arm', length(m.bicep)),
        const SizedBox(height: 6),
        Text(
          'Read from your silhouette, not measured with a tape. '
          '${pluralize(widget.frameCount, 'front and side pair')} combined'
          '$spread',
          style: muted,
        ),
      ],
    );
  }
}

/// One line of the breakdown: icon, name, value, and how sure it is.
class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(label),
      subtitle: Text(detail),
      trailing: Text(
        value,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The ACE category, the goal it suggests, and the buttons to build a plan.
class _SuggestedGoal extends StatelessWidget {
  const _SuggestedGoal({
    required this.result,
    required this.input,
    required this.onBuild,
  });

  final BodyCompositionResult result;
  final CompositionInput input;
  final ValueChanged<TrainingGoal>? onBuild;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bf = result.bodyFatPct;
    final category = bodyFatCategory(bf.value, isMale: input.isMale);
    final suggested = suggestedGoalFor(category);
    final current = context
        .dependOnInheritedWidgetOfExactType<ProfileScope>()
        ?.notifier
        ?.profile
        ?.goal;
    // A new estimate never changes the active program by itself, so say
    // when that program is built for a different goal than this suggests.
    final active = context
        .dependOnInheritedWidgetOfExactType<ProgramScope>()
        ?.notifier
        ?.activeProgram;
    final activeGoal = active?.goal;
    // The 80% range can reach into another category; say so rather than
    // present the category as certain.
    final spansCategories =
        bodyFatCategory(bf.low, isMale: input.isMale) !=
            bodyFatCategory(bf.high, isMale: input.isMale);

    return Card(
      key: const ValueKey('suggested-goal'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Suggested goal',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              suggested.label,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your estimate is in the "${category.label}" body fat range.'
              '${spansCategories ? ' It is close to the next range, so treat '
                  'this as a rough guide.' : ''}',
              style: theme.textTheme.bodyMedium,
            ),
            if (activeGoal case final goal? when goal != suggested) ...[
              const SizedBox(height: 8),
              Container(
                key: const ValueKey('program-goal-differs'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Your active program, ${active?.name}, is still set for '
                  '${goal.label}. It does not change by itself. '
                  '${onBuild != null ? 'Build a plan with this goal to make '
                            'a new one; your current program stays until you '
                            'save it.' : 'To train for ${suggested.label}, '
                            'change your goal in your profile, then '
                            'regenerate your program.'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
            if (onBuild case final onBuild?) ...[
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('build-plan-suggested'),
                onPressed: () => onBuild(suggested),
                child: const Text('Build my plan with this goal'),
              ),
              if (current != null && current != suggested) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const ValueKey('build-plan-current'),
                  onPressed: () => onBuild(current),
                  child: Text('Keep my goal: ${current.label}'),
                ),
              ],
            ] else if (current != null && current != suggested) ...[
              const SizedBox(height: 8),
              Text(
                'Your profile goal is still ${current.label}. Change it in '
                'your profile if you want to train for this one.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              onBuild != null
                  ? 'Your training goal and diet targets are built from this '
                        'estimate. The exercises come from your latest body '
                        'proportion scan, if you have one.'
                  : 'Your nutrition targets use this estimate. Your training '
                        'program uses your profile goal and your body '
                        'proportion scan.',
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

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

/// "5:53 PM"
String _timeOf(DateTime d) {
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${d.hour < 12 ? 'AM' : 'PM'}';
}
