import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/app.dart';
import 'package:anthrofit/data/exercise_library.dart';
import 'package:anthrofit/data/program_repository.dart';
import 'package:anthrofit/data/ready_made_programs.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/screens/library/add_exercise_actions.dart';

import 'test_helpers.dart';

void main() {
  useExerciseLibrary();

  // ---------------------------------------------------------------------
  group('ready-made programs', () {
    test('every recipe builds from the existing templates and library', () {
      expect(kReadyMadePrograms, isNotEmpty);
      for (final recipe in kReadyMadePrograms) {
        expect(recipe.days, isNotEmpty, reason: recipe.name);
        final workouts = workoutsFor(recipe);
        expect(workouts, isNotEmpty, reason: recipe.name);
        // No second exercise source: everything resolves in the library.
        for (final workout in workouts) {
          for (final planned in workout.exercises) {
            expect(
              ExerciseLibrary.byId(planned.exerciseId),
              isNotNull,
              reason: '${recipe.name}: ${planned.exerciseId}',
            );
          }
        }
      }
    });

    test('building one gives a normal, user-owned program', () {
      final recipe = readyMadeById('ready_push_pull_legs')!;
      final program = programFromReadyMade(recipe);

      expect(program.id, isNotEmpty);
      expect(program.name, 'Push / Pull / Legs');
      expect(program.goal, recipe.goal);
      expect(program.archived, isFalse);
      expect(program.workouts.length, 3);
      expect(program.schedule.length, recipe.days.length);
      // Every scheduled day points at one of its own workouts.
      for (final slot in program.schedule) {
        expect(program.workoutById(slot.workoutId), isNotNull);
      }
    });

    test('two copies of the same recipe share no ids', () {
      final recipe = readyMadeById('ready_upper_lower')!;
      final a = programFromReadyMade(recipe);
      final b = programFromReadyMade(recipe);

      expect(a.id, isNot(b.id));
      final aIds = a.workouts.map((w) => w.id).toSet();
      final bIds = b.workouts.map((w) => w.id).toSet();
      expect(aIds.intersection(bIds), isEmpty);
    });

    test('more days than workouts repeats the workouts in turn', () {
      final recipe = readyMadeById('ready_hypertrophy')!; // 3 workouts, 6 days
      final program = programFromReadyMade(recipe);
      expect(program.schedule.length, 6);
      final used = program.schedule.map((s) => s.workoutId).toSet();
      expect(used.length, 3); // each one twice
    });
  });

  // ---------------------------------------------------------------------
  group('the Library on screen', () {
    void useTallScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> openProgramTab(WidgetTester tester) => tapAndSettle(
      tester,
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Program'),
      ),
    );

    Future<void> launch(WidgetTester tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(AnthrofitApp(authService: FakeAuthService()));
      await tester.pumpAndSettle();
      await openProgramTab(tester);
    }

    testWidgets('it opens, and holds Programs and Exercises', (tester) async {
      seedSavedProfile();
      await launch(tester);

      await tapAndSettle(tester, find.text('Library'));
      expect(find.widgetWithText(AppBar, 'Library'), findsOneWidget);
      expect(find.text('Programs'), findsOneWidget);
      expect(find.text('Exercises'), findsOneWidget);
    });

    testWidgets('Programs lists the ready-made ones', (tester) async {
      seedSavedProfile();
      await launch(tester);
      await tapAndSettle(tester, find.text('Library'));
      await tapAndSettle(tester, find.text('Programs'));

      for (final recipe in kReadyMadePrograms) {
        expect(find.text(recipe.name), findsOneWidget, reason: recipe.name);
      }
    });

    testWidgets('adding one creates a user program, leaving others alone', (
      tester,
    ) async {
      final mine = TrainingProgram(
        id: 'mine',
        name: 'My Plan',
        workouts: [
          Workout(
            id: 'mine-w',
            name: 'Upper A',
            exercises: [testPlanned('mine-p', 'machine_chest_press')],
          ),
        ],
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      seedProfileAndPrograms([mine], activeProgramId: 'mine');
      await launch(tester);

      await tapAndSettle(tester, find.text('Library'));
      await tapAndSettle(tester, find.text('Programs'));
      await tapAndSettle(tester, find.text('Upper / Lower'));

      // The preview shows what it contains, and changes nothing yet.
      expect(find.text('Workouts'), findsOneWidget);
      expect(find.text('Upper'), findsWidgets);

      await tapAndSettle(tester, find.text('Add to my programs'));

      // Straight to the copy, which is a normal program.
      expect(find.widgetWithText(AppBar, 'Upper / Lower'), findsOneWidget);
      expect(find.text('Delete program'), findsOneWidget);

      final saved = await tester.runAsync(() => ProgramRepository().load());
      expect(saved!.programs.length, 2);
      // The user's own program is untouched, and still the active one.
      expect(saved.activeProgramId, 'mine');
      final original = saved.programs.firstWhere((p) => p.id == 'mine');
      expect(original.name, 'My Plan');
      expect(original.workouts.single.exercises.length, 1);
    });

    testWidgets('editing the copy never changes the recipe', (tester) async {
      seedSavedProfile();
      await launch(tester);
      await tapAndSettle(tester, find.text('Library'));
      await tapAndSettle(tester, find.text('Programs'));
      await tapAndSettle(tester, find.text('Full Body Beginner'));
      await tapAndSettle(tester, find.text('Add to my programs'));

      await tapAndSettle(tester, find.byTooltip('Rename program'));
      await tester.enterText(
        find.byKey(const ValueKey('rename-field')),
        'My Full Body',
      );
      await tapAndSettle(tester, find.text('Save'));

      // The recipe is unchanged, so it still offers the original.
      final recipe = readyMadeById('ready_full_body_beginner')!;
      expect(recipe.name, 'Full Body Beginner');
      expect(programFromReadyMade(recipe).name, 'Full Body Beginner');

      final saved = await tester.runAsync(() => ProgramRepository().load());
      expect(saved!.programs.single.name, 'My Full Body');
    });

    testWidgets('the exercise library still searches and opens a detail', (
      tester,
    ) async {
      seedSavedProfile();
      await launch(tester);
      await tapAndSettle(tester, find.text('Library'));
      await tapAndSettle(tester, find.text('Exercises'));

      await tester.enterText(find.byType(TextField).first, 'lat pulldown');
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.text('Lat Pulldown'));
      expect(find.text('Primary muscles'), findsOneWidget);
      expect(find.text('Instructions'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------
  group('adding an exercise from the library', () {
    void useTallScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    /// Program tab -> Library -> Exercises -> Lat Pulldown -> Add to…
    Future<void> openAddSheet(WidgetTester tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(AnthrofitApp(authService: FakeAuthService()));
      await tester.pumpAndSettle();
      await tapAndSettle(
        tester,
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Program'),
        ),
      );
      await tapAndSettle(tester, find.text('Library'));
      await tapAndSettle(tester, find.text('Exercises'));
      await tester.enterText(find.byType(TextField).first, 'lat pulldown');
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.text('Lat Pulldown'));
      await tapAndSettle(tester, find.text('Add to…'));
    }

    testWidgets('it can go into one of the user\'s workouts', (tester) async {
      seedProfileAndPrograms([
        TrainingProgram(
          id: 'mine',
          name: 'My Plan',
          workouts: [
            Workout(
              id: 'mine-w',
              name: 'Upper A',
              exercises: [testPlanned('mine-p', 'machine_chest_press')],
            ),
          ],
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      ], activeProgramId: 'mine');
      await openAddSheet(tester);

      await tapAndSettle(tester, find.text('Add to a program'));
      await tapAndSettle(tester, find.text('Upper A'));

      final saved = await tester.runAsync(() => ProgramRepository().load());
      final workout = saved!.programs.single.workouts.single;
      expect(workout.exercises.length, 2);
      expect(workout.exercises.last.exerciseId, 'lat_pulldown');
      // The existing exercise is untouched.
      expect(workout.exercises.first.exerciseId, 'machine_chest_press');
    });

    testWidgets('with no workouts it says so instead of failing', (
      tester,
    ) async {
      seedSavedProfile();
      await openAddSheet(tester);
      await tapAndSettle(tester, find.text('Add to a program'));
      expect(find.textContaining('no workouts yet'), findsOneWidget);
    });

    testWidgets('it can start a custom workout, which is saved and reusable', (
      tester,
    ) async {
      seedSavedProfile();
      await openAddSheet(tester);

      await tapAndSettle(tester, find.text('Add to a custom workout'));
      // The existing workout editor, pre-filled with the chosen exercise.
      expect(find.text('Lat Pulldown'), findsWidgets);
      await tester.enterText(find.byType(TextFormField).first, 'Back Day');
      await tapAndSettle(tester, find.text('Done'));

      final saved = await tester.runAsync(() => ProgramRepository().load());
      final program = saved!.programs.single;
      expect(program.name, kCustomWorkoutsProgramName);
      expect(program.workouts.single.name, 'Back Day');
      expect(
        program.workouts.single.exercises.single.exerciseId,
        'lat_pulldown',
      );
      // A custom workout is not a program the user is following.
      expect(saved.activeProgramId, program.id); // first ever, so active
    });

    testWidgets('more exercises join the same custom-workout program', (
      tester,
    ) async {
      seedSavedProfile();

      await openAddSheet(tester);
      await tapAndSettle(tester, find.text('Add to a custom workout'));
      await tester.enterText(find.byType(TextFormField).first, 'Back Day');
      await tapAndSettle(tester, find.text('Done'));

      await tester
          .pageBack(); // Back from ExerciseDetailScreen to ExerciseLibraryScreen
      await tester.pumpAndSettle();

      // Search for second exercise directly on ExerciseLibraryScreen.
      await tester.enterText(find.byType(TextField).first, 'leg press');
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.text('Leg Press'));
      await tapAndSettle(tester, find.text('Add to…'));
      await tapAndSettle(tester, find.text('Add to a custom workout'));
      await tester.enterText(find.byType(TextFormField).first, 'Leg Day');
      await tapAndSettle(tester, find.text('Done'));

      final saved = await tester.runAsync(() => ProgramRepository().load());
      final program = saved!.programs.firstWhere(
        (p) => p.name == kCustomWorkoutsProgramName,
      );
      expect(program.workouts.length, 2);
      expect(program.workouts.map((w) => w.name).toList(), [
        'Back Day',
        'Leg Day',
      ]);
    });
  });
}
