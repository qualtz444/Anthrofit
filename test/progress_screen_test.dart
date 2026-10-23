import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/app.dart';
import 'package:anthrofit/community/community_models.dart';
import 'package:anthrofit/core/measurement_labels.dart';
import 'package:anthrofit/core/units.dart';
import 'package:anthrofit/data/profile_repository.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/recommendation/proportion_rules.dart';
import 'package:anthrofit/screens/body_analysis/body_analysis_screen.dart';
import 'package:anthrofit/screens/composition/composition_compare_screen.dart';
import 'package:anthrofit/screens/progress/simple_line_chart.dart';
import 'package:anthrofit/state/measurement_scope.dart';

import 'test_helpers.dart';

final DateTime _now = DateTime.now();
DateTime _daysAgo(int n) => DateTime(_now.year, _now.month, _now.day - n, 10);

WorkoutSession _done(String id, int daysAgo, List<ExerciseLog> logs) =>
    WorkoutSession(
      id: id,
      workoutId: 'w',
      workoutName: 'Upper A',
      startedAt: _daysAgo(daysAgo).subtract(const Duration(minutes: 45)),
      completedAt: _daysAgo(daysAgo),
      exerciseLogs: logs,
    );

ExerciseLog _press(double kg, int reps, {int sets = 1}) => testLog(
  'machine_chest_press',
  'Machine Chest Press',
  List.filled(sets, (kg, reps)),
);

ExerciseLog _pulldown(double kg, int reps, {int sets = 1}) =>
    testLog('lat_pulldown', 'Lat Pulldown', List.filled(sets, (kg, reps)));

/// Chest press four times over three weeks; lat pulldown twice.
List<WorkoutSession> _history() => [
  _done('s1', 20, [_press(40, 10, sets: 3), _pulldown(50, 10, sets: 2)]),
  _done('s2', 13, [_press(42.5, 10, sets: 3)]),
  _done('s3', 6, [_press(45, 8, sets: 3), _pulldown(55, 8, sets: 2)]),
  _done('s4', 1, [_press(47.5, 8, sets: 3)]),
];

CompositionRecord _comp(
  String id,
  int daysAgo, {
  required double fat,
  required double fatMass,
  required double fatFree,
  required double lean,
  double waist = 80,
}) => CompositionRecord(
  id: id,
  takenAt: _daysAgo(daysAgo),
  weightKg: fatMass + fatFree,
  bodyFatPct: fat,
  bodyFatLow: fat - 3,
  bodyFatHigh: fat + 3,
  leanLimbKg: lean,
  fatFreeMassKg: fatFree,
  fatMassKg: fatMass,
  waistCm: waist,
  chestCm: 95,
  hipCm: 94,
  thighCm: 54,
  upperArmCm: 29,
  frameCount: 3,
);

Measurement _scan(String id, DateTime at, Map<String, double> ratios) =>
    Measurement(
      id: id,
      takenAt: at,
      ratios: ratios,
      precision: const {},
      framesUsed: 20,
      framesTotal: 20,
      worstIqrPct: 1,
      captureQuality: 'good',
    );

void main() {
  useExerciseLibrary();

  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openProgress(WidgetTester tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(AnthrofitApp(authService: FakeAuthService()));
    await tester.pumpAndSettle();
    await tapAndSettle(
      tester,
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Progress'),
      ),
    );
  }

  List<double> chartValues(WidgetTester tester, String key) => tester
      .widget<SimpleLineChart>(find.byKey(ValueKey(key)))
      .points
      .map((p) => p.value)
      .toList();

  Finder tab(String label) => find.widgetWithText(Tab, label);

  String stat(WidgetTester tester, String label) =>
      tester.widget<Text>(find.byKey(ValueKey('stat-$label'))).data!;

  // ---------------------------------------------------------------------
  testWidgets('Strength: the workout volume chart and the exercise list', (
    tester,
  ) async {
    seedAppData(sessions: _history());
    await openProgress(tester);

    expect(tab('Strength'), findsOneWidget);
    expect(tab('Muscle Distribution'), findsOneWidget);
    expect(tab('Body Weight'), findsOneWidget);

    // One chart: total workout volume. No per-exercise section any more.
    expect(find.text('Total workout volume'), findsOneWidget);
    expect(find.byKey(const ValueKey('overall-volume-chart')), findsOneWidget);
    expect(find.text('Per Exercise'), findsNothing);
    expect(find.byKey(const ValueKey('strength-exercise')), findsNothing);
    expect(find.byKey(const ValueKey('weight-trend-chart')), findsNothing);
    // It is workload, and is labelled as such.
    expect(find.textContaining('not strength'), findsOneWidget);

    // 2,200 · 1,275 · 1,960 · 1,140: the earlier two average 1,737.5 and the
    // later two 1,550.
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('strength-insight'))).data,
      contains('Average total workout volume fell 11%'),
    );

    // Every exercise is listed and opens its own page.
    expect(
      find.widgetWithText(ListTile, 'Machine Chest Press'),
      findsOneWidget,
    );
    expect(find.widgetWithText(ListTile, 'Lat Pulldown'), findsOneWidget);
  });

  testWidgets('Strength: one workout still draws the chart', (tester) async {
    seedAppData(sessions: [_history().last]);
    await openProgress(tester);
    expect(find.byKey(const ValueKey('overall-volume-chart')), findsOneWidget);
    expect(find.text('Log more sessions to see a trend.'), findsOneWidget);
  });

  testWidgets('share progress defaults to the active section', (tester) async {
    seedAppData(sessions: _history());
    await openProgress(tester);

    Future<void> openShareAndExpect(ShareTopic topic) async {
      await tapAndSettle(tester, find.byKey(const ValueKey('share-progress')));
      final chip = tester.widget<ChoiceChip>(
        find.byKey(ValueKey('share-progress-topic-${topic.name}')),
      );
      expect(chip.selected, isTrue);
      await tapAndSettle(
        tester,
        find.byKey(const ValueKey('share-progress-cancel')),
      );
    }

    await openShareAndExpect(ShareTopic.overall);
    await tapAndSettle(tester, tab('Muscle Distribution'));
    await openShareAndExpect(ShareTopic.muscles);
    await tapAndSettle(tester, tab('Body Weight'));
    await openShareAndExpect(ShareTopic.bodyWeight);
  });

  testWidgets('Exercise page: heaviest weight, sessions, volume, best set', (
    tester,
  ) async {
    seedAppData(sessions: _history());
    await openProgress(tester);
    await tapAndSettle(
      tester,
      find.widgetWithText(ListTile, 'Machine Chest Press'),
    );

    for (final label in [
      'Heaviest weight',
      'Sessions',
      'Total volume',
      'Best set',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // 47.5 kg is the heaviest; 4 sessions; 1,200 + 1,275 + 1,080 + 1,140.
    expect(find.text('47.5 kg'), findsWidgets);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('4,695 kg'), findsOneWidget);
    // Best set: 42.5 × 10 = 425 beats 47.5 × 8 = 380.
    expect(find.text('42.5 kg × 10'), findsOneWidget);

    // The chart and its insight, as the Strength tab used to show.
    expect(chartValues(tester, 'exercise-chart'), [40, 42.5, 45, 47.5]);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('exercise-insight'))).data,
      contains('Top working weight rose from 40 kg'),
    );
    await tapAndSettle(tester, find.text('Reps'));
    expect(chartValues(tester, 'exercise-chart'), [10, 10, 8, 8]);
    await tapAndSettle(tester, find.text('Volume'));
    expect(chartValues(tester, 'exercise-chart').first, 1200);

    // One session at a time, newest first; the arrows step back.
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('session-page'))).data,
      '1 of 4',
    );
    await tapAndSettle(tester, find.byKey(const ValueKey('session-next')));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('session-page'))).data,
      '2 of 4',
    );
  });

  testWidgets('Exercise page: one session still draws the chart', (
    tester,
  ) async {
    seedAppData(sessions: _history());
    await openProgress(tester);
    await tapAndSettle(tester, find.widgetWithText(ListTile, 'Lat Pulldown'));

    // The last week leaves one Lat Pulldown session: a single dot.
    await tapAndSettle(tester, find.text('1W'));
    expect(find.byKey(const ValueKey('exercise-chart')), findsOneWidget);
    expect(chartValues(tester, 'exercise-chart'), [55]);
    expect(
      find.text('Log this exercise in another session to see a trend.'),
      findsOneWidget,
    );
  });

  testWidgets('Strength charts draw the real values, in the chosen units', (
    tester,
  ) async {
    seedAppData(
      sessions: _history(),
      profile: sampleProfile.copyWith(weightUnit: WeightUnit.lb),
    );
    await openProgress(tester);

    List<double> ys() => tester
        .widget<LineChart>(find.byType(LineChart))
        .data
        .lineBarsData
        .first
        .spots
        .map((spot) => spot.y)
        .toList();

    expect(find.text('Total volume (lb·reps)'), findsOneWidget);
    expect(ys().first, closeTo(poundsFromKg(2200), 0.001));
    expect(ys().length, 4);

    await tapAndSettle(
      tester,
      find.widgetWithText(ListTile, 'Machine Chest Press'),
    );
    expect(
      chartValues(tester, 'exercise-chart').first,
      closeTo(poundsFromKg(40), 0.001),
    );
  });

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<IconButton>(find.byKey(ValueKey(key))).onPressed != null;

  testWidgets('Muscle Distribution: the weekly view, what was not trained, '
      'and one insight', (tester) async {
    seedAppData(sessions: _history());
    await openProgress(tester);
    await tapAndSettle(tester, tab('Muscle Distribution'));

    // The weekly view is the chart now; the "x of y workouts" bars are gone.
    expect(find.text('Weekly frequency'), findsOneWidget);
    expect(find.text('Muscle distribution'), findsNothing);
    expect(find.textContaining(' of 4'), findsNothing);

    // Primary and secondary are explained once, for the weekly view.
    expect(find.text('Primary (main target)'), findsOneWidget);
    expect(find.text('Secondary (assists)'), findsOneWidget);

    // Muscles no logged exercise listed are named as not recorded.
    final notRecorded = find.byKey(const ValueKey('dist-not-recorded'));
    expect(
      find.descendant(of: notRecorded, matching: find.text('Calves')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: notRecorded, matching: find.text('Chest')),
      findsNothing,
    );

    // One factual insight, with no verdict on any muscle.
    final insight = text(tester, 'muscle-insight');
    expect(insight, contains('In 4 workouts'));
    expect(insight, contains('primary involvement'));
    expect(insight, contains('Not recorded:'));
    for (final word in [
      'undertrained',
      'overtrained',
      'neglected',
      'lagging',
      'streak',
      'Scheduled',
    ]) {
      expect(find.textContaining(word), findsNothing, reason: word);
    }
  });

  testWidgets('Muscle Distribution follows the chosen range', (tester) async {
    seedAppData(sessions: _history());
    await openProgress(tester);
    await tapAndSettle(tester, tab('Muscle Distribution'));

    // The last week holds the sessions from 6 days and 1 day ago.
    await tapAndSettle(tester, find.text('1W'));
    expect(text(tester, 'muscle-insight'), contains('In 2 workouts'));
  });

  testWidgets('Weekly frequency counts a muscle once per day', (tester) async {
    // Two chest workouts on the same day: one training day, not two.
    seedAppData(
      sessions: [
        _done('morning', 0, [_press(40, 10)]),
        _done('evening', 0, [_press(45, 8)]),
      ],
    );
    await openProgress(tester);
    await tapAndSettle(tester, tab('Muscle Distribution'));

    expect(text(tester, 'week-label'), contains('This week'));
    expect(
      text(tester, 'week-chest-count'),
      '1 day primary · 0 days secondary',
    );
    // Triceps only assisted: a secondary day, never a primary one.
    expect(
      text(tester, 'week-triceps-count'),
      '0 days primary · 1 day secondary',
    );

    // Today's column: solid for the primary muscle, outlined for the one
    // that assisted.
    final today = DateTime.now().weekday - 1; // Monday is 0
    expect(find.byKey(ValueKey('cell-chest-$today-primary')), findsOneWidget);
    expect(
      find.byKey(ValueKey('cell-triceps-$today-secondary')),
      findsOneWidget,
    );
    expect(find.byKey(ValueKey('cell-chest-$today-secondary')), findsNothing);

    // Only one week to show.
    expect(enabled(tester, 'week-prev'), isFalse);
    expect(enabled(tester, 'week-next'), isFalse);
  });

  testWidgets(
    'Weekly frequency: step back to an earlier week, within the range',
    (tester) async {
      seedAppData(
        sessions: [
          _done('earlier', 8, [_press(40, 10)]),
          _done('today', 0, [_pulldown(50, 10)]),
        ],
      );
      await openProgress(tester);
      await tapAndSettle(tester, tab('Muscle Distribution'));

      // This week has the lat pulldown and no chest work.
      expect(find.byKey(const ValueKey('week-lats')), findsOneWidget);
      expect(find.byKey(const ValueKey('week-chest')), findsNothing);

      // Go back to the earliest week: it holds the chest press from 8 days ago.
      for (var i = 0; i < 3 && enabled(tester, 'week-prev'); i++) {
        await tapAndSettle(tester, find.byKey(const ValueKey('week-prev')));
      }
      expect(text(tester, 'week-label'), isNot(contains('This week')));
      expect(
        text(tester, 'week-chest-count'),
        '1 day primary · 0 days secondary',
      );
      expect(enabled(tester, 'week-next'), isTrue);

      // A week of the window the range leaves out is not offered.
      await tapAndSettle(tester, find.text('1W'));
      expect(enabled(tester, 'week-prev'), isFalse);
      expect(text(tester, 'week-label'), contains('This week'));
      expect(find.byKey(const ValueKey('week-chest')), findsNothing);
    },
  );

  testWidgets(
    'with no eligible workout in the range, there is an empty state',
    (tester) async {
      seedAppData(
        sessions: [
          _done('old', 40, [_press(40, 10)]),
        ],
      );
      await openProgress(tester);
      await tapAndSettle(tester, tab('Muscle Distribution'));
      expect(find.byKey(const ValueKey('muscle-insight')), findsOneWidget);

      await tapAndSettle(tester, find.text('1W'));
      expect(find.text('No muscle data in this period.'), findsOneWidget);
      expect(find.byKey(const ValueKey('muscle-insight')), findsNothing);
      expect(find.byKey(const ValueKey('week-label')), findsNothing);
    },
  );

  testWidgets('with no workouts, nothing pretends to be data', (tester) async {
    seedAppData();
    await openProgress(tester);

    expect(find.text('No workout data yet.'), findsOneWidget);
    expect(find.byType(SimpleLineChart), findsNothing);

    await tapAndSettle(tester, tab('Muscle Distribution'));
    expect(find.text('No workout data yet.'), findsOneWidget);
    expect(find.byKey(const ValueKey('stat-Workouts')), findsNothing);

    await tapAndSettle(tester, tab('Body Weight'));
    expect(find.text('No body measurements yet.'), findsOneWidget);
    expect(find.byType(SimpleLineChart), findsNothing);
    // The current weight still shows: it is on the profile.
    expect(stat(tester, 'Latest weight'), '65.5 kg');
  });

  testWidgets('Body Weight: latest weight, history, trend, and logging', (
    tester,
  ) async {
    seedAppData(
      profile: sampleProfile.copyWith(
        weightLog: [
          BodyWeightEntry(date: _daysAgo(20), weightKg: 66),
          BodyWeightEntry(date: _daysAgo(10), weightKg: 65.5),
        ],
      ),
    );
    await openProgress(tester);
    await tapAndSettle(tester, tab('Body Weight'));

    expect(stat(tester, 'Latest weight'), '65.5 kg');
    expect(chartValues(tester, 'body-weight-chart'), [66, 65.5]);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('weight-history')),
        matching: find.text('66 kg'),
      ),
      findsOneWidget,
    );

    await tapAndSettle(tester, find.text('Log weight'));
    await tester.enterText(find.byKey(const ValueKey('weight-field')), '67');
    await tapAndSettle(tester, find.text('Save'));

    expect(stat(tester, 'Latest weight'), '67 kg');
    expect(chartValues(tester, 'body-weight-chart'), [66, 65.5, 67]);
    final saved = await tester.runAsync(() => ProfileRepository().load());
    expect(saved!.weightKg, 67);
    expect(saved.weightLog.last.weightKg, 67);
  });

  testWidgets('one weight reading is a value, not a trend', (tester) async {
    seedAppData(
      profile: sampleProfile.copyWith(
        weightLog: [BodyWeightEntry(date: _daysAgo(2), weightKg: 65.5)],
      ),
    );
    await openProgress(tester);
    await tapAndSettle(tester, tab('Body Weight'));

    expect(find.text('Log more to see a trend.'), findsOneWidget);
    expect(find.byKey(const ValueKey('body-weight-chart')), findsNothing);
    expect(find.byKey(const ValueKey('weight-history')), findsOneWidget);
  });

  testWidgets('scan proportions appear under Body analysis, never Progress', (
    tester,
  ) async {
    seedAppData(sessions: _history());
    await openProgress(tester);

    final store = MeasurementScope.of(
      tester.element(find.byType(NavigationBar)),
      listen: false,
    );
    await store.add(
      _scan('old', _daysAgo(30), {
        RatioKeys.armToTorso: 0.96,
        RatioKeys.femurToTorso: 1.08,
      }),
    );
    await store.add(
      _scan('new', _daysAgo(1), {
        RatioKeys.armToTorso: 0.97,
        RatioKeys.femurToTorso: 1.06,
      }),
    );
    await tester.pumpAndSettle();

    // Not on any Progress tab, in any form.
    for (final name in ['Strength', 'Muscle Distribution', 'Body Weight']) {
      await tapAndSettle(tester, tab(name));
      for (final ratio in kKnownRatios) {
        expect(
          find.text(ratio.name),
          findsNothing,
          reason: '${ratio.name} on $name',
        );
      }
    }

    // Proportions live in Body analysis, which is opened from Home.
    Navigator.of(
      tester.element(find.byType(NavigationBar)),
    ).push(MaterialPageRoute<void>(builder: (_) => const BodyAnalysisScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Current analysis'), findsOneWidget);
    expect(find.text('Scan history'), findsOneWidget);
    // Proportions describe build, so two scans are never compared.
    expect(find.text('Scan comparison'), findsNothing);
    expect(
      find.byKey(const ValueKey('difference-${RatioKeys.armToTorso}')),
      findsNothing,
    );
    for (final banned in ['Improvement', 'Regression', 'Progress', 'Gain']) {
      expect(find.textContaining(banned), findsNothing, reason: banned);
    }
    expect(find.byType(SimpleLineChart), findsNothing);
  });

  testWidgets('Body: latest scan, body fat progress, previous scan', (
    tester,
  ) async {
    seedAppData(
      profile: sampleProfile.copyWith(
        compositionLog: [
          _comp('a', 30, fat: 24, fatMass: 16, fatFree: 50, lean: 22),
          _comp(
            'b',
            2,
            fat: 22,
            fatMass: 14.5,
            fatFree: 51.5,
            lean: 22.5,
            waist: 78,
          ),
        ],
      ),
    );
    await openProgress(tester);
    await tapAndSettle(tester, tab('Body Weight'));

    // The latest scan, laid out like its result screen.
    expect(find.byKey(const ValueKey('latest-scan')), findsOneWidget);
    expect(find.byKey(const ValueKey('body-fat-ring')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('summary-confidence')))
          .data,
      'Confidence: 80% range 19.0% to 25.0%',
    );
    expect(find.text('Fat mass'), findsWidgets);
    expect(find.byKey(const ValueKey('circumferences')), findsOneWidget);

    // Body fat over time: percent on y, one dot per scan.
    expect(find.text('Body fat progress'), findsOneWidget);
    final chart = tester.widget<LineChart>(
      find.descendant(
        of: find.byKey(const ValueKey('body-fat-chart')),
        matching: find.byType(LineChart),
      ),
    );
    expect([for (final s in chart.data.lineBarsData.last.spots) s.y], [24, 22]);

    // No Body analysis link any more: the comparison takes its place.
    expect(find.text('Body analysis'), findsNothing);
    final card = find.byKey(const ValueKey('previous-scan-comparison'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('−2.0 pts')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('−1.5 kg')),
      findsOneWidget,
    );

    // Tapping opens the comparison with a trend for each part.
    await tester.ensureVisible(card);
    await tester.tap(card);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(CompositionCompareScreen), findsOneWidget);
    List<double> trend() => tester
        .widget<SimpleLineChart>(
          find.byKey(const ValueKey('compare-trend-chart')),
        )
        .points
        .map((p) => p.value)
        .toList();
    expect(trend(), [24, 22]);
    await tester.ensureVisible(find.byKey(const ValueKey('trend-waist')));
    await tester.tap(find.byKey(const ValueKey('trend-waist')));
    await tester.pump();
    expect(trend(), [80, 78]);
  });

  testWidgets('Body: one scan still draws body fat and asks for another', (
    tester,
  ) async {
    seedAppData(
      profile: sampleProfile.copyWith(
        compositionLog: [
          _comp('a', 2, fat: 22, fatMass: 14.5, fatFree: 51.5, lean: 22.5),
        ],
      ),
    );
    await openProgress(tester);
    await tapAndSettle(tester, tab('Body Weight'));

    expect(find.byKey(const ValueKey('body-fat-chart')), findsOneWidget);
    expect(
      find.text('Scan again to see a trend. The shaded band is the 80% range.'),
      findsOneWidget,
    );
    expect(
      find.text('Scan again to compare your next scan with this one.'),
      findsOneWidget,
    );
  });
}
