import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/coaching/set_coach.dart';
import 'package:anthrofit/models/models.dart';

/// One exercise log with [planned] sets of 8–12 reps; [done] are the
/// completed (weight, reps) sets, the rest are still to do.
ExerciseLog _log(
  List<(double?, int)> done, {
  int planned = 3,
  double? targetLoad,
  String id = 'log',
}) => ExerciseLog(
  id: id,
  exerciseId: 'bench',
  plannedExerciseId: 'pe',
  exerciseName: 'Bench Press',
  plannedSets: [
    for (var i = 0; i < planned; i++)
      PlannedSet(
        setType: SetType.working,
        targetRepMin: 8,
        targetRepMax: 12,
        targetLoadKg: targetLoad,
        restSeconds: 120,
      ),
  ],
  sets: [
    for (var i = 0; i < planned; i++)
      i < done.length
          ? SetLog(
              setNumber: i + 1,
              weightKg: done[i].$1,
              reps: done[i].$2,
              isCompleted: true,
              completedAt: DateTime(2026, 10, 12),
            )
          : SetLog(setNumber: i + 1),
  ],
);

WorkoutSession _session(String id, ExerciseLog log, {DateTime? on}) {
  final end = on ?? DateTime(2026, 10, 5, 10);
  return WorkoutSession(
    id: id,
    workoutId: 'w',
    workoutName: 'Upper A',
    startedAt: end.subtract(const Duration(minutes: 45)),
    completedAt: end,
    exerciseLogs: [log],
  );
}

void main() {
  group('coaching after a set', () {
    test('inside the range: keep the load', () {
      final msg = coachAfterSet(_log([(40, 10)]), 0)!;
      expect(msg, contains('inside the 8–12 target'));
    });

    test('above the range: keep the load today', () {
      final msg = coachAfterSet(_log([(40, 14)]), 0)!;
      expect(msg, contains('above the 8–12 target'));
      expect(msg, contains('Keep this load for today'));
    });

    test('a drop at the same load is called fatigue across sets, with rest', () {
      final msg = coachAfterSet(_log([(40, 10), (40, 7)]), 1)!;
      expect(msg, contains('from 10 to 7'));
      expect(msg, contains('(120s)'));
    });

    test('below the range with nothing to compare', () {
      final msg = coachAfterSet(_log([(40, 6)]), 0)!;
      expect(msg, contains('below the 8–12 target'));
    });

    test('a set not done, or a warm-up, gets no message', () {
      expect(coachAfterSet(_log([]), 0), isNull);
      final warm = _log([(20, 10)]);
      final w = warm.copyWith(
        sets: [
          warm.sets[0].copyWith(setType: SetType.warmUp),
          ...warm.sets.skip(1),
        ],
      );
      expect(coachAfterSet(w, 0), isNull);
    });

    test('the last set adds the next-time suggestion', () {
      final log = _log([(40, 12), (40, 12), (40, 12)]);
      final msg = coachAfterSet(log, 2, sessionSoFar: _session('now', log))!;
      expect(msg, contains('For next time:'));
    });
  });

  group('autofill', () {
    test('plan targets come first', () {
      final p = proposeTargets(log: _log([], targetLoad: 50), history: []);
      expect(p, hasLength(3));
      expect(p.first.loadKg, 50);
      expect(p.first.loadSource, ProposalSource.plan);
      expect(p.first.reps, 8);
    });

    test('then sets done earlier today, only for sets not yet done', () {
      final p = proposeTargets(log: _log([(42.5, 10)]), history: []);
      expect(p.map((x) => x.setIndex), [1, 2]);
      expect(p.first.loadKg, 42.5);
      expect(p.first.reps, 10);
      expect(p.first.loadSource, ProposalSource.thisWorkout);
    });

    test('then the last session, through the progression rules', () {
      final history = [
        _session('old', _log([(40, 12), (40, 12), (40, 12)], id: 'old')),
      ];
      final p = proposeTargets(log: _log([]), history: history);
      expect(p.first.loadSource, ProposalSource.history);
      expect(p.first.loadKg, greaterThan(40));
    });

    test('no plan load, no sets, no history: no weight is invented', () {
      final p = proposeTargets(log: _log([]), history: []);
      expect(p.every((x) => x.loadKg == null), isTrue);
      // The rep target still comes from the plan.
      expect(p.first.reps, 8);
    });

    test('running it twice proposes the same sets, never more', () {
      final log = _log([(40, 10)]);
      final a = proposeTargets(log: log, history: []);
      final b = proposeTargets(log: log, history: []);
      expect(b.length, a.length);
      expect(log.sets, hasLength(3));
    });

    test('invalid edits are refused', () {
      expect(validateProposal(const SetProposal(setIndex: 0, loadKg: 0)),
          isNotNull);
      expect(validateProposal(const SetProposal(setIndex: 0, reps: 0)),
          isNotNull);
      expect(
        validateProposal(const SetProposal(setIndex: 0, loadKg: 40, reps: 8)),
        isNull,
      );
    });
  });

  group('situation check', () {
    test('easy at the top of the range: one load step up, back to the bottom', () {
      final a = adjustNextSet(_log([(40, 12)]), 0, SetFeel.easy);
      expect(a.setIndex, 1);
      expect(a.loadKg, greaterThan(40));
      expect(a.reps, 8);
    });

    test('easy inside the range: same load, one more rep', () {
      final a = adjustNextSet(_log([(40, 9)]), 0, SetFeel.easy);
      expect(a.loadKg, 40);
      expect(a.reps, 10);
    });

    test('just right: same load and reps', () {
      final a = adjustNextSet(_log([(40, 10)]), 0, SetFeel.justRight);
      expect(a.loadKg, 40);
      expect(a.reps, 10);
    });

    test('hard and below the range: one load step down', () {
      final a = adjustNextSet(_log([(40, 6)]), 0, SetFeel.hard);
      expect(a.loadKg, lessThan(40));
      expect(a.reps, 8);
    });

    test('pain stops the exercise and suggests nothing', () {
      final a = adjustNextSet(_log([(40, 10)]), 0, SetFeel.pain);
      expect(a.stop, isTrue);
      expect(a.setIndex, isNull);
      expect(a.loadKg, isNull);
    });

    test('after the last set there is no next set to change', () {
      final a = adjustNextSet(
        _log([(40, 10), (40, 10), (40, 10)]),
        2,
        SetFeel.easy,
      );
      expect(a.setIndex, isNull);
    });

    test('reps never leave the planned range', () {
      final a = adjustNextSet(_log([(40, 12)], planned: 3), 0, SetFeel.justRight);
      expect(a.reps, lessThanOrEqualTo(12));
    });
  });
}
