import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/units.dart';
import '../../data/training_stats.dart';
import '../../models/models.dart';
import '../../progress/progress_analytics_service.dart';
import '../../progress/progress_insights.dart';
import '../../state/profile_scope.dart';
import '../../state/program_scope.dart';
import '../../state/session_scope.dart';
import '../../composition/composition_visuals.dart';
import '../composition/composition_compare_screen.dart';
import '../composition/composition_result_screen.dart';
import '../history/history_screen.dart';
import '../../intelligence/ai_explainer.dart';
import '../widgets/ai_explain_button.dart';
import '../widgets/empty_state.dart';
import 'exercise_progress_screen.dart';
import 'range_selector.dart';
import 'share_progress_sheet.dart';
import 'simple_line_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math' as math;
import '../widgets/muscle_image.dart';
import '../../core/snack_bar_timing.dart';
import '../../community/community_models.dart';

/// Progress, as three tabs that each answer one question:
///
///   Strength          Am I getting stronger?
///   Muscle Distribution   Which muscle groups do my workouts cover, and
///                         on how many days?
///   Body Weight       Is my body weight changing?
///
/// The period chips above the tabs apply to all three, and sit above them so
/// it is obvious that they do.
///
/// The Body Weight tab also shows body composition scans: the latest scan
/// laid out like its result screen, body fat over time with its 80% range,
/// and the latest scan against the one before it.
///
/// Deliberately not here: planned-versus-done adherence, streaks, targets
/// for any muscle, and body proportions. Proportions live in Body analysis.
///
/// Every number is worked out by ProgressAnalytics from completed sessions
/// and the profile's weight log; nothing here calculates, and nothing is
/// sample data. Scan proportions are not here: they are structure, not
/// progress, and live in Body analysis (opened from Home).
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  ProgressRange _range = ProgressRange.allTime;

  /// The calendar week (a Monday) shown in Muscle Distribution's weekly
  /// frequency; null follows the current week.
  DateTime? _weekStart;

  @override
  Widget build(BuildContext context) {
    final sessions = SessionScope.of(context).completedSessions;
    final profile = ProfileScope.of(context).profile;
    final analytics = ProgressAnalytics(
      sessions: sessions,
      weightLog: profile?.weightLog ?? const [],
    );

    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Progress'),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const HistoryScreen()),
              ),
              icon: const Icon(Icons.history),
              label: const Text('Workout history'),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Strength'),
              Tab(
                height: 56,
                child: Text('Muscle Distribution', textAlign: TextAlign.center),
              ),
              Tab(text: 'Body Weight'),
            ],
          ),
        ),
        body: Column(
          children: [
            _PeriodHeader(
              range: _range,
              onChanged: (range) => setState(() => _range = range),
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                children: [
                  _Tab(
                    children: _guard(
                      () => analytics.hasWorkouts
                          ? _strength(context, analytics, sessions)
                          : const [_NoWorkouts()],
                    ),
                  ),
                  _Tab(
                    children: _guard(
                      () => analytics.hasWorkouts
                          ? _muscles(context, analytics, sessions)
                          : const [_NoWorkouts()],
                    ),
                  ),
                  _Tab(
                    children: _guard(() => _body(context, analytics, profile)),
                  ),
                ],
              ),
            ),
            // Below the pages, so it reads as an action on the active section.
            if (sessions.isNotEmpty ||
                (profile?.compositionLog.isNotEmpty ?? false) ||
                (profile?.weightLog.isNotEmpty ?? false))
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: Builder(
                      builder: (shareContext) => OutlinedButton.icon(
                        key: const ValueKey('share-progress'),
                        onPressed: () {
                          final topic = switch (DefaultTabController.of(
                            shareContext,
                          ).index) {
                            0 => ShareTopic.overall,
                            1 => ShareTopic.muscles,
                            _ => ShareTopic.bodyWeight,
                          };
                          final weeks = analytics.weeksIn(_range);
                          showShareProgressSheet(
                            shareContext,
                            scans: profile?.compositionLog ?? const [],
                            sessions: sessions,
                            weightLog: profile?.weightLog ?? const [],
                            currentBodyWeightKg: profile?.weightKg,
                            range: _range,
                            muscleWeekStart:
                                _weekStart ??
                                (weeks.isEmpty ? null : weeks.last),
                            initialTopic: topic,
                          );
                        },
                        icon: const Icon(Icons.ios_share),
                        label: const Text('Share progress with friends'),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Builds one tab's content; if the numbers cannot be worked out, the tab
  /// says so instead of taking the screen down.
  List<Widget> _guard(List<Widget> Function() build) {
    try {
      return build();
    } catch (_) {
      return const [
        EmptyState(
          title: "Couldn't load your progress.",
          message:
              'Something went wrong reading your workout history. '
              'Go back and try again.',
        ),
      ];
    }
  }

  // =====================================================================
  // Strength
  // =====================================================================
  List<Widget> _strength(
    BuildContext context,
    ProgressAnalytics analytics,
    List<WorkoutSession> sessions,
  ) {
    final theme = Theme.of(context);
    final units = unitsOf(context);
    final today = analytics.today;
    final summary = analytics.summary(_range);
    final volumes = analytics.workoutVolume(_range);
    final volumeText = volumes.isEmpty
        ? ''
        : volumeInsight(
            [for (final v in volumes) (date: v.date, volumeKg: v.volumeKg)],
            units,
            noun: 'total workout volume',
          );
    final exercises = exercisesPerformed(
      sessionsInRange(sessions, _range, today),
    );

    return [
      // ---- The whole workout, over time ----
      Text('Total workout volume', style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      const _Caption(
        'Weight × reps for each day\'s working sets. It shows how much work you '
        'did, not strength.',
      ),
      const SizedBox(height: 12),
      _trendChart(
        context,
        key: 'overall-volume-chart',
        seriesName: 'Total volume (${units.short}·reps)',
        axisName: '${units.short}·reps',
        emptyText:
            'No completed workouts with weighted sets in this period. '
            'Log a workout with weights to see your total volume.',
        points: [
          for (final v in volumes)
            _TrendPoint(
              date: v.date,
              y: enteredFromKg(v.volumeKg, units),
              value: formatWorkVolume(v.volumeKg, units),
              tooltip:
                  '${formatShortDate(v.date)}\n'
                  '${formatWorkVolume(v.volumeKg, units)}\n'
                  '${pluralize(v.sets, 'set')}'
                  '${v.workouts > 1 ? ' in ${v.workouts} workouts' : ''}',
            ),
        ],
      ),
      if (summary.bodyweightSets > 0) ...[
        const SizedBox(height: 8),
        Text(
          'Bodyweight: ${pluralize(summary.bodyweightSets, 'set')} · '
          '${summary.bodyweightReps} reps (no weight logged)',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      if (volumes.isNotEmpty) ...[
        const SizedBox(height: 12),
        _Insight(volumeText),
        AiExplainButton(
          request: ExplainRequest(
            kind: ExplainKind.insights,
            facts: [
              'Total workout volume, ${_range.label}.',
              volumeText,
              'Volume is weight times reps; it is not the same as strength.',
            ],
          ),
        ),
      ],
      const SizedBox(height: 24),

      // ---- Each exercise: opens its own progress page ----
      Text('All exercises', style: theme.textTheme.titleSmall),
      const SizedBox(height: 4),
      const _Caption(
        'Tap an exercise to see its heaviest weight, best set and every '
        'session.',
      ),
      const SizedBox(height: 8),
      if (exercises.isEmpty)
        const _Caption(
          'No exercises with logged sets in this period. Try a longer range.',
        ),
      for (final e in exercises)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              title: Text(e.name),
              subtitle: Text(
                '${pluralize(e.sessionCount, 'session')} · Last: '
                '${formatDate(e.lastPerformed, today: today)}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ExerciseProgressScreen(
                    exerciseId: e.exerciseId,
                    initialRange: _range,
                  ),
                ),
              ),
            ),
          ),
        ),
      const _HowCounted(lines: _strengthNotes),
    ];
  }

  /// One line chart over the sessions' dates. Always drawn: with no points
  /// the empty axes carry a message, and with one point it is a single dot
  /// with a note that a trend needs more sessions.
  Widget _trendChart(
    BuildContext context, {
    required String key,
    required String seriesName,
    required String axisName,
    required String emptyText,
    required List<_TrendPoint> points,
    bool integer = false,
  }) {
    final theme = Theme.of(context);
    final first = points.isEmpty
        ? dateOnly(DateTime.now())
        : dateOnly(points.first.date);
    final ys = [for (final p in points) p.y];
    final axis = ys.isEmpty
        ? _niceAxis(0, 0, integer: integer)
        : _niceAxis(ys.reduce(math.min), ys.reduce(math.max), integer: integer);
    final chart = _DateLineChart(
      key: ValueKey(key),
      firstDate: first,
      lastDay: points.isEmpty ? 0 : _dayIndex(points.last.date, first),
      minY: axis.min,
      maxY: axis.max,
      interval: axis.step,
      leftName: axisName,
      leftLabel: _axisNumber,
      series: [
        if (points.isNotEmpty)
          _ChartSeries(
            name: seriesName,
            color: theme.colorScheme.primary,
            spots: [
              for (final p in points)
                FlSpot(_dayIndex(p.date, first).toDouble(), p.y),
            ],
            tooltips: [for (final p in points) p.tooltip],
          ),
      ],
    );
    if (points.isEmpty) {
      return Stack(
        alignment: Alignment.center,
        children: [
          chart,
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 24, 16, 24),
            child: Text(
              emptyText,
              key: ValueKey('$key-empty'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }
    if (points.length < kMinTrendPoints) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          chart,
          const SizedBox(height: 4),
          const _Caption('Log more sessions to see a trend.'),
        ],
      );
    }
    return chart;
  }

  static const List<String> _strengthNotes = [
    'Only completed working and failure sets count. Warm-ups, skipped sets '
        'and sets with no reps do not.',
    'Volume is weight × reps for sets with a weight. Two workouts on one day '
        'count as one day.',
    'Insights compare the start and end of the period.',
    'Volume shows how much work was done. It is not a direct measure of '
        'strength.',
    "Each exercise's own page shows its heaviest weight, best set and "
        'sessions.',
  ];

  // =====================================================================
  // Muscle Distribution
  // =====================================================================
  List<Widget> _muscles(
    BuildContext context,
    ProgressAnalytics analytics,
    List<WorkoutSession> sessions,
  ) {
    final theme = Theme.of(context);
    final distribution = analytics.distribution(_range);
    if (distribution.isEmpty) {
      return const [
        EmptyState(
          title: 'No muscle data in this period.',
          message:
              'Complete a workout with exercises that list their muscles '
              'to see which muscle groups it covered. Try a longer range if '
              'you trained earlier.',
        ),
      ];
    }

    // The week shown: the chosen one while it is still on offer, else this
    // week, which is always the last.
    final weeks = analytics.weeksIn(_range);
    final week = weeks.contains(_weekStart) ? _weekStart! : weeks.last;
    final weekIndex = weeks.indexOf(week);
    final isThisWeek = week == startOfWeek(dateOnly(analytics.today));
    final days = analytics.muscleDaysIn(week, _range);
    final weekLabel =
        '${formatShortDate(week)} – '
        '${formatShortDate(addDays(week, 6))}'
        '${isThisWeek ? ' · This week' : ''}';

    return [
      // ---- Weekly frequency: which days each muscle was trained ----
      Text('Weekly frequency', style: theme.textTheme.titleSmall),
      const SizedBox(height: 4),
      Row(
        children: [
          IconButton(
            key: const ValueKey('week-prev'),
            tooltip: 'Previous week',
            icon: const Icon(Icons.chevron_left),
            onPressed: weekIndex > 0
                ? () => setState(() => _weekStart = weeks[weekIndex - 1])
                : null,
          ),
          Expanded(
            child: Text(
              weekLabel,
              key: const ValueKey('week-label'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
          ),
          IconButton(
            key: const ValueKey('week-next'),
            tooltip: 'Next week',
            icon: const Icon(Icons.chevron_right),
            onPressed: weekIndex < weeks.length - 1
                ? () => setState(() => _weekStart = weeks[weekIndex + 1])
                : null,
          ),
        ],
      ),
      const _Caption(
        'Days this week each muscle group was trained.',
      ),
      const SizedBox(height: 12),
      const _InvolvementLegend(),
      const SizedBox(height: 12),
      if (days.isEmpty)
        const _Caption('No eligible workouts were recorded in this week.')
      else ...[
        const _WeekHeader(),
        for (final d in days)
          _WeekRow(key: ValueKey('week-${d.muscle.name}'), days: d),
      ],

      // ---- Muscles not trained at all in the chosen period ----
      if (distribution.notRecorded.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Not trained in this period', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          key: const ValueKey('dist-not-recorded'),
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in distribution.notRecorded)
              Chip(
                avatar: MuscleImage(m, size: 24),
                label: Text(m.label),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
      const SizedBox(height: 16),
      _Insight(
        distributionInsight(distribution),
        valueKey: const ValueKey('muscle-insight'),
      ),
      if (programGapInsight(
            ProgramScope.of(context).activeProgram,
            distribution,
          )
          case final gap?) ...[
        const SizedBox(height: 8),
        _Insight(gap, valueKey: const ValueKey('program-gap-insight')),
      ],
      AiExplainButton(
        request: ExplainRequest(
          kind: ExplainKind.insights,
          facts: [
            distributionInsight(distribution),
            ?programGapInsight(
              ProgramScope.of(context).activeProgram,
              distribution,
            ),
          ],
        ),
      ),
      const _HowCounted(lines: _muscleNotes),
    ];
  }

  static const List<String> _muscleNotes = [
    'Each exercise lists the muscles it mainly trains (primary) and those that '
        'assist (secondary).',
    'Solid day: the muscle was a main target. Outlined: it only assisted.',
    'Only completed working sets count. Warm-ups, skipped sets and cardio do '
        'not.',
    'Weeks run Monday to Sunday. A day counts once per muscle, however many '
        'exercises trained it.',
    'This shows what your logged workouts covered. It does not say whether a '
        'muscle is trained enough.',
  ];

  /// Whole days from [first] to [date], safe across daylight-saving changes.
  static int _dayIndex(DateTime date, DateTime first) => DateTime.utc(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime.utc(first.year, first.month, first.day)).inDays;

  /// Axis numbers: whole when whole, one decimal otherwise, k above 10,000.
  static String _axisNumber(double v) {
    if (v.abs() >= 10000) return '${(v / 1000).toStringAsFixed(0)}k';
    return v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
  }

  // =====================================================================
  // Body
  // =====================================================================
  List<Widget> _body(
    BuildContext context,
    ProgressAnalytics analytics,
    UserProfile? profile,
  ) {
    final theme = Theme.of(context);
    final units = unitsOf(context);
    final weight = analytics.bodyWeight(_range);

    final Widget trend;
    if (weight.isEmpty) {
      trend = const EmptyState(
        title: 'No body measurements yet.',
        message: 'Add a measurement to start tracking your body progress.',
      );
    } else if (!weight.hasTrend) {
      trend = const _Caption('Log more to see a trend.');
    } else {
      final change = weight.changeKg!;
      final sign = change > 0 ? '+' : '';
      trend = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(
            label: 'Change this period',
            value: change == 0
                ? 'No change'
                : '$sign${formatWeight(change, units)}',
          ),
          const SizedBox(height: 12),
          SimpleLineChart(
            key: const ValueKey('body-weight-chart'),
            points: [
              for (final p in weight.points)
                LinePoint(
                  label: formatShortDate(p.date),
                  value: p.weightKg,
                  valueLabel: formatNumber(enteredFromKg(p.weightKg, units)),
                ),
            ],
          ),
        ],
      );
    }

    return [
      // ---- Current weight ----
      // From the profile, so it shows even before any reading is logged.
      // The latest reading in the period; with none in it, the profile's
      // weight, which is the latest one saved.
      if (weight.latestKg != null || profile != null) ...[
        _Stat(
          label: 'Latest weight',
          value: formatWeight(weight.latestKg ?? profile!.weightKg, units),
        ),
        const SizedBox(height: 24),
      ],

      // ---- Weight trend ----
      Text('Weight trend', style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      trend,

      // ---- Weight history ----
      if (weight.points.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text('Weight history', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Column(
          key: const ValueKey('weight-history'),
          children: [
            for (final p in weight.points.reversed)
              _InfoRow(
                label: formatDate(p.date, today: analytics.today),
                value: formatWeight(p.weightKg, units),
              ),
          ],
        ),
      ],
      if (profile != null) ...[
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _logWeight(context, profile, units),
            icon: const Icon(Icons.add),
            label: const Text('Log weight'),
          ),
        ),
      ],
      const SizedBox(height: 24),
      ..._composition(context, analytics, profile),
    ];
  }

  /// Saved scans' outlines, loaded once per record id. They live on this
  /// phone only; a scan without them shows its numbers alone.
  final Map<String, Future<CompositionVisuals>> _visuals = {};

  Future<CompositionVisuals> _visualsFor(String id) =>
      _visuals[id] ??= CompositionVisualStore()
          .load(id)
          .catchError((Object _) => CompositionVisuals.none)
          .then((visuals) {
            // An empty answer is not kept: the pictures may simply not have
            // been written yet, and the next build should look again.
            if (visuals.isEmpty) _visuals.remove(id);
            return visuals;
          });

  /// Body composition: the latest scan laid out like its result screen, body
  /// fat over the period, and the latest scan against the one before it.
  List<Widget> _composition(
    BuildContext context,
    ProgressAnalytics analytics,
    UserProfile? profile,
  ) {
    final theme = Theme.of(context);
    final all = [...?profile?.compositionLog]
      ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
    final inRange = [
      for (final r in all)
        if (isInRange(dateOnly(r.takenAt), _range, analytics.today)) r,
    ];

    final children = <Widget>[
      Text('Body composition', style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
    ];
    if (all.isEmpty) {
      return [
        ...children,
        const _Caption(
          'No body composition scans yet. Use the scan button to take one.',
        ),
      ];
    }

    // ---- The latest scan, as its result screen showed it ----
    final latest = all.last;
    children.addAll([
      Text('Latest scan', style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      FutureBuilder<CompositionVisuals>(
        key: const ValueKey('latest-scan'),
        future: _visualsFor(latest.id),
        builder: (context, snapshot) => CompositionRecordSummary(
          record: latest,
          // Numbers first; the outline appears once it has loaded.
          visuals: snapshot.data ?? CompositionVisuals.none,
          visualsLoaded: snapshot.connectionState == ConnectionState.done,
        ),
      ),
      const SizedBox(height: 24),
    ]);

    // ---- Body fat over the period ----
    children.addAll([
      Text('Body fat progress', style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
    ]);
    if (inRange.isEmpty) {
      children.add(
        _trendChart(
          context,
          key: 'body-fat-chart',
          seriesName: 'Body fat %',
          axisName: 'Body fat %',
          emptyText: 'No body composition scans in this period.',
          points: const [],
        ),
      );
    } else {
      final first = dateOnly(inRange.first.takenAt);
      final fatAxis = _niceAxis(
        inRange.map((r) => r.bodyFatLow).reduce(math.min),
        inRange.map((r) => r.bodyFatHigh).reduce(math.max),
      );
      children.addAll([
        _RangeLineChart(
          key: const ValueKey('body-fat-chart'),
          firstDate: first,
          lastDay: _dayIndex(inRange.last.takenAt, first),
          minY: fatAxis.min,
          maxY: fatAxis.max,
          interval: fatAxis.step,
          leftName: 'Body fat %',
          leftLabel: _axisNumber,
          color: theme.colorScheme.primary,
          points: [
            for (final r in inRange)
              (
                x: _dayIndex(r.takenAt, first).toDouble(),
                y: r.bodyFatPct,
                low: r.bodyFatLow,
                high: r.bodyFatHigh,
                tooltip:
                    '${formatShortDate(r.takenAt)}\n'
                    '${r.bodyFatPct.toStringAsFixed(1)}% '
                    '(${r.bodyFatLow.toStringAsFixed(1)}–'
                    '${r.bodyFatHigh.toStringAsFixed(1)})',
              ),
          ],
        ),
        const SizedBox(height: 4),
        _Caption(
          inRange.length < kMinTrendPoints
              ? 'Scan again to see a trend. The shaded band is the 80% range.'
              : 'The shaded band is each scan\'s 80% range. Changes inside it '
                    'may just be noise.',
        ),
      ]);
    }
    children.add(const SizedBox(height: 24));

    // ---- Latest against the one before ----
    children.add(_PreviousScanCard(records: all));

    final change = compositionInsight(inRange);
    if (change != null) {
      children.addAll([
        const SizedBox(height: 12),
        _Insight(change, valueKey: const ValueKey('composition-insight')),
        AiExplainButton(
          request: ExplainRequest(
            kind: ExplainKind.insights,
            facts: [
              change,
              // For the AI only, never shown: stops it claiming diet
              // adherence, which the app cannot know.
              'The app does not track food intake.',
            ],
          ),
        ),
      ]);
    }
    return children;
  }

  Future<void> _logWeight(
    BuildContext context,
    UserProfile profile,
    WeightUnit units,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = ProfileScope.of(context, listen: false);
    final entered = await showDialog<double>(
      context: context,
      builder: (_) => _WeightDialog(
        initial: enteredFromKg(profile.weightKg, units),
        unit: units.short,
      ),
    );
    if (entered == null) return;
    try {
      // Saving the profile records the reading: see ProfileController.save.
      await controller.save(
        profile.copyWith(weightKg: kgFromEntered(entered, units)),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          duration: kSnackBarDuration,
          persist: false,
          content: Text("Couldn't save your weight. Try again."),
        ),
      );
    }
  }
}

/// The latest scan against the one before it, with the change in each
/// part. Tapping opens the full comparison, with a trend for each part.
class _PreviousScanCard extends StatelessWidget {
  const _PreviousScanCard({required this.records});

  /// Every saved scan, oldest first.
  final List<CompositionRecord> records;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final units = unitsOf(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    if (records.length < 2) {
      return Card(
        key: const ValueKey('previous-scan-comparison'),
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.compare_arrows),
          title: const Text('Previous scan comparison'),
          subtitle: Text(
            'Scan again to compare your next scan with this one.',
            style: muted,
          ),
        ),
      );
    }

    final a = records[records.length - 2];
    final b = records.last;
    String signedMass(double kg) =>
        '${kg >= 0 ? '+' : '−'}${formatWeight(kg.abs(), units)}';
    final fatDiff = b.bodyFatPct - a.bodyFatPct;
    final overlap =
        a.bodyFatLow <= b.bodyFatHigh && b.bodyFatLow <= a.bodyFatHigh;

    Widget row(String label, String before, String after, String diff) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text(label)),
              Expanded(
                flex: 4,
                child: Text(
                  '$before → $after',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  diff,
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
      key: const ValueKey('previous-scan-comparison'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CompositionCompareScreen(records: records),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.compare_arrows, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Previous scan comparison',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${formatShortDate(a.takenAt)} → '
                '${formatShortDate(b.takenAt)}',
                style: muted,
              ),
              const SizedBox(height: 8),
              row(
                'Body fat',
                '${a.bodyFatPct.toStringAsFixed(1)}%',
                '${b.bodyFatPct.toStringAsFixed(1)}%',
                '${fatDiff >= 0 ? '+' : '−'}'
                    '${fatDiff.abs().toStringAsFixed(1)} pts',
              ),
              row(
                'Fat mass',
                formatWeight(a.fatMassKg, units),
                formatWeight(b.fatMassKg, units),
                signedMass(b.fatMassKg - a.fatMassKg),
              ),
              row(
                'Fat-free mass',
                formatWeight(a.fatFreeMassKg, units),
                formatWeight(b.fatFreeMassKg, units),
                signedMass(b.fatFreeMassKg - a.fatFreeMassKg),
              ),
              row(
                'Arm & leg lean',
                formatWeight(a.leanLimbKg, units),
                formatWeight(b.leanLimbKg, units),
                signedMass(b.leanLimbKg - a.leanLimbKg),
              ),
              const SizedBox(height: 6),
              Text(
                overlap
                    ? 'The two body fat ranges overlap, so the change is '
                          'within what the scan cannot tell apart.'
                    : 'The two body fat ranges do not overlap.',
                style: muted,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Tap for more details',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Icon(Icons.chevron_right, color: theme.colorScheme.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One point of a strength trend: where it sits, how it reads, and what its
/// tooltip says.
class _TrendPoint {
  const _TrendPoint({
    required this.date,
    required this.y,
    required this.value,
    required this.tooltip,
  });

  final DateTime date;

  /// Height on the chart, already in the user's units.
  final double y;

  /// The value as text, for when there is only this one point.
  final String value;
  final String tooltip;
}

/// Round axis limits and a step for data between [lo] and [hi], so labels are
/// numbers like 40, 42.5, 45 rather than 41.37. The line gets room above and
/// below, and the axis never goes under zero. [integer] keeps steps whole.
({double min, double max, double step}) _niceAxis(
  double lo,
  double hi, {
  bool integer = false,
}) {
  var span = hi - lo;
  if (span <= 0) span = math.max(hi.abs() * 0.2, integer ? 2.0 : 1.0);
  var raw = span / 4;
  if (integer) raw = math.max(raw, 1.0);
  final exp = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final f = raw / exp;
  final double mult;
  if (f <= 1) {
    mult = 1;
  } else if (f <= 2) {
    mult = 2;
  } else if (f <= 2.5 && !integer) {
    mult = 2.5;
  } else if (f <= 5) {
    mult = 5;
  } else {
    mult = 10;
  }
  var step = mult * exp;
  if (integer && step < 1) step = 1;

  var min = (lo / step).floor() * step;
  var max = (hi / step).ceil() * step;
  if (min >= lo) min -= step;
  if (max <= hi) max += step;
  if (min < 0) min = 0;
  return (min: min, max: max, step: step);
}

/// One line on a [_DateLineChart].
class _ChartSeries {
  const _ChartSeries({
    required this.name,
    required this.color,
    required this.spots,
    required this.tooltips,
  });

  final String name;
  final Color color;

  /// x is whole days since the chart's first date.
  final List<FlSpot> spots;

  /// What touching each point says, one per spot.
  final List<String> tooltips;
}

/// A line chart over dates, with a legend and tooltips, from real points
/// only: no smoothing and nothing drawn between observations.
class _DateLineChart extends StatelessWidget {
  const _DateLineChart({
    super.key,
    required this.series,
    required this.firstDate,
    required this.lastDay,
    required this.minY,
    required this.maxY,
    required this.interval,
    required this.leftLabel,
    required this.leftName,
  });

  final List<_ChartSeries> series;
  final DateTime firstDate;

  /// x of the last point, in days from [firstDate].
  final int lastDay;
  final double minY;
  final double maxY;
  final double interval;
  final String Function(double) leftLabel;

  /// What the y-axis measures, written beside it.
  final String leftName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axisStyle = TextStyle(
      fontSize: 10,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final lastX = math.max(lastDay, 1).toDouble();
    final xInterval = math.max(1, (lastX / 3).ceil()).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            for (final line in series)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 16, height: 3, color: line.color),
                  const SizedBox(width: 6),
                  Text(line.name, style: theme.textTheme.bodySmall),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: lastX,
              minY: minY,
              maxY: maxY,
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touched) => [
                    for (final t in touched)
                      LineTooltipItem(
                        series[t.barIndex].tooltips[t.spotIndex],
                        const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                  ],
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
              ),
              borderData: FlBorderData(show: true),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  axisNameWidget: Text(leftName, style: axisStyle),
                  axisNameSize: 18,
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    interval: interval,
                    getTitlesWidget: (value, meta) =>
                        Text(leftLabel(value), style: axisStyle),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: xInterval,
                    getTitlesWidget: (value, meta) {
                      if (value != value.roundToDouble()) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          formatShortDate(addDays(firstDate, value.round())),
                          style: axisStyle,
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                for (final line in series)
                  LineChartBarData(
                    spots: line.spots,
                    isCurved: false,
                    color: line.color,
                    barWidth: 3,
                    dotData: FlDotData(show: true),
                    belowBarData: BarAreaData(show: false),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A line of estimates over dates with each point's range shaded around it.
class _RangeLineChart extends StatelessWidget {
  const _RangeLineChart({
    super.key,
    required this.points,
    required this.firstDate,
    required this.lastDay,
    required this.minY,
    required this.maxY,
    required this.interval,
    required this.leftLabel,
    required this.leftName,
    required this.color,
  });

  final List<({double x, double y, double low, double high, String tooltip})>
  points;
  final DateTime firstDate;
  final int lastDay;
  final double minY;
  final double maxY;
  final double interval;
  final String Function(double) leftLabel;
  final String leftName;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axisStyle = TextStyle(
      fontSize: 10,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final lastX = math.max(lastDay, 1).toDouble();
    final xInterval = math.max(1, (lastX / 3).ceil()).toDouble();
    LineChartBarData edge(List<FlSpot> spots) => LineChartBarData(
      spots: spots,
      isCurved: false,
      color: Colors.transparent,
      barWidth: 0,
      dotData: const FlDotData(show: false),
    );

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: lastX,
          minY: minY,
          maxY: maxY,
          betweenBarsData: [
            BetweenBarsData(
              fromIndex: 0,
              toIndex: 1,
              color: color.withValues(alpha: 0.18),
            ),
          ],
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touched) => [
                for (final t in touched)
                  t.barIndex == 2
                      ? LineTooltipItem(
                          points[t.spotIndex].tooltip,
                          const TextStyle(color: Colors.white, fontSize: 12),
                        )
                      : null,
              ],
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
          ),
          borderData: FlBorderData(show: true),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              axisNameWidget: Text(leftName, style: axisStyle),
              axisNameSize: 18,
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: interval,
                getTitlesWidget: (value, meta) =>
                    Text(leftLabel(value), style: axisStyle),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: xInterval,
                getTitlesWidget: (value, meta) {
                  if (value != value.roundToDouble()) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      formatShortDate(addDays(firstDate, value.round())),
                      style: axisStyle,
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            edge([for (final p in points) FlSpot(p.x, p.low)]),
            edge([for (final p in points) FlSpot(p.x, p.high)]),
            LineChartBarData(
              spots: [for (final p in points) FlSpot(p.x, p.y)],
              isCurved: false,
              color: color,
              barWidth: 3,
              dotData: const FlDotData(show: true),
            ),
          ],
        ),
      ),
    );
  }
}

/// One short, automatically written observation under a chart.
class _Insight extends StatelessWidget {
  const _Insight(
    this.text, {
    this.valueKey = const ValueKey('strength-insight'),
  });

  final String text;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lightbulb_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, key: valueKey, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _WeightDialog extends StatefulWidget {
  const _WeightDialog({required this.initial, required this.unit});

  final double initial;
  final String unit;

  @override
  State<_WeightDialog> createState() => _WeightDialogState();
}

class _WeightDialogState extends State<_WeightDialog> {
  late final TextEditingController _field = TextEditingController(
    text: formatNumber(widget.initial),
  );
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _save() {
    final value = double.tryParse(_field.text.trim().replaceAll(',', '.'));
    if (value == null || !value.isFinite || value <= 0) {
      setState(() => _error = 'Enter your weight');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Log weight'),
      content: TextField(
        key: const ValueKey('weight-field'),
        controller: _field,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          suffixText: widget.unit,
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

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

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            key: ValueKey('stat-$label'),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// One tab: its content, scrolling on its own.
class _Tab extends StatelessWidget {
  const _Tab({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: children);
  }
}

/// The period chips, above all three tabs because they apply to all three.
class _PeriodHeader extends StatelessWidget {
  const _PeriodHeader({required this.range, required this.onChanged});

  final ProgressRange range;
  final ValueChanged<ProgressRange> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: RangeSelector(selected: range, onChanged: onChanged),
  );
}

class _NoWorkouts extends StatelessWidget {
  const _NoWorkouts();

  @override
  Widget build(BuildContext context) => const EmptyState(
    title: 'No workout data yet.',
    message:
        'Complete your first workout to start tracking your '
        'strength and training exposure.',
  );
}

/// How primary and secondary involvement are drawn, the same in both views:
/// primary is solid, secondary is a lighter fill with an outline. They are
/// different things and never share a style.
BoxDecoration _involvementDecoration(
  ColorScheme scheme, {
  required bool secondary,
  double radius = 4,
}) => secondary
    ? BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.25),
        border: Border.all(color: scheme.primary, width: 1.5),
        borderRadius: BorderRadius.circular(radius),
      )
    : BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(radius),
      );

/// What the two styles mean.
class _InvolvementLegend extends StatelessWidget {
  const _InvolvementLegend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget item(bool secondary, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: _involvementDecoration(
            theme.colorScheme,
            secondary: secondary,
            radius: 3,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        item(false, 'Primary (main target)'),
        item(true, 'Secondary (assists)'),
      ],
    );
  }
}

const List<String> _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const List<String> _dayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const double _cellSize = 24;

/// The M T W T F S S heading over the weekly rows.
class _WeekHeader extends StatelessWidget {
  const _WeekHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Spacer(),
          for (final letter in _dayLetters)
            SizedBox(
              width: _cellSize + 4,
              child: Center(child: Text(letter, style: style)),
            ),
        ],
      ),
    );
  }
}

/// One muscle's week: how many days, and which, as primary or secondary.
class _WeekRow extends StatelessWidget {
  const _WeekRow({super.key, required this.days});

  final MuscleDays days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = days.muscle.name;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          MuscleImage(days.muscle, size: 36),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(days.muscle.label, style: theme.textTheme.bodyLarge),
                Text(
                  '${pluralize(days.primaryDays.length, 'day')} primary · '
                  '${pluralize(days.secondaryDays.length, 'day')} secondary',
                  key: ValueKey('week-$name-count'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < 7; i++) _cell(theme, name, i),
        ],
      ),
    );
  }

  /// A day: solid when it was a primary day, outlined when the muscle only
  /// assisted, empty when it was not recorded.
  Widget _cell(ThemeData theme, String name, int day) {
    final String state;
    final BoxDecoration decoration;
    if (days.primaryDays.contains(day)) {
      state = 'primary';
      decoration = _involvementDecoration(
        theme.colorScheme,
        secondary: false,
        radius: 6,
      );
    } else if (days.secondaryDays.contains(day)) {
      state = 'secondary';
      decoration = _involvementDecoration(
        theme.colorScheme,
        secondary: true,
        radius: 6,
      );
    } else {
      state = 'none';
      decoration = BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      );
    }
    return Semantics(
      label: '${_dayNames[day]}: ${state == 'none' ? 'not recorded' : state}',
      child: Container(
        key: ValueKey('cell-$name-$day-$state'),
        width: _cellSize,
        height: _cellSize,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: decoration,
      ),
    );
  }
}

/// The small print for a tab, folded away until asked for.
class _HowCounted extends StatelessWidget {
  const _HowCounted({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text('How is this counted?', style: theme.textTheme.bodyMedium),
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                line,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
