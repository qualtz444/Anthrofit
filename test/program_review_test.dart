import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/coaching/program_review.dart';
import 'package:anthrofit/models/models.dart';

import 'test_helpers.dart';

TrainingProgram _program({TrainingGoal? goal}) => TrainingProgram(
  id: 'p1',
  name: 'My Plan',
  goal: goal,
  workouts: [
    Workout(
      id: 'w1',
      name: 'Upper',
      exercises: [testPlanned('pe1', 'barbell_bench_press', rest: 90)],
    ),
  ],
  createdAt: DateTime(2026, 9, 1),
  updatedAt: DateTime(2026, 9, 1),
);

WorkoutSession _done(String id, DateTime when, List<int> reps) =>
    WorkoutSession(
      id: id,
      programId: 'p1',
      workoutId: 'w1',
      workoutName: 'Upper',
      startedAt: when,
      completedAt: when,
      exerciseLogs: [
        ExerciseLog(
          id: 'l$id',
          exerciseId: 'barbell_bench_press',
          plannedExerciseId: 'pe1',
          exerciseName: 'Bench',
          plannedSets: [
            for (final _ in reps)
              const PlannedSet(
                setType: SetType.working,
                targetRepMin: 8,
                targetRepMax: 12,
                restSeconds: 90,
              ),
          ],
          sets: [
            for (var i = 0; i < reps.length; i++)
              SetLog(
                setNumber: i + 1,
                weightKg: 60,
                reps: reps[i],
                isCompleted: true,
                completedAt: when,
              ),
          ],
        ),
      ],
    );

void main() {
  useExerciseLibrary();

  test('same goal and no struggle: nothing to suggest', () {
    final r = reviewProgram(
      program: _program(goal: TrainingGoal.buildMuscle),
      profile: sampleProfile,
      history: const [],
    );
    expect(r.isEmpty, isTrue);
  });

  test('a program without a goal is not compared', () {
    final r = reviewProgram(
      program: _program(),
      profile: sampleProfile,
      history: const [],
    );
    expect(r.proposed, isNull);
  });

  test('goal change: only reps and rest change, ids and sets kept', () {
    final before = _program(goal: TrainingGoal.buildMuscle);
    final r = reviewProgram(
      program: before,
      profile: sampleProfile.copyWith(goal: TrainingGoal.getStronger),
      history: const [],
    );
    final p = r.proposed!;
    expect(p.id, before.id);
    expect(p.goal, TrainingGoal.getStronger);
    final pe = p.workouts.single.exercises.single;
    expect(pe.id, 'pe1');
    expect(pe.plannedSets, hasLength(3));
    // Strength, beginner, main lift: 8–12 reps, 180 s (ACSM rules).
    expect(pe.plannedSets.first.restSeconds, 180);
    expect(r.changes.single.before, '8–12 reps, 90s rest');
  });

  test('two sessions in a row below range flags the exercise', () {
    final r = reviewProgram(
      program: _program(goal: TrainingGoal.buildMuscle),
      profile: sampleProfile,
      history: [
        _done('a', DateTime(2026, 10, 1), [6, 5, 5]),
        _done('b', DateTime(2026, 10, 3), [6, 6, 5]),
      ],
    );
    expect(r.struggling, hasLength(1));
  });

  test('one bad session is not a pattern', () {
    final r = reviewProgram(
      program: _program(goal: TrainingGoal.buildMuscle),
      profile: sampleProfile,
      history: [
        _done('a', DateTime(2026, 10, 1), [10, 9, 8]),
        _done('b', DateTime(2026, 10, 3), [6, 6, 5]),
      ],
    );
    expect(r.struggling, isEmpty);
  });

  test('equipment the profile no longer lists is flagged, not changed', () {
    final r = reviewProgram(
      program: _program(goal: TrainingGoal.buildMuscle),
      profile: sampleProfile.copyWith(
        equipment: [EquipmentAccess.bodyweight],
      ),
      history: const [],
    );
    expect(r.missingEquipment, isNotEmpty);
    expect(r.proposed, isNull);
  });

  test('push / legs / push with Pull unscheduled is flagged', () {
    final ppl = TrainingProgram(
      id: 'ppl',
      name: 'PPL',
      workouts: [
        Workout(
          id: 'push',
          name: 'Push',
          exercises: [testPlanned('a', 'barbell_bench_press')],
        ),
        Workout(
          id: 'pull',
          name: 'Pull',
          exercises: [testPlanned('b', 'lat_pulldown')],
        ),
        Workout(
          id: 'legs',
          name: 'Legs',
          exercises: [testPlanned('c', 'leg_press')],
        ),
      ],
      schedule: const [
        ScheduledWorkout(day: Weekday.monday, workoutId: 'push'),
        ScheduledWorkout(day: Weekday.wednesday, workoutId: 'legs'),
        ScheduledWorkout(day: Weekday.friday, workoutId: 'push'),
      ],
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );
    final r = reviewProgram(
      program: ppl,
      profile: sampleProfile,
      history: const [],
    );
    expect(r.unscheduledWorkouts, ['Pull']);
    expect(r.unplannedMuscles, isNotEmpty);
    expect(r.isEmpty, isFalse);
  });
}
