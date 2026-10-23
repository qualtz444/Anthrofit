import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/app.dart';
import 'package:anthrofit/models/models.dart';

import 'test_helpers.dart';

void main() {
  // The exercise catalogue is an asset now, so it has to be loaded.
  useExerciseLibrary();

  testWidgets('Shell shows the four baseline tabs once a profile exists', (
    tester,
  ) async {
    seedSavedProfile();
    await tester.pumpWidget(AnthrofitApp(authService: FakeAuthService()));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Progress'), findsWidgets);
    expect(find.text('Program'), findsWidgets);
    expect(find.text('Profile'), findsWidgets);
  });

  test('Program survives a JSON round trip', () {
    final planned = testPlanned('pe1', 'machine_chest_press');
    final program = TrainingProgram(
      id: 'p1',
      name: '4-Day Hypertrophy',
      workouts: [
        Workout(id: 'w1', name: 'Upper A', exercises: [planned]),
      ],
      schedule: const [ScheduledWorkout(day: Weekday.monday, workoutId: 'w1')],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    final restored = TrainingProgram.fromJson(program.toJson());
    expect(restored.workoutForDay(Weekday.monday)?.name, 'Upper A');
    final restoredSets = restored.workouts.first.exercises.first.plannedSets;
    expect(restoredSets.length, 3);
    expect(restoredSets.first.repRangeLabel, '8–12');
  });

  test('Logging does not change the plan', () {
    final planned = testPlanned('pe1', 'machine_chest_press');
    final log = ExerciseLog.fromPlanned(planned, 'Machine Chest Press');
    final updated = log.copyWith(
      sets: [
        log.sets[0].copyWith(weightKg: 40, reps: 10, isCompleted: true),
        ...log.sets.skip(1),
      ],
    );

    expect(updated.sets.first.weightKg, 40);
    expect(updated.sets.first.reps, 10);
    expect(updated.sets.first.isCompleted, isTrue);
    expect(planned.plannedSets.length, 3);
    expect(planned.plannedSets.first.targetRepMin, 8);
  });
}
