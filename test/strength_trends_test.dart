import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/core/units.dart';
import 'package:anthrofit/data/training_stats.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/progress/progress_analytics_service.dart';

import 'test_helpers.dart';

final DateTime _today = DateTime(2026, 10, 8, 18);

DateTime _daysAgo(int n) => DateTime(2026, 10, 8 - n, 10);

WorkoutSession _done(String id, int daysAgo, List<ExerciseLog> logs) =>
    WorkoutSession(
      id: id,
      workoutId: 'w',
      workoutName: 'Upper A',
      startedAt: _daysAgo(daysAgo).subtract(const Duration(minutes: 45)),
      completedAt: _daysAgo(daysAgo),
      exerciseLogs: logs,
    );

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

ProgressAnalytics _analytics(List<WorkoutSession> sessions) =>
    ProgressAnalytics(sessions: sessions, today: _today);

void main() {
  useExerciseLibrary();

  group('exercise sessions', () {
    test('a session is its top set and its volume, warm-ups left out', () {
      final sessions = _analytics([
        _done('a', 3, [
          _press(
            [(20, 12), (40, 10), (45, 8), (45, 9)],
            types: [
              SetType.warmUp,
              SetType.working,
              SetType.working,
              SetType.failure,
            ],
          ),
        ]),
      ]).exerciseTrend('machine_chest_press', ProgressRange.allTime);

      expect(sessions, hasLength(1));
      // Heaviest set, and of the two at 45 kg the one with more reps.
      expect(sessions.single.topWeightKg, 45);
      expect(sessions.single.topReps, 9);
      // 40×10 + 45×8 + 45×9. The warm-up adds nothing.
      expect(sessions.single.volumeKg, 1165);
      expect(sessions.single.sets, 3);
    });

    test('zero reps, unfinished sessions and other exercises never count', () {
      final sessions = _analytics([
        _done('a', 5, [
          _press([(40, 10), (60, 0)]), // a 60 kg set with no reps is not a set
          _pulldown([(50, 10)]),
        ]),
        _unfinished('b', 1, [
          _press([(100, 10)]),
        ]),
      ]).exerciseTrend('machine_chest_press', ProgressRange.allTime);

      expect(sessions, hasLength(1));
      expect(sessions.single.topWeightKg, 40);
      expect(sessions.single.sets, 1);
    });

    test('sessions come oldest first, and the range applies', () {
      final analytics = _analytics([
        _done('new', 2, [
          _press([(45, 8)]),
        ]),
        _done('old', 40, [
          _press([(40, 8)]),
        ]),
        _done('mid', 10, [
          _press([(42.5, 8)]),
        ]),
      ]);
      List<double?> weights(ProgressRange r) => [
        for (final s in analytics.exerciseTrend('machine_chest_press', r))
          s.topWeightKg,
      ];
      expect(weights(ProgressRange.allTime), [40, 42.5, 45]);
      expect(weights(ProgressRange.month1), [42.5, 45]);
      expect(weights(ProgressRange.week1), [45]);
    });

    test('bodyweight work has reps and no weight or volume', () {
      final sessions = _analytics([
        _done('a', 3, [
          _pushUp([(null, 15), (null, 12)]),
        ]),
      ]).exerciseTrend('push_up', ProgressRange.allTime);

      expect(sessions.single.topWeightKg, isNull);
      expect(sessions.single.topReps, 15);
      expect(sessions.single.volumeKg, 0);
    });
  });

  group('workout volume', () {
    test('adds every working set of every exercise in a session', () {
      final volumes = _analytics([
        _done('a', 6, [
          _press(
            [(40, 10), (20, 15)],
            types: [SetType.working, SetType.warmUp],
          ),
          _pulldown([(50, 10)]),
        ]),
        _done('b', 1, [
          _press([(45, 8)]),
        ]),
      ]).workoutVolume(ProgressRange.allTime);

      expect(volumes.map((v) => v.volumeKg), [400 + 500, 360]);
      expect(volumes.map((v) => v.sets), [2, 1]);
    });

    test('workouts on the same day are one day, not compared', () {
      final volumes = _analytics([
        _done('quick', 1, [
          _press([(40, 10)]),
        ]),
        _done('program', 1, [
          _pulldown([(50, 10)]),
        ]),
      ]).workoutVolume(ProgressRange.allTime);

      expect(volumes, hasLength(1));
      expect(volumes.single.volumeKg, 400 + 500);
      expect(volumes.single.sets, 2);
      expect(volumes.single.workouts, 2);
    });

    test('a session with nothing weighted, or unfinished, is left out', () {
      final volumes = _analytics([
        _done('a', 4, [
          _pushUp([(null, 15)]),
        ]),
        _unfinished('b', 2, [
          _press([(40, 10)]),
        ]),
        _done('c', 1, [
          _press([(40, 10)]),
        ]),
      ]).workoutVolume(ProgressRange.allTime);

      expect(volumes, hasLength(1));
      expect(volumes.single.volumeKg, 400);
    });
  });

  group('insights', () {
    ExerciseSession session(
      int daysAgo,
      double? kg,
      int reps, {
      double volume = 0,
      int sets = 3,
    }) => ExerciseSession(
      date: _daysAgo(daysAgo),
      topWeightKg: kg,
      topReps: reps,
      volumeKg: volume,
      sets: sets,
    );

    test('weight: first against latest, with the values', () {
      final text = weightInsight([
        session(14, 40, 8),
        session(7, 42.5, 8),
        session(0, 45, 8),
      ], WeightUnit.kg);
      expect(text, contains('rose from 40 kg (Sep 24) to 45 kg (Oct 8)'));
      expect(text, contains('+5 kg over 3 sessions'));
    });

    test('weight: steady and falling are said plainly', () {
      expect(
        weightInsight([session(7, 40, 8), session(0, 40, 8)], WeightUnit.kg),
        contains('stayed at 40 kg'),
      );
      expect(
        weightInsight([session(7, 45, 8), session(0, 40, 8)], WeightUnit.kg),
        contains('fell from 45 kg'),
      );
    });

    test('reps are compared only at the same load', () {
      final same = repInsight([
        session(14, 45, 8),
        session(7, 50, 6),
        session(0, 45, 10),
      ], WeightUnit.kg);
      expect(same, contains('At 45 kg'));
      expect(same, contains('rose from 8 (Sep 24) to 10 (Oct 8)'));

      final changed = repInsight([
        session(7, 45, 8),
        session(0, 50, 8),
      ], WeightUnit.kg);
      expect(changed, contains("can't be compared"));
      expect(changed, contains('50 kg'));
    });

    test('reps at bodyweight compare with other bodyweight sessions', () {
      final text = repInsight([
        session(7, null, 12),
        session(0, null, 15),
      ], WeightUnit.kg);
      expect(text, contains('At bodyweight'));
      expect(text, contains('rose from 12'));
    });

    test('volume: a few sessions compare first with latest', () {
      final text = volumeInsight(
        [
          (date: _daysAgo(7), volumeKg: 1000.0),
          (date: _daysAgo(0), volumeKg: 1200.0),
        ],
        WeightUnit.kg,
        noun: 'session volume',
      );
      expect(text, contains('Session volume rose 20%'));
      expect(text, contains('1,000 kg·reps'));
      expect(text, contains('1,200 kg·reps'));
    });

    test('volume: four or more compare the earlier half with the later', () {
      final text = volumeInsight(
        [
          (date: _daysAgo(21), volumeKg: 1000.0),
          (date: _daysAgo(14), volumeKg: 1000.0),
          (date: _daysAgo(7), volumeKg: 1200.0),
          (date: _daysAgo(0), volumeKg: 1400.0),
        ],
        WeightUnit.kg,
        noun: 'total workout volume',
      );
      expect(text, contains('Average total workout volume rose 30%'));
      expect(text, contains('first 2 sessions'));
      expect(text, contains('latest 2 sessions'));
    });

    test('volume: a tiny change is "about the same"', () {
      final text = volumeInsight(
        [
          (date: _daysAgo(7), volumeKg: 1000.0),
          (date: _daysAgo(0), volumeKg: 1010.0),
        ],
        WeightUnit.kg,
        noun: 'session volume',
      );
      expect(text, contains('about the same'));
    });

    test('too little data says more comparable sessions are needed', () {
      expect(
        weightInsight([session(0, 40, 8)], WeightUnit.kg),
        kNeedMoreSessions,
      );
      expect(repInsight(const [], WeightUnit.kg), kNeedMoreSessions);
      expect(
        volumeInsight(
          [(date: _daysAgo(0), volumeKg: 1000.0)],
          WeightUnit.kg,
          noun: 'session volume',
        ),
        kNeedMoreSessions,
      );
    });

    test('values read in the chosen units, and never claim strength', () {
      final text = weightInsight([
        session(7, 40, 8),
        session(0, 45, 8),
      ], WeightUnit.lb);
      expect(text, contains('lb'));
      expect(text, isNot(contains(' kg')));

      final volume = volumeInsight(
        [
          (date: _daysAgo(7), volumeKg: 1000.0),
          (date: _daysAgo(0), volumeKg: 1500.0),
        ],
        WeightUnit.kg,
        noun: 'session volume',
      );
      expect(volume.toLowerCase(), isNot(contains('strength')));
      expect(volume.toLowerCase(), isNot(contains('stronger')));
    });
  });
}
