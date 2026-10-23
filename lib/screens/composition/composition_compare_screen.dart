import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../composition/composition_visuals.dart';
import '../../composition/silhouette_features.dart';
import '../../core/format.dart';
import '../../core/units.dart';
import '../../models/models.dart';
import '../../state/profile_scope.dart';
import '../progress/simple_line_chart.dart';
import 'outline_overlay.dart';

/// Two body composition scans side by side: the numbers, a trend for each
/// part across every scan, the outlines laid over each other, and the photos
/// if both scans kept them.
///
/// Every difference is shown with the reminder that these are estimates:
/// when the two 80% ranges overlap, the change is within what the estimate
/// cannot reliably tell apart.
class CompositionCompareScreen extends StatefulWidget {
  const CompositionCompareScreen({
    super.key,
    required this.records,
    this.visualStore,
    this.focusId,
  });

  /// Opens on this scan, compared with the one before it (or after it, if
  /// it is the first). Null opens on the two latest.

  /// At least two, any order.
  final List<CompositionRecord> records;

  final CompositionVisualStore? visualStore;
  final String? focusId;

  @override
  State<CompositionCompareScreen> createState() =>
      _CompositionCompareScreenState();
}

class _CompositionCompareScreenState extends State<CompositionCompareScreen> {
  late final CompositionVisualStore _store =
      widget.visualStore ?? CompositionVisualStore();

  late List<CompositionRecord> _byDate;
  late String _earlierId;
  late String _laterId;
  bool _showPhotos = false;
  _Part _part = _Part.bodyFat;

  /// Loaded once per record id.
  final Map<String, Future<CompositionVisuals>> _visuals = {};

  @override
  void initState() {
    super.initState();
    _byDate = [...widget.records]
      ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
    final focus = _byDate.indexWhere((r) => r.id == widget.focusId);
    if (focus > 0) {
      _laterId = _byDate[focus].id;
      _earlierId = _byDate[focus - 1].id;
    } else if (focus == 0) {
      _earlierId = _byDate[0].id;
      _laterId = _byDate[1].id;
    } else {
      _laterId = _byDate.last.id;
      _earlierId = _byDate[_byDate.length - 2].id;
    }
  }

  Future<CompositionVisuals> _visualsFor(String id) =>
      _visuals[id] ??= _store.load(id).catchError(
        (Object _) => CompositionVisuals.none,
      );

  CompositionRecord _record(String id) =>
      _byDate.firstWhere((r) => r.id == id);

  /// One part over every saved scan, oldest first. Each dot is a scan; the
  /// line only joins them.
  Widget _trends(
    BuildContext context,
    String Function(double kg) mass,
    String Function(double cm) length,
  ) {
    final theme = Theme.of(context);
    final weightUnit = unitsOf(context);
    final metric = heightUnitOf(context).isMetric;
    final part = _part;

    // The chart's y values in the units the user reads.
    double shown(double v) => switch (part.kind) {
      _Kind.percent => v,
      _Kind.mass => enteredFromKg(v, weightUnit),
      _Kind.length => metric ? v : inchesFromCm(v),
    };
    String label(double v) => switch (part.kind) {
      _Kind.percent => '${v.toStringAsFixed(1)}%',
      _Kind.mass => mass(v),
      _Kind.length => length(v),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Trend for each part', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Every saved scan, oldest first. Pick a part to see how it changed.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in _Part.values)
              ChoiceChip(
                key: ValueKey('trend-${p.name}'),
                label: Text(p.label),
                selected: p == part,
                onSelected: (_) => setState(() => _part = p),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SimpleLineChart(
          key: const ValueKey('compare-trend-chart'),
          points: [
            for (final r in _byDate)
              LinePoint(
                label: formatShortDate(r.takenAt),
                value: shown(part.of(r)),
                valueLabel: label(part.of(r)),
              ),
          ],
        ),
        if (part == _Part.bodyFat) ...[
          const SizedBox(height: 4),
          Text(
            'Each scan has an 80% range. Changes smaller than that may just be '
            'noise.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final weightUnit = unitsOf(context);
    final metric = heightUnitOf(context).isMetric;

    // Earlier first, whichever way round they were picked.
    var a = _record(_earlierId);
    var b = _record(_laterId);
    if (b.takenAt.isBefore(a.takenAt)) {
      final t = a;
      a = b;
      b = t;
    }

    String mass(double kg) => formatWeight(kg, weightUnit);
    String length(double cm) => metric
        ? '${cm.toStringAsFixed(1)} cm'
        : '${inchesFromCm(cm).toStringAsFixed(1)} in';
    String signedMass(double kg) => '${kg >= 0 ? '+' : '−'}${mass(kg.abs())}';
    String signedLength(double cm) =>
        '${cm >= 0 ? '+' : '−'}${length(cm.abs())}';
    String signedPct(double v) =>
        '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(1)} pts';

    final rangesOverlap =
        a.bodyFatLow <= b.bodyFatHigh && b.bodyFatLow <= a.bodyFatHigh;
    final items = {
      for (final r in _byDate) r.id: formatDate(r.takenAt, today: today),
    };
    final earlierColor = theme.colorScheme.tertiary.withValues(alpha: 0.45);
    final laterColor = theme.colorScheme.primary.withValues(alpha: 0.45);

    return Scaffold(
      appBar: AppBar(title: const Text('Compare scans')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: _Picker(
                  key: const ValueKey('compare-earlier'),
                  label: 'Scan',
                  value: _earlierId,
                  items: items,
                  onChanged: (id) => setState(() => _earlierId = id),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Picker(
                  key: const ValueKey('compare-later'),
                  label: 'Compared with',
                  value: _laterId,
                  items: items,
                  onChanged: (id) => setState(() => _laterId = id),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (a.id == b.id)
            Text(
              'Choose two different scans to compare.',
              style: theme.textTheme.bodyMedium,
            )
          else ...[
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _Row.header(
                      formatShortDate(a.takenAt),
                      formatShortDate(b.takenAt),
                    ),
                    const Divider(),
                    _Row(
                      'Body fat',
                      '${a.bodyFatPct.toStringAsFixed(1)}%',
                      '${b.bodyFatPct.toStringAsFixed(1)}%',
                      signedPct(b.bodyFatPct - a.bodyFatPct),
                      key: const ValueKey('compare-body-fat'),
                    ),
                    _Row(
                      '80% range',
                      '${a.bodyFatLow.toStringAsFixed(1)}–'
                          '${a.bodyFatHigh.toStringAsFixed(1)}',
                      '${b.bodyFatLow.toStringAsFixed(1)}–'
                          '${b.bodyFatHigh.toStringAsFixed(1)}',
                      '',
                    ),
                    _Row(
                      'Fat-free mass',
                      mass(a.fatFreeMassKg),
                      mass(b.fatFreeMassKg),
                      signedMass(b.fatFreeMassKg - a.fatFreeMassKg),
                    ),
                    _Row(
                      'Arm and leg lean',
                      mass(a.leanLimbKg),
                      mass(b.leanLimbKg),
                      signedMass(b.leanLimbKg - a.leanLimbKg),
                    ),
                    _Row(
                      'Weight',
                      mass(a.weightKg),
                      mass(b.weightKg),
                      signedMass(b.weightKg - a.weightKg),
                    ),
                    _Row(
                      'Waist',
                      length(a.waistCm),
                      length(b.waistCm),
                      signedLength(b.waistCm - a.waistCm),
                    ),
                    _Row(
                      'Chest',
                      length(a.chestCm),
                      length(b.chestCm),
                      signedLength(b.chestCm - a.chestCm),
                    ),
                    _Row(
                      'Hip',
                      length(a.hipCm),
                      length(b.hipCm),
                      signedLength(b.hipCm - a.hipCm),
                    ),
                    _Row(
                      'Thigh',
                      length(a.thighCm),
                      length(b.thighCm),
                      signedLength(b.thighCm - a.thighCm),
                    ),
                    _Row(
                      'Upper arm',
                      length(a.upperArmCm),
                      length(b.upperArmCm),
                      signedLength(b.upperArmCm - a.upperArmCm),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              rangesOverlap
                  ? 'The two body fat ranges overlap, so this may not be a '
                        'real change.'
                  : 'The two body fat ranges do not overlap.',
              key: const ValueKey('compare-overlap-note'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            _trends(context, mass, length),
            const SizedBox(height: 24),
            FutureBuilder<List<CompositionVisuals>>(
              future: Future.wait([_visualsFor(a.id), _visualsFor(b.id)]),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final va = snapshot.data![0];
                final vb = snapshot.data![1];
                return _VisualCompare(
                  earlier: va,
                  later: vb,
                  earlierLabel: formatShortDate(a.takenAt),
                  laterLabel: formatShortDate(b.takenAt),
                  earlierColor: earlierColor,
                  laterColor: laterColor,
                  showPhotos: _showPhotos,
                  onShowPhotos: () => setState(() => _showPhotos = true),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Every part a scan records, for the trend chart.
enum _Part {
  bodyFat('Body fat', _Kind.percent),
  fatMass('Fat mass', _Kind.mass),
  fatFree('Fat-free mass', _Kind.mass),
  leanLimb('Arm & leg lean', _Kind.mass),
  weight('Weight', _Kind.mass),
  waist('Waist', _Kind.length),
  chest('Chest', _Kind.length),
  hip('Hip', _Kind.length),
  thigh('Thigh', _Kind.length),
  upperArm('Upper arm', _Kind.length);

  const _Part(this.label, this.kind);

  final String label;
  final _Kind kind;

  /// Stored units: percent, kilograms or centimetres.
  double of(CompositionRecord r) => switch (this) {
    _Part.bodyFat => r.bodyFatPct,
    _Part.fatMass => r.fatMassKg,
    _Part.fatFree => r.fatFreeMassKg,
    _Part.leanLimb => r.leanLimbKg,
    _Part.weight => r.weightKg,
    _Part.waist => r.waistCm,
    _Part.chest => r.chestCm,
    _Part.hip => r.hipCm,
    _Part.thigh => r.thighCm,
    _Part.upperArm => r.upperArmCm,
  };
}

enum _Kind { percent, mass, length }

class _VisualCompare extends StatelessWidget {
  const _VisualCompare({
    required this.earlier,
    required this.later,
    required this.earlierLabel,
    required this.laterLabel,
    required this.earlierColor,
    required this.laterColor,
    required this.showPhotos,
    required this.onShowPhotos,
  });

  final CompositionVisuals earlier;
  final CompositionVisuals later;
  final String earlierLabel;
  final String laterLabel;
  final Color earlierColor;
  final Color laterColor;
  final bool showPhotos;
  final VoidCallback onShowPhotos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget overlay(String title, OutlineLayer? a, OutlineLayer? b) {
      final layers = [?a, ?b];
      return Expanded(
        child: Column(
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (layers.isEmpty)
              SizedBox(
                height: 260,
                child: Center(child: Text('Not saved', style: muted)),
              )
            else
              OutlineOverlay(layers: layers),
          ],
        ),
      );
    }

    OutlineLayer? layer(SilhouetteMask? mask, Color color) =>
        mask == null ? null : OutlineLayer(mask: mask, color: color);

    final hasAnyPhotos = earlier.hasPhotos || later.hasPhotos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Outlines', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Wrap(
          spacing: 16,
          children: [
            _Swatch(color: earlierColor, label: earlierLabel),
            _Swatch(color: laterColor, label: laterLabel),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          key: const ValueKey('compare-outlines'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            overlay(
              'Front',
              layer(earlier.frontOutline, earlierColor),
              layer(later.frontOutline, laterColor),
            ),
            const SizedBox(width: 12),
            overlay(
              'Side',
              layer(earlier.sideOutline, earlierColor),
              layer(later.sideOutline, laterColor),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Both outlines are scaled to the same height. Where the colours do '
          'not overlap, the shape differs; clothing and posture affect it too.',
          style: muted,
        ),
        const SizedBox(height: 24),
        Text('Photos', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        if (hasAnyPhotos && !showPhotos)
          OutlinedButton.icon(
            key: const ValueKey('show-photos'),
            onPressed: onShowPhotos,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Show photos'),
          )
        else ...[
          if (!hasAnyPhotos)
            Text(
              'Original photos are unavailable for these scans.',
              style: muted,
            ),
          const SizedBox(height: 8),
          _PhotoPair(
            'Front',
            earlier.frontPhoto,
            later.frontPhoto,
            earlierLabel,
            laterLabel,
          ),
          const SizedBox(height: 12),
          _PhotoPair(
            'Side',
            earlier.sidePhoto,
            later.sidePhoto,
            earlierLabel,
            laterLabel,
          ),
        ],
      ],
    );
  }
}

class _PhotoPair extends StatelessWidget {
  const _PhotoPair(this.title, this.a, this.b, this.aLabel, this.bLabel);

  final String title;
  final Uint8List? a;
  final Uint8List? b;
  final String aLabel;
  final String bLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget one(Uint8List? bytes, String label) => Expanded(
      child: Column(
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          AspectRatio(
            aspectRatio: 3 / 4,
            child: bytes == null
                ? _UnavailablePhoto()
                : Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) =>
                        const _UnavailablePhoto(),
                  ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Row(children: [one(a, aLabel), const SizedBox(width: 8), one(b, bLabel)]),
      ],
    );
  }
}

class _UnavailablePhoto extends StatelessWidget {
  const _UnavailablePhoto();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.hide_image_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                'Original photo unavailable',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 14, height: 14, color: color),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.a, this.b, this.diff, {super.key})
    : header = false;

  const _Row.header(this.a, this.b)
    : label = '',
      diff = 'Change',
      header = true;

  final String label;
  final String a;
  final String b;
  final String diff;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = header
        ? theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          )
        : theme.textTheme.bodyMedium;
    Widget cell(String text) => Expanded(
      flex: 2,
      child: Text(text, textAlign: TextAlign.end, style: style),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(label, style: style)),
          cell(a),
          cell(b),
          cell(diff),
        ],
      ),
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        items: [
          for (final e in items.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    ),
  );
}
