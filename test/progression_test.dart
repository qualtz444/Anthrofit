import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/progression/progression_rules.dart';
import 'package:anthrofit/progression/progression_service.dart';

import 'test_helpers.dart';

/// One completed session for [exerciseId]. Each entry of [sets] is
/// (weight, reps); a null weight means bodyweight.
WorkoutSession _session(
  String id,
  String exerciseId,
  List<(double?, int)> sets, {
  DateTime? on,
  int repMin = 8,
  int repMax = 12,
  List<SetType>? types,
}) {
  final end = on ?? DateTime(2026, 10, 5, 10);
  SetType typeAt(int i) => types == null ? SetType.working : types[i];
  return WorkoutSession(
    id: id,
    workoutId: 'w',
    workoutName: 'Upper A',
    startedAt: end.subtract(const Duration(minutes: 45)),
    completedAt: end,
    exerciseLogs: [
      ExerciseLog(
        id: 'log-$id',
        exerciseId: exerciseId,
        plannedExerciseId: 'pe',
        exerciseName: exerciseId,
        plannedSets: [
          for (var i = 0; i < sets.length; i++)
            PlannedSet(
              setType: typeAt(i),
              targetRepMin: repMin,
              targetRepMax: repMax,
              restSeconds: 90,
            ),
        ],
        sets: [
          for (var i = 0; i < sets.length; i++)
            SetLog(
              setNumber: i + 1,
              setType: typeAt(i),
              weightKg: sets[i].$1,
              reps: sets[i].$2,
              isCompleted: true,
              completedAt: end,
            ),
        ],
      ),
    ],
  );
}

void main() {
  // The exercise catalogue is an asset now, so it has to be loaded.
  useExerciseLibrary();

  const service = ProgressionService();
  const press = 'machine_chest_press';

  group('no history', () {
    test('a first-time exercise suggests nothing and says why', () {
      final s = service.suggestFor(sessions: const [], exerciseId: press);
      expect(s.action, ProgressionAction.noHistory);
      expect(s.suggestedLoadKg, isNull);
      expect(s.suggestedReps, isNull);
      expect(s.hasSuggestion, isFalse);
      expect(s.reason, contains('First time'));
    });

    test('history for a different exercise does not count', () {
      final s = service.suggestFor(
        sessions: [
          _session('a', 'leg_press', [(100.0, 10)]),
        ],
        exerciseId: press,
      );
      expect(s.action, ProgressionAction.noHistory);
    });

    test('warm-up sets alone do not count as history', () {
      final s = service.suggestFor(
        sessions: [
          _session('a', press, [(20.0, 10)], types: const [SetType.warmUp]),
        ],
        exerciseId: press,
      );
      expect(s.action, ProgressionAction.noHistory);
    });
  });

  group('every set at the top of the range', () {
    test('the load goes up and the rep target resets to the bottom', () {
      final s = service.suggestFor(
        sessions: [
          _session('a', press, [(40.0, 12), (40.0, 12), (40.0, 12)]),
        ],
        exerciseId: press,
      );
      expect(s.action, ProgressionAction.increaseLoad);
      // 2.5% of 40 is 1 kg, below the 2.5 kg minimum, so 42.5 kg.
      expect(s.suggestedLoadKg, 42.5);
      expect(s.suggestedReps, 8);
      expect(s.reason, contains('42.5 kg'));
      expect(s.lastPerformance, '40 kg × 12, 12, 12');
    });

    test('a heavy load moves by the percentage, not the minimum', () {
      final s = service.suggestFor(
        sessions: [
          _session('a', press, [(200.0, 12), (200.0, 12)]),
        ],
        exerciseId: press,
      );
      // 2.5% of 200 is 5 kg, rounded to the nearest 2.5.
      expect(s.suggestedLoadKg, 205);
    });

    test('bodyweight work increases reps rather than inventing a load', () {
      final s = service.suggestFor(
        sessions: [
          _session('a', 'push_up', [(null, 12), (null, 12)]),
        ],
        exerciseId: 'push_up',
      );
      expect(s.action, ProgressionAction.increaseLoad);
      expect(s.suggestedLoadKg, isNull);
      expect(s.reason, contains('Add a little resistance'));
    });
  });

  group('working through the range', () {
    test('the load holds and the rep target goes up by one', () {
      final s = service.suggestFor(
        sessions: [
          _session('a', press, [(40.0, 10), (40.0, 9), (40.0, 8)]),
        ],
        exerciseId: press,
      );
      expect(s.action, ProgressionAction.holdLoad);
      expect(s.suggestedLoadKg, 40);
      expect(s.suggestedReps, 11); // best was 10
      expect(s.reason, contains('40 kg × 10, 9, 8'));
    });

    test('the rep target never passes the top of the range', () {
      final s = service.suggestFor(
        sessions: [
          _session('a', press, [(40.0, 12), (40.0, 11), (40.0, 9)]),
        ],
        exerciseId: press,
      );
      expect(s.action, ProgressionAction.holdLoad); // not every set at the top
      expect(s.suggestedReps, 12);
    });

    test('slightly under the range is still holding, not regressing', () {
      // 7 is one below the minimum of 8, inside the tolerance.
      final s = service.suggestFor(
        sessions: [
          _session('a', press, [(40.0, 7), (40.0, 7), (40.0, 7)]),
        ],
        exerciseId: press,
      );
      expect(s.action, ProgressionAction.holdLoad);
      expect(s.suggestedLoadKg, 40);
    });
  });

  group('performance dropping', () {
    test('a clear drop eases the load off', () {
      final s = service.suggestFor(
        sessions: [
          _session('a', press, [(40.0, 5), (40.0, 4), (40.0, 4)]),
        ],
        exerciseId: press,
      );
      expect(s.action, ProgressionAction.reduceLoad);
      expect(s.suggestedLoadKg, 35); // 10% off 40, rounded to 2.5
      expect(s.suggestedReps, 8);
      expect(s.reason, contains('eases'));
    });

    test('a load never rounds below the smallest increment', () {
      final s = service.suggestFor(
        sessions: [
          _session('a', press, [(2.5, 3), (2.5, 3)]),
        ],
        exerciseId: press,
      );
      expect(s.action, ProgressionAction.reduceLoad);
      expect(s.suggestedLoadKg, 2.5);
    });
  });

  group('reading history', () {
    test('the most recent session is the one used', () {
      final sessions = [
        _session('old', press, [
          (40.0, 12),
          (40.0, 12),
        ], on: DateTime(2026, 10, 1)),
        _session('new', press, [
          (45.0, 9),
          (45.0, 8),
        ], on: DateTime(2026, 10, 5)),
      ];
      final s = service.suggestFor(sessions: sessions, exerciseId: press);
      expect(s.action, ProgressionAction.holdLoad);
      expect(s.suggestedLoadKg, 45);
    });

    test('warm-ups are ignored when judging the working sets', () {
      final s = service.suggestFor(
        sessions: [
          _session(
            'a',
            press,
            [(20.0, 10), (40.0, 12), (40.0, 12)],
            types: const [SetType.warmUp, SetType.working, SetType.working],
          ),
        ],
        exerciseId: press,
      );
      expect(s.action, ProgressionAction.increaseLoad);
      expect(s.suggestedLoadKg, 42.5); // from 40, not from the 20 kg warm-up
    });

    test('a Failure set with no rep target just repeats the load', () {
      final s = service.suggestFor(
        sessions: [
          WorkoutSession(
            id: 's',
            workoutId: 'w',
            workoutName: 'W',
            startedAt: DateTime(2026, 10, 5, 9),
            completedAt: DateTime(2026, 10, 5, 10),
            exerciseLogs: [
              ExerciseLog(
                id: 'l',
                exerciseId: press,
                plannedExerciseId: 'pe',
                exerciseName: press,
                plannedSets: const [
                  PlannedSet(setType: SetType.failure, restSeconds: 120),
                ],
                sets: [
                  SetLog(
                    setNumber: 1,
                    setType: SetType.failure,
                    weightKg: 40,
                    reps: 7,
                    isCompleted: true,
                    completedAt: DateTime(2026, 10, 5, 10),
                  ),
                ],
              ),
            ],
          ),
        ],
        exerciseId: press,
      );
      expect(s.action, ProgressionAction.holdLoad);
      expect(s.suggestedLoadKg, 40);
    });

    test('the planned range passed in wins over the recorded one', () {
      final sessions = [
        _session('a', press, [(40.0, 6), (40.0, 6)], repMin: 8, repMax: 12),
      ];
      // Judged against 4-6 instead: every set is at the top.
      final s = service.suggestFor(
        sessions: sessions,
        exerciseId: press,
        planned: const PlannedSet(
          setType: SetType.working,
          targetRepMin: 4,
          targetRepMax: 6,
          restSeconds: 180,
        ),
      );
      expect(s.action, ProgressionAction.increaseLoad);
      expect(s.suggestedReps, 4);
    });

    test('lastLogFor finds the newest usable log', () {
      final sessions = [
        _session('old', press, [(40.0, 10)], on: DateTime(2026, 10, 1)),
        _session('new', press, [(45.0, 10)], on: DateTime(2026, 10, 5)),
      ];
      expect(service.lastLogFor(sessions, press)!.sets.first.weightKg, 45);
      expect(service.lastLogFor(sessions, 'nothing'), isNull);
    });
  });

  group('the increments are configurable', () {
    test('a different rule set gives different numbers', () {
      const gentle = ProgressionService(
        rules: ProgressionRules(
          increasePercent: 10,
          minIncrementKg: 1,
          roundToKg: 1,
        ),
      );
      final s = gentle.suggestFor(
        sessions: [
          _session('a', press, [(40.0, 12), (40.0, 12)]),
        ],
        exerciseId: press,
      );
      expect(s.suggestedLoadKg, 44); // 10% of 40, rounded to 1
    });

    test('rounding never returns zero or a negative load', () {
      const rules = ProgressionRules.standard;
      expect(rules.round(0), 0);
      expect(rules.round(0.4), 2.5);
      expect(rules.round(41), 40);
      expect(rules.round(41.5), 42.5);
    });
  });

  test('a suggestion is only ever a suggestion', () {
    // Nothing in the service writes: it takes sessions and returns advice.
    final before = [
      _session('a', press, [(40.0, 12), (40.0, 12)]),
    ];
    final snapshot = before.first.exerciseLogs.first.sets.first.weightKg;
    service.suggestFor(sessions: before, exerciseId: press);
    expect(before.first.exerciseLogs.first.sets.first.weightKg, snapshot);
  });
}
