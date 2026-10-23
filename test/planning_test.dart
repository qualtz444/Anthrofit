import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/app.dart';
import 'package:anthrofit/core/list_utils.dart';
import 'package:anthrofit/data/program_repository.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/state/program_controller.dart';

import 'test_helpers.dart';

TrainingProgram _program(String id, String name) {
  return TrainingProgram(
    id: id,
    name: name,
    workouts: [
      Workout(
        id: 'w-$id',
        name: 'Upper A',
        exercises: [
          testPlanned(
            'pe-$id',
            'machine_chest_press',
            note: 'Pause at the bottom',
          ),
        ],
      ),
    ],
    schedule: [ScheduledWorkout(day: Weekday.monday, workoutId: 'w-$id')],
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

Future<void> openProgramTab(WidgetTester tester) async {
  await tapAndSettle(
    tester,
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Program'),
    ),
  );
}

/// Program tab -> Create program (Custom) -> Add workout (Custom).
/// Leaves you in the workout editor with a blank name and no exercises.
Future<void> openNewWorkoutEditor(WidgetTester tester) async {
  await openProgramTab(tester);
  await tapAndSettle(tester, find.byKey(const ValueKey('create-program')));
  await completeProgramSetup(tester);
  await tapAndSettle(tester, find.text('Add workout'));
  await tapAndSettle(tester, find.text('Custom')); // workout type
}

/// In the workout editor: pick Machine Chest Press from the library.
Future<void> addMachineChestPress(WidgetTester tester) async {
  await tapAndSettle(tester, find.text('Add exercises'));
  await tester.tap(find.text('Machine Chest Press'));
  await tester.pump();
  await tapAndSettle(tester, find.text('Add 1 exercise'));
}

void main() {
  // The exercise catalogue is an asset now, so it has to be loaded.
  useExerciseLibrary();

  group('reorderList', () {
    test('moves an item to the end', () {
      expect(reorderList(['a', 'b', 'c'], 0, 2), ['b', 'c', 'a']);
    });

    test('moves an item to the front', () {
      expect(reorderList(['a', 'b', 'c'], 2, 0), ['c', 'a', 'b']);
    });

    test('does not change the original list', () {
      final original = ['a', 'b', 'c'];
      reorderList(original, 0, 2);
      expect(original, ['a', 'b', 'c']);
    });
  });

  group('PlannedExercise.withDefaults', () {
    test('uses the spec example values', () {
      final p = PlannedExercise.withDefaults('machine_chest_press');
      expect(p.exerciseId, 'machine_chest_press');
      expect(p.id, isNotEmpty);
      expect(p.plannedSets.length, 3);
      for (final s in p.plannedSets) {
        expect(s.setType, SetType.working);
        expect(s.targetRepMin, 8);
        expect(s.targetRepMax, 12);
        expect(s.targetLoadKg, isNull);
        expect(s.restSeconds, 90);
      }
      expect(p.note, '');
    });
  });

  group('ProgramRepository', () {
    test(
      'saves and loads programs, workouts, exercises and active id',
      () async {
        seedNoProfile();
        final repo = ProgramRepository();
        await repo.save(
          ProgramData(programs: [_program('p1', 'One')], activeProgramId: 'p1'),
        );

        final loaded = await repo.load();
        expect(loaded.activeProgramId, 'p1');
        final program = loaded.programs.single;
        expect(program.name, 'One');
        expect(program.workoutForDay(Weekday.monday)?.name, 'Upper A');
        final planned = program.workouts.single.exercises.single;
        expect(planned.exerciseId, 'machine_chest_press');
        expect(planned.plannedSets.length, 3);
        expect(planned.plannedSets.first.repRangeLabel, '8–12');
        expect(planned.note, 'Pause at the bottom');
      },
    );

    test('nothing saved loads as empty', () async {
      seedNoProfile();
      final loaded = await ProgramRepository().load();
      expect(loaded.programs, isEmpty);
      expect(loaded.activeProgramId, isNull);
    });
  });

  group('ProgramController', () {
    Future<ProgramController> freshController() async {
      seedNoProfile();
      final c = ProgramController(ProgramRepository());
      await c.load();
      return c;
    }

    test(
      'first saved program becomes active, later ones do not replace it',
      () async {
        final c = await freshController();
        await c.saveProgram(_program('p1', 'One'));
        expect(c.activeProgramId, 'p1');
        await c.saveProgram(_program('p2', 'Two'));
        expect(c.activeProgramId, 'p1');
        expect(c.programs.length, 2);
      },
    );

    test('saving an existing id replaces that program', () async {
      final c = await freshController();
      await c.saveProgram(_program('p1', 'One'));
      await c.saveProgram(_program('p1', 'Renamed'));
      expect(c.programs.length, 1);
      expect(c.programById('p1')?.name, 'Renamed');
    });

    test('setActiveProgram switches the active program', () async {
      final c = await freshController();
      await c.saveProgram(_program('p1', 'One'));
      await c.saveProgram(_program('p2', 'Two'));
      await c.setActiveProgram('p2');
      expect(c.activeProgram?.name, 'Two');
    });

    test('deleting the active program leaves NO program active', () async {
      final c = await freshController();
      await c.saveProgram(_program('p1', 'One'));
      await c.saveProgram(_program('p2', 'Two'));

      await c.deleteProgram('p1');
      expect(c.activeProgramId, isNull); // p2 is NOT activated for the user
      expect(c.programs.single.id, 'p2');

      await c.deleteProgram('p2');
      expect(c.programs, isEmpty);
      expect(c.activeProgram, isNull);
    });

    test('programs and the active choice survive a reload', () async {
      final c = await freshController();
      await c.saveProgram(_program('p1', 'One'));
      await c.saveProgram(_program('p2', 'Two'));
      await c.setActiveProgram('p2');

      final reloaded = ProgramController(ProgramRepository());
      await reloaded.load();
      expect(reloaded.programs.length, 2);
      expect(reloaded.activeProgram?.name, 'Two');
    });
  });

  group('Planning screens', () {
    testWidgets('Program tab shows an empty state with a create button', (
      tester,
    ) async {
      seedSavedProfile();
      useTallScreen(tester);
      await launchApp(tester);
      await openProgramTab(tester);

      // New here: a scan first, with setting one up still possible.
      expect(find.byKey(const ValueKey('first-scan-cta')), findsOneWidget);
      expect(find.text('Run your first scan'), findsOneWidget);
      expect(find.text('Create program'), findsNothing);
      expect(find.byKey(const ValueKey('create-program')), findsOneWidget);
      expect(find.text('No program yet.'), findsOneWidget);
      expect(find.text('Manage exercises'), findsOneWidget);
    });

    testWidgets('a program with no days or workouts cannot be saved', (
      tester,
    ) async {
      seedSavedProfile();
      useTallScreen(tester);
      await launchApp(tester);
      await openProgramTab(tester);
      await tapAndSettle(tester, find.byKey(const ValueKey('create-program')));
      await completeProgramSetup(tester);

      // Custom arrives with a default name and no workouts.
      await tapAndSettle(tester, find.text('Save program'));

      expect(find.text('Choose at least one training day'), findsOneWidget);
      expect(find.text('Add at least one workout'), findsOneWidget);
      expect(find.text('New program'), findsOneWidget); // still on the planner

      // Clearing the name blocks saving too.
      await tester.enterText(find.byType(TextFormField).first, '');
      await tapAndSettle(tester, find.text('Save program'));
      expect(find.text('Enter a program name'), findsOneWidget);
    });

    testWidgets('a workout needs a name and at least one exercise', (
      tester,
    ) async {
      seedSavedProfile();
      useTallScreen(tester);
      await launchApp(tester);
      await openNewWorkoutEditor(tester);

      await tapAndSettle(tester, find.text('Done'));

      expect(find.text('Enter a workout name'), findsOneWidget);
      expect(find.text('Add at least one exercise'), findsOneWidget);
      expect(find.text('New workout'), findsOneWidget); // still in the editor
    });

    testWidgets('added exercises get default values that can be edited', (
      tester,
    ) async {
      seedSavedProfile();
      useTallScreen(tester);
      await launchApp(tester);
      await openNewWorkoutEditor(tester);
      await addMachineChestPress(tester);

      expect(find.text('Machine Chest Press'), findsOneWidget);
      expect(find.text('3 sets'), findsOneWidget);

      // Edit it: three Working sets, four boxes each (min reps, max reps,
      // load, rest), then the note. Max reps below min reps is rejected.
      await tapAndSettle(tester, find.text('Machine Chest Press'));
      expect(find.text('Edit exercise'), findsOneWidget);
      expect(find.text('Set 1'), findsOneWidget);
      expect(find.text('Set 2'), findsOneWidget);
      expect(find.text('Set 3'), findsOneWidget);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '10'); // set 1 min reps
      await tester.enterText(fields.at(1), '6'); // set 1 max reps (too low)
      await tester.enterText(fields.at(3), '120'); // set 1 rest
      await tester.enterText(fields.at(12), 'Slow lowering'); // note
      await tapAndSettle(tester, find.text('Done'));
      expect(find.text('Max reps must be at least min reps'), findsOneWidget);
      expect(find.text('Edit exercise'), findsOneWidget);

      await tester.enterText(fields.at(1), '15');
      await tapAndSettle(tester, find.text('Done'));

      expect(find.text('Edit exercise'), findsNothing);
      expect(find.text('3 sets'), findsOneWidget);
      expect(find.text('Slow lowering'), findsOneWidget);

      // The change was kept: reopen and read the boxes back.
      await tapAndSettle(tester, find.text('Machine Chest Press'));
      String boxText(int i) => tester
          .widget<TextFormField>(find.byType(TextFormField).at(i))
          .controller!
          .text;
      expect(boxText(0), '10');
      expect(boxText(1), '15');
      expect(boxText(3), '120');
      expect(boxText(4), '8'); // set 2 is untouched
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Remove it again.
      await tapAndSettle(tester, find.byTooltip('Remove exercise'));
      expect(find.text('Machine Chest Press'), findsNothing);
      expect(find.text('No exercises yet.'), findsOneWidget);
    });

    testWidgets(
      'plan a program, save it, see it after restart, edit it, then delete it',
      (tester) async {
        seedSavedProfile();
        useTallScreen(tester);
        await launchApp(tester);
        await openProgramTab(tester);

        // --- plan ---
        await tapAndSettle(tester, find.byKey(const ValueKey('create-program')));
        await completeProgramSetup(tester);
        await tester.enterText(find.byType(TextFormField).first, 'Test Plan');
        await tester.tap(find.widgetWithText(FilterChip, 'Mon'));
        await tester.pump();

        await tapAndSettle(tester, find.text('Add workout'));
        await tapAndSettle(tester, find.text('Custom'));
        await tester.enterText(find.byType(TextFormField).first, 'Upper A');
        await addMachineChestPress(tester);
        await tapAndSettle(tester, find.text('Done'));

        expect(find.text('1 exercise · 3 sets'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilterChip, 'Upper A'));
        await tester.pump();

        // --- save ---
        await tapAndSettle(tester, find.text('Save program'));
        expect(find.text('Test Plan'), findsOneWidget);
        expect(find.text('Active · M'), findsOneWidget);

        // --- restart: it is still there ---
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await launchApp(tester);
        await openProgramTab(tester);
        expect(find.text('Test Plan'), findsOneWidget);

        // --- detail ---
        await tapAndSettle(tester, find.text('Test Plan'));
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('schedule-day-monday')),
            matching: find.text('Rest'),
          ),
          findsNothing,
        );
        expect(find.text('Upper A'), findsWidgets);
        expect(find.text('Active program'), findsOneWidget);

        // --- edit ---
        await tapAndSettle(tester, find.byTooltip('Rename program'));
        expect(find.text('Program name'), findsOneWidget); // the rename dialog
        await tester.enterText(
          find.byKey(const ValueKey('rename-field')),
          'Renamed Plan',
        );
        await tapAndSettle(tester, find.text('Save'));
        expect(find.text('Renamed Plan'), findsWidgets);

        // --- delete ---
        await tapAndSettle(tester, find.text('Delete program'));
        await tapAndSettle(tester, find.text('Delete'));
        expect(find.text('No program yet.'), findsOneWidget);
      },
    );
  });
}
