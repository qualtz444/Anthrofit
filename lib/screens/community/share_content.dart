import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../community/community_models.dart';
import '../../community/community_service.dart';
import '../../data/training_stats.dart';
import '../../models/models.dart';
import '../../photos/progress_photo.dart';
import '../../core/format.dart';
import '../../core/units.dart';
import '../../progress/strength_trends.dart';
import '../../state/profile_scope.dart';
import '../progress/simple_line_chart.dart';

/// The inside of a composer post: its title and period, a tile for each
/// number the author chose, any top-weight changes, and the charts.
///
/// Used both in the composer's preview and in the feed, so the author sees
/// exactly what friends will see. Weights show in the viewer's units.
class ShareContentView extends StatelessWidget {
  const ShareContentView({
    super.key,
    required this.share,
    this.postId,
    this.photoBytes,
  });

  final ProgressShare share;

  /// A shared post's id, to load its photos. Null in the composer's preview.
  final String? postId;

  /// The photos themselves, in the preview, before anything is shared.
  final List<Uint8List>? photoBytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final units = unitsOf(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final s = share;
    String pct(double v) => '${v.toStringAsFixed(1)}%';

    final tiles = <Widget>[
      if (s.workouts != null) _Tile('Workouts', '${s.workouts}'),
      if (s.sets != null) _Tile('Sets', '${s.sets}'),
      if (s.sessions != null) _Tile('Sessions', '${s.sessions}'),
      if (s.volumeKg != null)
        _Tile('Total volume', formatWorkVolume(s.volumeKg!, units)),
      if (s.bestWeightKg != null)
        _Tile('Best weight', formatWeight(s.bestWeightKg!, units)),
      if (s.bestSetReps != null)
        _Tile(
          'Best set',
          s.bestSetKg == null
              ? '${s.bestSetReps} reps'
              : '${formatWeight(s.bestSetKg!, units)} × ${s.bestSetReps}',
        ),
      if (s.bodyFatPct != null)
        _Tile(
          'Body fat',
          pct(s.bodyFatPct!),
          detail: s.bodyFatLow == null || s.bodyFatHigh == null
              ? null
              : '80% range ${pct(s.bodyFatLow!)}–${pct(s.bodyFatHigh!)}',
        ),
      if (s.fatFreeMassKg != null)
        _Tile('Fat-free mass', formatWeight(s.fatFreeMassKg!, units)),
      if (s.previousBodyFatPct != null)
        _Tile('Previous scan', pct(s.previousBodyFatPct!)),
      if (s.bodyWeightKg != null)
        _Tile('Latest weight', formatWeight(s.bodyWeightKg!, units)),
      if (s.bodyWeightChangeKg != null)
        _Tile(
          'Change this period',
          s.bodyWeightChangeKg == 0
              ? 'No change'
              : '${s.bodyWeightChangeKg! > 0 ? '+' : ''}'
                    '${formatWeight(s.bodyWeightChangeKg!, units)}',
        ),
      if (s.muscleWorkouts != null)
        _Tile('Workouts with muscle data', '${s.muscleWorkouts}'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_iconOf(s.topic), color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.title,
                key: const ValueKey('share-title'),
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (s.topic != ShareTopic.photos) Text(s.periodLabel, style: muted),
          ],
        ),
        if (s.photos.isNotEmpty) ...[
          const SizedBox(height: 10),
          _SharedPhotos(
            infos: s.photos,
            bytes: photoBytes != null
                ? Future.value(photoBytes!)
                : postId != null
                ? _loadPhotos(postId!)
                : Future.value(const <Uint8List>[]),
          ),
        ],
        if (tiles.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: tiles),
        ],
        if (s.changes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Top-weight changes', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final c in s.changes)
            Row(
              children: [
                Icon(
                  c.toKg > c.fromKg ? Icons.trending_up : Icons.trending_down,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${c.exercise}: ${formatWeight(c.fromKg, units)} → '
                    '${formatWeight(c.toKg, units)}',
                  ),
                ),
              ],
            ),
        ],
        if (s.muscles.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Muscle coverage', style: theme.textTheme.titleSmall),
          if (s.muscleWeekStart != null)
            Text(
              'Weekly frequency · ${formatShortDate(s.muscleWeekStart!)} – '
              '${formatShortDate(addDays(s.muscleWeekStart!, 6))}',
              style: muted,
            ),
          for (final muscle in s.muscles)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${_muscleLabel(muscle.muscle)} · '
                '${muscle.primaryWorkouts} primary workouts · '
                '${muscle.secondaryWorkouts} assisting workouts'
                '${s.muscleWeekStart == null ? '' : '\n  Primary days: '
                          '${_days(muscle.primaryDays)} · Assisting days: '
                          '${_days(muscle.secondaryDays)}'}',
              ),
            ),
        ],
        for (final chart in s.charts) ...[
          const SizedBox(height: 12),
          Text(chart.kind.label, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          SimpleLineChart(
            key: ValueKey('share-chart-${chart.kind.name}'),
            height: 150,
            points: [
              for (final p in chart.points)
                LinePoint(
                  label: formatShortDate(p.date),
                  value: _shown(chart.kind, p.value, units),
                  valueLabel: _label(chart.kind, p.value, units),
                ),
            ],
          ),
        ],
        if (s.topic == ShareTopic.body) ...[
          const SizedBox(height: 8),
          Text(
            [
              if (s.scanDate != null)
                'Scan of ${formatShortDate(s.scanDate!)}.',
              'Camera estimates, not measurements.',
            ].join(' '),
            style: muted,
          ),
        ],
      ],
    );
  }

  static IconData _iconOf(ShareTopic t) => switch (t) {
    ShareTopic.overall => Icons.insights,
    ShareTopic.exercise => Icons.fitness_center,
    ShareTopic.body => Icons.donut_large,
    ShareTopic.bodyWeight => Icons.monitor_weight_outlined,
    ShareTopic.muscles => Icons.accessibility_new,
    ShareTopic.photos => Icons.photo_library_outlined,
  };

  static String _muscleLabel(String id) => MuscleGroup.byId(id)?.label ?? id;

  static String _days(List<int> days) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final valid = days.where((day) => day >= 0 && day < labels.length);
    return valid.map((day) => labels[day]).join(', ');
  }

  /// Loaded once per post while the app runs, so scrolling the feed does
  /// not download the same photos again.
  static final Map<String, Future<List<Uint8List>>> _photoCache = {};

  static Future<List<Uint8List>> _loadPhotos(String postId) =>
      _photoCache.putIfAbsent(postId, () async {
        final photos = await communityService.postPhotos(postId);
        // A failed load is not kept, so it is tried again next time.
        if (photos.isEmpty) _photoCache.remove(postId);
        return photos;
      });

  static double _shown(ShareChartKind k, double v, WeightUnit units) =>
      switch (k) {
        ShareChartKind.bodyFat => v,
        ShareChartKind.weight ||
        ShareChartKind.bodyWeight ||
        ShareChartKind.volume => enteredFromKg(v, units),
      };

  static String _label(ShareChartKind k, double v, WeightUnit units) =>
      switch (k) {
        ShareChartKind.bodyFat => '${v.toStringAsFixed(1)}%',
        ShareChartKind.weight => formatNumber(enteredFromKg(v, units)),
        ShareChartKind.bodyWeight => formatWeight(v, units),
        ShareChartKind.volume => formatThousands(
          enteredFromKg(v, units).roundToDouble(),
        ),
      };
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, {this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(label, style: theme.textTheme.bodySmall),
          if (detail != null)
            Text(
              detail!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// Shared progress photos side by side, each with its date and pose.
class _SharedPhotos extends StatelessWidget {
  const _SharedPhotos({required this.infos, required this.bytes});

  final List<SharedPhotoInfo> infos;
  final Future<List<Uint8List>> bytes;

  static String _pose(String name) {
    for (final p in PhotoPose.values) {
      if (p.name == name && p != PhotoPose.other) return p.label;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<Uint8List>>(
      key: const ValueKey('share-photos'),
      future: bytes,
      builder: (context, snap) {
        final images = snap.data ?? const <Uint8List>[];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < infos.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AspectRatio(
                        aspectRatio: 3 / 4,
                        child: i < images.length
                            ? Image.memory(
                                images[i],
                                fit: BoxFit.cover,
                                cacheWidth: 600,
                              )
                            : ColoredBox(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                child: Center(
                                  child:
                                      snap.connectionState ==
                                          ConnectionState.done
                                      ? const Icon(Icons.broken_image_outlined)
                                      : const CircularProgressIndicator(),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        formatShortDate(infos[i].takenAt),
                        if (_pose(infos[i].pose).isNotEmpty)
                          _pose(infos[i].pose),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (infos[i].bodyFatPct != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          'Body fat '
                              '${infos[i].bodyFatPct!.toStringAsFixed(1)}%',
                          if (infos[i].bodyFatLow != null &&
                              infos[i].bodyFatHigh != null)
                            '80% range '
                                '${infos[i].bodyFatLow!.toStringAsFixed(1)}–'
                                '${infos[i].bodyFatHigh!.toStringAsFixed(1)}%',
                          if (infos[i].fatFreeMassKg != null)
                            'Fat-free mass '
                                '${formatWeight(infos[i].fatFreeMassKg!, unitsOf(context))}',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The bordered box around a post's main content, in the feed and in the
/// composer's preview.
class PostContentBox extends StatelessWidget {
  const PostContentBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}
