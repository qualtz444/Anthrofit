import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/screens/widgets/muscle_image.dart';
import 'package:anthrofit/app.dart';
import 'package:anthrofit/data/exercise_library.dart';
import 'package:anthrofit/data/workout_summary.dart';
import 'package:anthrofit/models/models.dart';

import 'test_helpers.dart';

PlannedExercise _planned(
  String id,
  String exerciseId, {
  int sets = 3,
  int repMin = 8,
  int repMax = 12,
  int rest = 90,
  String note = '',
}) => testPlanned(
  id,
  exerciseId,
  sets: sets,
  repMin: repMin,
  repMax: repMax,
  rest: rest,
  note: note,
);

/// Upper A (Mon + Thu): 4 exercises, 13 sets.
/// Lower A (Tue), Spare (not scheduled).
TrainingProgram _testProgram() {
  return TrainingProgram(
    id: 'prog1',
    name: 'Test Plan',
    workouts: [
      Workout(
        id: 'w-upper',
        name: 'Upper A',
        focus: 'Upper body',
        exercises: [
          _planned('p1', 'machine_chest_press', note: 'Pause at the bottom'),
          _planned(
            'p2',
            'lat_pulldown',
            sets: 4,
            repMin: 6,
            repMax: 10,
            rest: 120,
          ),
          _planned('p3', 'seated_cable_row'),
          _planned('p4', 'machine_shoulder_press'),
        ],
      ),
      Workout(
        id: 'w-lower',
        name: 'Lower A',
        exercises: [_planned('p5', 'leg_press')],
      ),
      Workout(
        id: 'w-spare',
        name: 'Spare',
        exercises: [_planned('p6', 'leg_extension')],
      ),
    ],
    schedule: const [
      ScheduledWorkout(day: Weekday.monday, workoutId: 'w-upper'),
      ScheduledWorkout(day: Weekday.tuesday, workoutId: 'w-lower'),
      ScheduledWorkout(day: Weekday.thursday, workoutId: 'w-upper'),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

void useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> launchApp(WidgetTester tester) async {
  await tester.pumpWidget(AnthrofitApp(authService: FakeAuthService()));
  await tester.pumpAndSettle();
}

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Program tab -> Test Plan -> the workout card with this id.
Future<void> openWorkout(WidgetTester tester, String workoutId) async {
  await tapAndSettle(
    tester,
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Program'),
    ),
  );
  await tapAndSettle(tester, find.text('Test Plan'));
  await tapAndSettle(tester, find.byKey(ValueKey('workout-card-$workoutId')));
}

void main() {
  // The exercise catalogue is an asset now, so it has to be loaded.
  useExerciseLibrary();

  group('primaryMusclesOf', () {
    test('lists primary muscles once each, in first-seen order', () {
      final upper = _testProgram().workouts.first;
      expect(primaryMusclesOf(upper), [
        MuscleGroup.chest,
        MuscleGroup.lats,
        MuscleGroup.upperBack,
        MuscleGroup.frontDelts,
        MuscleGroup.sideDelts,
      ]);
    });

    test('skips exercises that are not in the library', () {
      final workout = Workout(
        id: 'w',
        name: 'W',
        exercises: [_planned('p', 'not_a_real_exercise')],
      );
      expect(primaryMusclesOf(workout), isEmpty);
    });
  });

  group('Data integrity', () {
    test('every planned exercise points at one library definition', () {
      for (final workout in _testProgram().workouts) {
        for (final planned in workout.exercises) {
          final exercise = ExerciseLibrary.byId(planned.exerciseId);
          expect(exercise, isNotNull, reason: planned.exerciseId);
          expect(
            identical(exercise, ExerciseLibrary.byId(planned.exerciseId)),
            isTrue,
          );
        }
      }
    });
  });

  group('Workout Detail', () {
    testWidgets(
      'opens from the program and shows header, summary and exercises',
      (tester) async {
        seedProfileAndPrograms([_testProgram()], activeProgramId: 'prog1');
        useTallScreen(tester);
        await launchApp(tester);
        await openWorkout(tester, 'w-upper');

        // Header
        expect(find.text('Upper A'), findsOneWidget);
        expect(find.text('Upper body'), findsOneWidget);
        expect(find.widgetWithText(Chip, 'Monday'), findsOneWidget);
        expect(find.widgetWithText(Chip, 'Thursday'), findsOneWidget);
        // Muscles worked are pictured in a scrolling row.
        expect(find.widgetWithText(MuscleGallery, 'Chest'), findsOneWidget);
        expect(find.widgetWithText(MuscleGallery, 'Lats'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(MuscleGallery),
            matching: find.byKey(const ValueKey('muscle-image-chest')),
          ),
          findsOneWidget,
        );

        // Summary
        expect(find.text('4 exercises · 13 sets'), findsOneWidget);

        // Classification and primary muscles come from the library
        expect(find.text('Machine · Horizontal Push'), findsOneWidget);
        expect(find.text('Machine · Vertical Pull'), findsOneWidget);
        expect(find.text('Machine · Horizontal Pull'), findsOneWidget);
        expect(find.text('Machine · Vertical Push'), findsOneWidget);
        // Each appears twice: once as a muscles-worked chip, once as the
        // primary-muscle subtitle on its exercise card.
        expect(find.text('Chest'), findsNWidgets(2));
        expect(find.text('Lats'), findsNWidgets(2));
        expect(find.text('Upper Back, Lats'), findsOneWidget);
        expect(find.text('Front Delts, Side Delts'), findsOneWidget);

        // Prescription comes from the planned exercises
        // Every set has its own line: 3 + 3 + 3 sets at 8-12 / 90s, 4 at 6-10 / 120s.
        expect(find.text('8–12 reps · Rest 90s'), findsNWidgets(9));
        expect(find.text('6–10 reps · Rest 120s'), findsNWidgets(4));
        expect(find.text('Working'), findsNWidgets(13));
        expect(find.text('Pause at the bottom'), findsOneWidget);

        // Order matches the plan
        final y = [
          for (final name in [
            'Machine Chest Press',
            'Lat Pulldown',
            'Seated Cable Row',
            'Machine Shoulder Press',
          ])
            tester.getTopLeft(find.text(name)).dy,
        ];
        expect(y[0] < y[1] && y[1] < y[2] && y[2] < y[3], isTrue);
      },
    );

    testWidgets('a workout that is on no day says so', (tester) async {
      seedProfileAndPrograms([_testProgram()], activeProgramId: 'prog1');
      useTallScreen(tester);
      await launchApp(tester);
      await openWorkout(tester, 'w-spare');

      expect(find.text('Spare'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'Monday'), findsNothing);
      expect(find.text('Not scheduled'), findsOneWidget);
      expect(find.text('1 exercise · 3 sets'), findsOneWidget);
    });

    testWidgets('tapping an exercise opens its details', (tester) async {
      seedProfileAndPrograms([_testProgram()], activeProgramId: 'prog1');
      useTallScreen(tester);
      await launchApp(tester);
      await openWorkout(tester, 'w-upper');

      // Tapping an exercise shows what it is. Changing how it is prescribed
      // lives in Edit workout.
      await tapAndSettle(tester, find.text('Machine Chest Press'));

      expect(find.text('Primary muscles'), findsOneWidget);
      expect(find.text('This workout'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Start workout'), findsOneWidget);
      expect(find.text('Edit workout'), findsOneWidget);
      expect(find.text('Primary muscles'), findsNothing);
    });

    testWidgets('Edit workout reuses the editor, saves, and survives restart', (
      tester,
    ) async {
      seedProfileAndPrograms([_testProgram()], activeProgramId: 'prog1');
      useTallScreen(tester);
      await launchApp(tester);
      await openWorkout(tester, 'w-upper');

      await tapAndSettle(tester, find.byTooltip('Rename workout'));
      expect(find.text('Workout name'), findsOneWidget); // the rename dialog
      await tester.enterText(
        find.byKey(const ValueKey('rename-field')),
        'Upper Body A',
      );
      await tapAndSettle(tester, find.text('Save'));

      // Back on Workout Detail with the new name, same exercises, same days.
      expect(find.text('Upper Body A'), findsOneWidget);
      expect(find.text('4 exercises · 13 sets'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'Monday'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'Thursday'), findsOneWidget);

      // Restart: the edit was saved.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await launchApp(tester);
      await openWorkout(tester, 'w-upper');
      expect(find.text('Upper Body A'), findsOneWidget);
      expect(find.text('4 exercises · 13 sets'), findsOneWidget);
    });
  });
}
