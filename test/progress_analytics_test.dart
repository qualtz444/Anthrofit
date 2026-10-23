import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/data/exercise_library.dart';
import 'package:anthrofit/data/training_stats.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/progress/progress_analytics_service.dart';
import 'package:anthrofit/recommendation/proportion_rules.dart';

import 'test_helpers.dart';

final DateTime _today = DateTime(2026, 10, 8, 18);

DateTime _daysAgo(int n) => DateTime(2026, 10, 8 - n, 10);

WorkoutSession _done(String id, int daysAgo, List<ExerciseLog> logs) {
  final end = _daysAgo(daysAgo);
  return WorkoutSession(
    id: id,
    workoutId: 'w',
    workoutName: 'Upper A',
    startedAt: end.subtract(const Duration(minutes: 45)),
    completedAt: end,
    exerciseLogs: logs,
  );
}

/// Started, never finished: must never count.
WorkoutSession _unfinished(String id, int daysAgo, List<ExerciseLog> logs) =>
    WorkoutSession(
      id: id,
      workoutId: 'w',
      workoutName: 'Upper A',
      startedAt: _daysAgo(daysAgo),
      exerciseLogs: logs,
    );

ExerciseLog _press(List<(double?, int)> sets, {List<SetType>? types}) =>
    testLog('machine_chest_press', 'Machine Chest Press', sets, types: types);

ExerciseLog _pulldown(List<(double?, int)> sets) =>
    testLog('lat_pulldown', 'Lat Pulldown', sets);

ExerciseLog _pushUp(List<(double?, int)> sets) =>
    testLog('push_up', 'Push-Up', sets);

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

  // ---------------------------------------------------------------------
  group('Strength Progress', () {
    test('a completed workout counts; an unfinished one does not', () {
      final analytics = ProgressAnalytics(
        sessions: [
          _done('a', 2, [
            _press([(40, 10)]),
          ]),
          _unfinished('b', 1, [
            _press([(100, 10)]),
          ]),
        ],
        today: _today,
      );
      final p = analytics.strength(
        exerciseId: 'machine_chest_press',
        metric: StrengthMetric.heaviestWeight,
        range: ProgressRange.allTime,
      );
      expect(p.points.map((x) => x.value).toList(), [40]);
      expect(p.records.heaviestKg, 40); // the 100 kg was never completed
    });

    test('weight, reps and volume come from the logged sets', () {
      final analytics = ProgressAnalytics(
        sessions: [
          _done('a', 6, [
            _press([(40, 10), (45, 8), (45, 6)]),
          ]),
          _done('b', 1, [
            _press([(50, 8), (50, 7)]),
          ]),
        ],
        today: _today,
      );
      List<double> values(StrengthMetric m) => analytics
          .strength(
            exerciseId: 'machine_chest_press',
            metric: m,
            range: ProgressRange.allTime,
          )
          .points
          .map((p) => p.value)
          .toList();

      expect(values(StrengthMetric.heaviestWeight), [45, 50]);
      expect(values(StrengthMetric.mostReps), [10, 8]);
      expect(values(StrengthMetric.volume), [
        40 * 10 + 45 * 8 + 45 * 6,
        50 * 8 + 50 * 7,
      ]);
    });

    test('warm-ups are left out of every strength figure', () {
      final analytics = ProgressAnalytics(
        sessions: [
          _done('a', 1, [
            _press(
              [(80, 12), (40, 8)],
              types: [SetType.warmUp, SetType.working],
            ),
          ]),
        ],
        today: _today,
      );
      final p = analytics.strength(
        exerciseId: 'machine_chest_press',
        metric: StrengthMetric.heaviestWeight,
        range: ProgressRange.allTime,
      );
      expect(p.points.single.value, 40);
      expect(p.records.heaviestKg, 40);
    });

    test('the latest session is compared with the one before it', () {
      final analytics = ProgressAnalytics(
        sessions: [
          _done('a', 6, [
            _press([(60, 8)]),
          ]),
          _done('b', 1, [
            _press([(65, 8)]),
          ]),
        ],
        today: _today,
      );
      final c = analytics
          .strength(
            exerciseId: 'machine_chest_press',
            metric: StrengthMetric.heaviestWeight,
            range: ProgressRange.allTime,
          )
          .comparison!;
      expect(c.previous.weightKg, 60);
      expect(c.latest.weightKg, 65);
      expect(c.weightChangeKg, 5);
      expect(c.repChange, 0);
    });

    test('a personal record is the heaviest completed set', () {
      final analytics = ProgressAnalytics(
        sessions: [
          _done('a', 20, [
            _press([(70, 5)]),
          ]),
          _done('b', 1, [
            _press([(60, 10)]),
          ]),
        ],
        today: _today,
      );
      final p = analytics.strength(
        exerciseId: 'machine_chest_press',
        metric: StrengthMetric.heaviestWeight,
        range: ProgressRange.week1,
      );
      // The window shows only the recent session...
      expect(p.points.map((x) => x.value).toList(), [60]);
      // ...but a record is a record, whenever it was set.
      expect(p.records.heaviestKg, 70);
      expect(p.records.repsAtHeaviest, 5);
    });

    test('windows include only sessions inside them', () {
      final analytics = ProgressAnalytics(
        sessions: [
          _done('z', 200, [
            _press([(25, 10)]),
          ]),
          _done('a', 100, [
            _press([(30, 10)]),
          ]),
          _done('b', 40, [
            _press([(35, 10)]),
          ]),
          _done('c', 10, [
            _press([(40, 10)]),
          ]),
          _done('d', 3, [
            _press([(45, 10)]),
          ]),
        ],
        today: _today,
      );
      int count(ProgressRange r) => analytics
          .strength(
            exerciseId: 'machine_chest_press',
            metric: StrengthMetric.heaviestWeight,
            range: r,
          )
          .points
          .length;
      expect(count(ProgressRange.week1), 1);
      expect(count(ProgressRange.month1), 2);
      expect(count(ProgressRange.month3), 3);
      expect(count(ProgressRange.month6), 4);
      expect(count(ProgressRange.allTime), 5);
    });

    test('one session is a value, not a trend', () {
      final analytics = ProgressAnalytics(
        sessions: [
          _done('a', 1, [
            _press([(40, 10)]),
          ]),
        ],
        today: _today,
      );
      final p = analytics.strength(
        exerciseId: 'machine_chest_press',
        metric: StrengthMetric.heaviestWeight,
        range: ProgressRange.allTime,
      );
      expect(p.isEmpty, isFalse);
      expect(p.hasTrend, isFalse);
      expect(p.comparison, isNull);
    });

    test('a bodyweight exercise has reps but no weight or volume points', () {
      final analytics = ProgressAnalytics(
        sessions: [
          _done('a', 1, [
            _pushUp([(null, 12)]),
          ]),
        ],
        today: _today,
      );
      List<double> values(StrengthMetric m) => analytics
          .strength(
            exerciseId: 'push_up',
            metric: m,
            range: ProgressRange.allTime,
          )
          .points
          .map((p) => p.value)
          .toList();
      expect(values(StrengthMetric.mostReps), [12]);
      expect(values(StrengthMetric.heaviestWeight), isEmpty); // not zero
      expect(values(StrengthMetric.volume), isEmpty);
    });

    test('the period\'s best weight, best reps and volume', () {
      final analytics = ProgressAnalytics(
        sessions: [
          _done('old', 45, [
            _press([(90, 3)]),
          ]), // outside 30 days
          _done('a', 6, [
            _press([(40, 12), (45, 8)]),
          ]),
          _done('b', 1, [
            _press([(50, 6)]),
          ]),
        ],
        today: _today,
      );
      final p = analytics.strength(
        exerciseId: 'machine_chest_press',
        metric: StrengthMetric.heaviestWeight,
        range: ProgressRange.month1,
      );
      expect(p.bestWeightKg, 50);
      expect(p.bestReps, 12);
      expect(p.volumeKg, 40 * 12 + 45 * 8 + 50 * 6);
      // The record still sees all time.
      expect(p.records.heaviestKg, 90);
    });

    test('a bodyweight exercise has no best weight or volume, not zero', () {
      final p =
          ProgressAnalytics(
            sessions: [
              _done('a', 1, [
                _pushUp([(null, 15)]),
              ]),
            ],
            today: _today,
          ).strength(
            exerciseId: 'push_up',
            metric: StrengthMetric.mostReps,
            range: ProgressRange.allTime,
          );
      expect(p.bestReps, 15);
      expect(p.bestWeightKg, isNull);
      expect(p.volumeKg, isNull);
    });

    test('no history at all is empty, not an error', () {
      final analytics = ProgressAnalytics(sessions: const [], today: _today);
      expect(analytics.hasWorkouts, isFalse);
      expect(analytics.strengthExercisesIn(ProgressRange.allTime), isEmpty);
      final p = analytics.strength(
        exerciseId: 'machine_chest_press',
        metric: StrengthMetric.heaviestWeight,
        range: ProgressRange.allTime,
      );
      expect(p.isEmpty, isTrue);
    });
  });

  // ---------------------------------------------------------------------
  group('Muscle Training', () {
    test('primary muscles are counted per completed set', () {
      // Machine chest press: primary chest; lat pulldown: primary lats.
      final analytics = ProgressAnalytics(
        sessions: [
          _done('a', 1, [
            _press([(40, 10), (40, 10), (40, 10)]),
            _pulldown([(50, 10), (50, 10)]),
          ]),
        ],
        today: _today,
      );
      final byMuscle = {
        for (final e in analytics.exposure(ProgressRange.allTime)) e.muscle: e,
      };
      expect(byMuscle[MuscleGroup.chest]!.primarySets, 3);
      expect(byMuscle[MuscleGroup.lats]!.primarySets, 2);
      expect(byMuscle[MuscleGroup.chest]!.sessions, 1);
    });

    test('secondary muscles are counted separately, never as fractions', () {
      final analytics = ProgressAnalytics(
        sessions: [
          _done('a', 1, [
            _press([(40, 10), (40, 10)]),
          ]),
        ],
        today: _today,
      );
      final exercise = ExerciseLibrary.byId('machine_chest_press')!;
      final exposure = analytics.exposure(ProgressRange.allTime);
      for (final m in exercise.secondaryMuscles) {
        final e = exposure.firstWhere((x) => x.muscle == m);
        expect(e.secondarySets, 2, reason: m.label);
        expect(e.primarySets, 0, reason: m.label);
      }
      // The record behind it all keeps both lists intact.
      final record = analytics.setRecords.first;
      expect(record.primary, exercise.primaryMuscles);
      expect(record.secondary, exercise.secondaryMuscles);
    });

    test('unfinished, warm-up and skipped work does not count', () {
      final skipped = _pulldown([(50, 10)]).copyWith(skipped: true);
      final analytics = ProgressAnalytics(
        sessions: [
          _done('a', 1, [
            _press(
              [(20, 15), (40, 10)],
              types: [SetType.warmUp, SetType.working],
            ),
            skipped,
          ]),
          _unfinished('b', 0, [
            _pulldown([(50, 10)]),
          ]),
        ],
        today: _today,
      );
      final byMuscle = {
        for (final e in analytics.exposure(ProgressRange.allTime)) e.muscle: e,
      };
      expect(byMuscle[MuscleGroup.chest]!.primarySets, 1); // not the warm-up
      expect(byMuscle.containsKey(MuscleGroup.lats), isFalse);
    });

    test('cardio is not counted as muscle work', () {
      // A COMPLETED set, so only the cardio rule can keep it out.
      final analytics = ProgressAnalytics(
        sessions: [
          _done('a', 1, [
            testLog('treadmill_run', 'Treadmill Run', [(null, 1)]),
          ]),
        ],
        today: _today,
      );
      expect(analytics.setRecords, isEmpty);
      expect(analytics.exposure(ProgressRange.allTime), isEmpty);
    });

    test('1W, 1M, 3M and 6M windows each count their own sets', () {
      final analytics = ProgressAnalytics(
        sessions: [
          _done('a', 150, [
            _press([(40, 10)]),
          ]),
          _done('b', 60, [
            _press([(40, 10)]),
          ]),
          _done('c', 25, [
            _press([(40, 10)]),
          ]),
          _done('d', 2, [
            _press([(40, 10)]),
          ]),
        ],
        today: _today,
      );
      int chest(ProgressRange r) => analytics
          .exposure(r)
          .firstWhere((e) => e.muscle == MuscleGroup.chest)
          .primarySets;
      expect(chest(ProgressRange.week1), 1);
      expect(chest(ProgressRange.month1), 2);
      expect(chest(ProgressRange.month3), 3);
      expect(chest(ProgressRange.month6), 4);
    });

    test('the distribution is ordered, and levels are relative', () {
      final analytics = ProgressAnalytics(
        sessions: [
          _done('a', 1, [
            _press(List.filled(9, (40.0, 10))),
            _pulldown(List.filled(4, (50.0, 10))),
          ]),
        ],
        today: _today,
      );
      final exposure = analytics.exposure(ProgressRange.allTime);
      final primary = exposure.where((e) => e.primarySets > 0).toList();
      expect(primary.first.muscle, MuscleGroup.chest); // most sets first
      expect(primary.first.level, ExposureLevel.high);
      // 4 of 9 is under two-thirds but over one-third.
      final lats = exposure.firstWhere((e) => e.muscle == MuscleGroup.lats);
      expect(lats.level, ExposureLevel.moderate);
    });

    test('a weekly trend starts when training starts, with real zeroes', () {
      final analytics = ProgressAnalytics(
        sessions: [
          _done('a', 20, [
            _press([(40, 10), (40, 10)]),
          ]),
          _done('b', 6, [
            _pulldown([(50, 10)]),
          ]), // a week with no chest
          _done('c', 1, [
            _press([(40, 10)]),
          ]),
        ],
        today: _today,
      );
      final weeks = analytics.muscleTrend(
        MuscleGroup.chest,
        ProgressRange.month1,
      );
      expect(weeks.first.sets, 2);
      expect(weeks.map((w) => w.sets), contains(0));
      expect(weeks.last.sets, 1);
      // Nothing before the first workout is padded in as zero.
      expect(weeks.first.weekStart, startOfWeek(_daysAgo(20)));
    });

    test('a trend can follow secondary sets instead of primary', () {
      // Lat pulldown: lats primary, biceps among the secondaries.
      final analytics = ProgressAnalytics(
        sessions: [
          _done('a', 1, [
            _pulldown([(50, 10), (50, 10)]),
          ]),
        ],
        today: _today,
      );
      int total(List<WeeklyMuscleSets> w) =>
          w.fold(0, (sum, x) => sum + x.sets);
      expect(
        total(analytics.muscleTrend(MuscleGroup.lats, ProgressRange.allTime)),
        2,
      );
      expect(
        total(
          analytics.muscleTrend(
            MuscleGroup.biceps,
            ProgressRange.allTime,
            secondary: true,
          ),
        ),
        2,
      );
      // And the two never mix.
      expect(
        total(analytics.muscleTrend(MuscleGroup.biceps, ProgressRange.allTime)),
        0,
      );
    });

    test('frequency counts workouts per week of the period', () {
      final analytics = ProgressAnalytics(
        sessions: [
          _done('a', 12, [
            _press([(40, 10)]),
          ]),
          _done('b', 8, [
            _press([(40, 10)]),
          ]),
          _done('c', 1, [
            _press([(40, 10), (40, 10)]),
          ]),
          _unfinished('d', 0, [
            _press([(40, 10)]),
          ]),
        ],
        today: _today,
      );
      final f = analytics.frequency(ProgressRange.month1);
      expect(f.workouts, 3); // the unfinished one never counts
      expect(f.sets, 4);
      expect(f.weeks, 5); // 30 days, in whole weeks
      expect(f.perWeek, closeTo(0.6, 1e-9));
    });

    test('with no workouts, frequency has no per-week figure', () {
      final f = ProgressAnalytics(
        sessions: const [],
        today: _today,
      ).frequency(ProgressRange.allTime);
      expect(f.workouts, 0);
      expect(f.perWeek, isNull);
    });

    test('no history at all gives no exposure rows, not zeroes', () {
      final analytics = ProgressAnalytics(sessions: const [], today: _today);
      expect(analytics.exposure(ProgressRange.allTime), isEmpty);
      expect(
        analytics.muscleTrend(MuscleGroup.chest, ProgressRange.allTime),
        isEmpty,
      );
    });
  });

  // ---------------------------------------------------------------------
  group('Body Progress', () {
    test('weight readings come from the saved log, oldest first', () {
      final analytics = ProgressAnalytics(
        sessions: const [],
        weightLog: [
          BodyWeightEntry(date: _daysAgo(3), weightKg: 70.2),
          BodyWeightEntry(date: _daysAgo(20), weightKg: 69.8),
          BodyWeightEntry(date: _daysAgo(10), weightKg: 70.4),
        ],
        today: _today,
      );
      final w = analytics.bodyWeight(ProgressRange.allTime);
      expect(w.points.map((p) => p.weightKg).toList(), [69.8, 70.4, 70.2]);
      expect(w.latestKg, 70.2);
      expect(w.changeKg, closeTo(0.4, 1e-9));
    });

    test('windows apply, and one reading is not a trend', () {
      final analytics = ProgressAnalytics(
        sessions: const [],
        weightLog: [
          BodyWeightEntry(date: _daysAgo(20), weightKg: 69.8),
          BodyWeightEntry(date: _daysAgo(3), weightKg: 70.2),
        ],
        today: _today,
      );
      final week = analytics.bodyWeight(ProgressRange.week1);
      expect(week.points.length, 1);
      expect(week.hasTrend, isFalse);
      expect(week.changeKg, isNull); // never "no change" from one reading
      expect(analytics.bodyWeight(ProgressRange.month1).hasTrend, isTrue);
    });

    test('no readings is empty', () {
      final w = ProgressAnalytics(
        sessions: const [],
        today: _today,
      ).bodyWeight(ProgressRange.allTime);
      expect(w.isEmpty, isTrue);
      expect(w.latestKg, isNull);
    });

    test('recording keeps one reading a day and skips repeats', () {
      var log = recordBodyWeight(const [], 70, DateTime(2026, 10, 1, 8));
      log = recordBodyWeight(log, 70, DateTime(2026, 10, 2, 8)); // same value
      expect(log.length, 1);
      log = recordBodyWeight(log, 71, DateTime(2026, 10, 3, 8));
      log = recordBodyWeight(log, 70.5, DateTime(2026, 10, 3, 20)); // same day
      expect(log.map((e) => e.weightKg).toList(), [70, 70.5]);
    });
  });

  // ---------------------------------------------------------------------
  group('Body Analysis comparison', () {
    test('two scans are compared ratio by ratio, as measurements', () {
      final earlier = _scan('a', DateTime(2026, 9, 1), {
        RatioKeys.armToTorso: 0.96,
        RatioKeys.femurToTorso: 1.08,
      });
      final later = _scan('b', DateTime(2026, 10, 1), {
        RatioKeys.armToTorso: 0.97,
        RatioKeys.femurToTorso: 1.06,
      });
      final c = ProgressAnalytics.compareScanMeasurements(earlier, later);
      final arm = c.rows.firstWhere((r) => r.key == RatioKeys.armToTorso);
      expect(arm.previous, 0.96);
      expect(arm.latest, 0.97);
      expect(arm.differenceLabel, '+0.01');
      final femur = c.rows.firstWhere((r) => r.key == RatioKeys.femurToTorso);
      expect(femur.differenceLabel, '-0.02');
    });

    test('a difference is never worded as improvement or regression', () {
      final c = ProgressAnalytics.compareScanMeasurements(
        _scan('a', DateTime(2026, 9, 1), {RatioKeys.armToTorso: 0.96}),
        _scan('b', DateTime(2026, 10, 1), {RatioKeys.armToTorso: 0.99}),
      );
      final words = [
        for (final r in c.rows) r.differenceLabel,
        kScanDifferenceNote,
      ].join(' ').toLowerCase();
      for (final banned in [
        'progress',
        'improve',
        'regress',
        'gain',
        'loss',
        'better',
        'worse',
      ]) {
        expect(words, isNot(contains(banned)), reason: banned);
      }
      // And the note explains why readings differ.
      expect(kScanDifferenceNote, contains('measurement variation'));
      expect(kScanDifferenceNote, contains('camera position'));
    });

    test('a ratio in only one scan is left out, and tiny noise reads 0.00', () {
      final c = ProgressAnalytics.compareScanMeasurements(
        _scan('a', DateTime(2026, 9, 1), {
          RatioKeys.armToTorso: 0.960,
          RatioKeys.femurToTorso: 1.08,
        }),
        _scan('b', DateTime(2026, 10, 1), {RatioKeys.armToTorso: 0.961}),
      );
      expect(c.rows.single.key, RatioKeys.armToTorso);
      expect(c.rows.single.differenceLabel, '0.00');
    });
  });

  group('muscle distribution', () {
    ProgressAnalytics analytics0(List<WorkoutSession> s) =>
        ProgressAnalytics(sessions: s, today: _today);

    MuscleInvolvement involvement(MuscleDistribution d, MuscleGroup m) =>
        d.involved.firstWhere((i) => i.muscle == m);

    test('counts workouts, with primary and secondary kept apart', () {
      final d = analytics0([
        _done('a', 10, [
          _press([(40, 10), (40, 10)]),
        ]),
        _done('b', 3, [
          _press([(45, 8)]),
          _pulldown([(50, 10)]),
        ]),
        _done('c', 1, [
          _pulldown([(55, 8)]),
        ]),
      ]).distribution(ProgressRange.allTime);

      expect(d.workouts, 3);
      // Workouts, not sets: two chest sets in one workout are one workout.
      expect(involvement(d, MuscleGroup.chest).primaryWorkouts, 2);
      expect(involvement(d, MuscleGroup.lats).primaryWorkouts, 2);
      // Triceps only assist the press: secondary, never primary.
      expect(involvement(d, MuscleGroup.triceps).primaryWorkouts, 0);
      expect(involvement(d, MuscleGroup.triceps).secondaryWorkouts, 2);
      // A muscle no logged exercise lists is named, not shown as zero.
      expect(
        d.involved.map((i) => i.muscle),
        isNot(contains(MuscleGroup.calves)),
      );
      expect(d.notRecorded, contains(MuscleGroup.calves));
      expect(d.notRecorded, isNot(contains(MuscleGroup.chest)));
    });

    test('warm-ups and unfinished workouts leave nothing to show', () {
      final d = analytics0([
        _done('a', 2, [
          _press([(20, 10)], types: [SetType.warmUp]),
        ]),
        _unfinished('b', 1, [
          _press([(40, 10)]),
        ]),
      ]).distribution(ProgressRange.allTime);

      expect(d.isEmpty, isTrue);
      expect(d.involved, isEmpty);
    });

    test('the range applies', () {
      final analytics = analytics0([
        _done('old', 40, [
          _press([(40, 10)]),
        ]),
        _done('new', 2, [
          _pulldown([(50, 10)]),
        ]),
      ]);
      final week = analytics.distribution(ProgressRange.week1);
      expect(week.workouts, 1);
      expect(week.involved.map((i) => i.muscle), contains(MuscleGroup.lats));
      expect(
        week.involved.map((i) => i.muscle),
        isNot(contains(MuscleGroup.chest)),
      );
      expect(analytics.distribution(ProgressRange.allTime).workouts, 2);
    });

    test('the insight reports coverage and passes no verdict', () {
      final text = distributionInsight(
        analytics0([
          _done('a', 3, [
            _press([(40, 10)]),
          ]),
          _done('b', 1, [
            _pulldown([(50, 10)]),
          ]),
        ]).distribution(ProgressRange.allTime),
      );

      expect(text, contains('In 2 workouts'));
      expect(text, contains('primary involvement'));
      expect(text, contains('Chest'));
      expect(text, contains('only as secondary'));
      expect(text, contains('Not recorded:'));
      for (final word in ['under', 'over', 'neglect', 'lagging', 'growth']) {
        expect(text.toLowerCase(), isNot(contains(word)), reason: word);
      }
    });
  });

  group('weekly muscle days', () {
    // Today is Thursday 8 Oct 2026; its week starts Monday 5 Oct.
    final thisWeek = DateTime(2026, 10, 5);
    final lastWeek = DateTime(2026, 9, 28);

    ProgressAnalytics analytics0(List<WorkoutSession> s) =>
        ProgressAnalytics(sessions: s, today: _today);

    MuscleDays days(List<MuscleDays> all, MuscleGroup m) =>
        all.firstWhere((d) => d.muscle == m);

    test('a muscle counts once per calendar day', () {
      final all = analytics0([
        _done('morning', 3, [
          _press([(40, 10)]),
        ]), // Monday
        _done('evening', 3, [
          _press([(45, 8)]),
          _pulldown([(50, 10)]),
        ]),
        _done('later', 1, [
          _press([(47.5, 8)]),
        ]), // Wednesday
      ]).muscleDaysIn(thisWeek, ProgressRange.allTime);

      // Monday is 0: three chest workouts, on two days.
      expect(days(all, MuscleGroup.chest).primaryDays, {0, 2});
      expect(days(all, MuscleGroup.lats).primaryDays, {0});
      // Triceps only assisted: secondary days, and no primary ones.
      expect(days(all, MuscleGroup.triceps).primaryDays, isEmpty);
      expect(days(all, MuscleGroup.triceps).secondaryDays, {0, 2});
    });

    test('only the chosen week is counted', () {
      final analytics = analytics0([
        _done('earlier', 10, [
          _press([(40, 10)]),
        ]), // Monday 28 Sep
        _done('now', 1, [
          _pulldown([(50, 10)]),
        ]),
      ]);
      final last = analytics.muscleDaysIn(lastWeek, ProgressRange.allTime);
      expect(last.map((d) => d.muscle), contains(MuscleGroup.chest));
      expect(last.map((d) => d.muscle), isNot(contains(MuscleGroup.lats)));

      final now = analytics.muscleDaysIn(thisWeek, ProgressRange.allTime);
      expect(now.map((d) => d.muscle), contains(MuscleGroup.lats));
      expect(now.map((d) => d.muscle), isNot(contains(MuscleGroup.chest)));
    });

    test('weeks on offer run from the first workout to this week', () {
      final analytics = analytics0([
        _done('a', 10, [
          _press([(40, 10)]),
        ]),
        _done('b', 1, [
          _press([(40, 10)]),
        ]),
      ]);
      expect(analytics.weeksIn(ProgressRange.allTime), [lastWeek, thisWeek]);
      // The last week reaches back to Friday 2 Oct: a part-week is not
      // offered, so only this week is.
      expect(analytics.weeksIn(ProgressRange.week1), [thisWeek]);
    });

    test('no eligible workout, no weeks', () {
      expect(analytics0(const []).weeksIn(ProgressRange.allTime), isEmpty);
    });
  });
}
