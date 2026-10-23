import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/data/session_report.dart';
import 'package:anthrofit/models/models.dart';

// The Workout summary's numbers, worked out from what was logged.

ExerciseLog _log(List<SetLog> sets) => ExerciseLog(
  id: 'l',
  exerciseId: 'lateral_raise',
  plannedExerciseId: 'p',
  exerciseName: 'Lateral raise',
  plannedSets: const [],
  sets: sets,
);

SetLog _done(int n, int reps, double? kg, {int? rest, SetType? type}) =>
    SetLog(
      setNumber: n,
      setType: type ?? SetType.working,
      reps: reps,
      weightKg: kg,
      isCompleted: true,
      restBeforeSeconds: rest,
    );

void main() {
  test('a row: sets × reps, weight and volume', () {
    final r = exerciseReport(
      _log([
        _done(1, 10, 15),
        _done(2, 12, 15),
        const SetLog(setNumber: 3, skipped: true),
      ]),
    );
    expect(r.setsDone, 2);
    expect(r.setsSkipped, 1);
    expect(r.setsByReps, '2 × 10–12');
    expect(r.minWeightKg, 15);
    expect(r.maxWeightKg, 15);
    expect(r.volumeKg, 15 * 10 + 15 * 12);
  });

  test('warm-ups count as sets done but not toward volume', () {
    final r = exerciseReport(
      _log([_done(1, 10, 10, type: SetType.warmUp), _done(2, 10, 20)]),
    );
    expect(r.setsDone, 2);
    expect(r.volumeKg, 200);
    expect(r.minWeightKg, 10);
    expect(r.maxWeightKg, 20);
  });

  test('bodyweight work has no weight and no volume', () {
    final r = exerciseReport(_log([_done(1, 12, null), _done(2, 12, null)]));
    expect(r.setsByReps, '2 × 12');
    expect(r.minWeightKg, isNull);
    expect(r.volumeKg, 0);
  });

  test('an exercise with only skipped sets did nothing', () {
    final r = exerciseReport(
      _log([const SetLog(setNumber: 1, skipped: true)]),
    );
    expect(r.nothingDone, isTrue);
  });

  test('calories: 3.5 METs × body weight × hours', () {
    expect(estimatedKcal(const Duration(hours: 1), 70), closeTo(245, 1e-9));
    expect(estimatedKcal(const Duration(minutes: 30), 60), closeTo(105, 1e-9));
    expect(estimatedKcal(const Duration(hours: 1), null), isNull);
  });

  test('time between sets averages only the sets that measured it', () {
    final session = WorkoutSession(
      id: 's',
      workoutId: 'w',
      workoutName: 'Upper A',
      startedAt: DateTime(2026, 10, 14),
      exerciseLogs: [
        _log([
          _done(1, 10, 15), // first set: nothing to measure from
          _done(2, 10, 15, rest: 90),
          _done(3, 10, 15, rest: 150),
        ]),
      ],
    );
    expect(averageTimeBetweenSets(session), const Duration(seconds: 120));
    expect(
      averageTimeBetweenSets(
        WorkoutSession(
          id: 's',
          workoutId: 'w',
          workoutName: 'x',
          startedAt: DateTime(2026),
        ),
      ),
      isNull,
    );
  });

  test('the measured time survives a save and load', () {
    final set = SetLog.fromJson(_done(2, 10, 15, rest: 95).toJson());
    expect(set.restBeforeSeconds, 95);
  });
}
