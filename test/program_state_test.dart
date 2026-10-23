import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/app.dart';
import 'package:anthrofit/data/program_repository.dart';
import 'package:anthrofit/data/session_repository.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/state/program_controller.dart';
import 'package:anthrofit/state/session_controller.dart';

import 'test_helpers.dart';

TrainingProgram _program(String id, String name, {bool archived = false}) =>
    TrainingProgram(
      id: id,
      name: name,
      archived: archived,
      workouts: [
        Workout(
          id: '$id-w',
          name: '$name Day',
          exercises: [testPlanned('$id-p', 'machine_chest_press', sets: 1)],
        ),
      ],
      schedule: [
        for (final day in Weekday.values)
          ScheduledWorkout(day: day, workoutId: '$id-w'),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Future<ProgramController> _programs() async {
  final c = ProgramController(ProgramRepository());
  await c.load();
  return c;
}

Future<SessionController> _sessions() async {
  final c = SessionController(SessionRepository());
  await c.load();
  return c;
}

void main() {
  // The exercise catalogue is an asset now, so it has to be loaded.
  useExerciseLibrary();

  // ---------------------------------------------------------------------
  group('activation', () {
    test(
      'activating an inactive program makes it the one being followed',
      () async {
        seedProfileAndPrograms([_program('a', 'Alpha')]);
        final programs = await _programs();
        expect(programs.activeProgramId, isNull);

        await programs.setActiveProgram('a');
        expect(programs.activeProgramId, 'a');
        expect(programs.activeProgram!.name, 'Alpha');

        final reloaded = await _programs();
        expect(reloaded.activeProgramId, 'a');
      },
    );

    test('activating B stops following A, and changes neither', () async {
      seedProfileAndPrograms([
        _program('a', 'Alpha'),
        _program('b', 'Beta'),
      ], activeProgramId: 'a');
      final programs = await _programs();

      await programs.setActiveProgram('b');

      expect(programs.activeProgramId, 'b');
      // A is still there, with everything it had.
      final alpha = programs.programById('a')!;
      expect(alpha.archived, isFalse);
      expect(alpha.workouts.single.exercises.length, 1);
      expect(alpha.schedule.length, Weekday.values.length);
      expect(programs.programById('b')!.workouts.single.name, 'Beta Day');
    });

    test(
      'deactivating leaves no active program, and deletes nothing',
      () async {
        seedProfileAndPrograms([_program('a', 'Alpha')], activeProgramId: 'a');
        final programs = await _programs();

        await programs.deactivateProgram('a');

        expect(programs.activeProgramId, isNull);
        expect(programs.activeProgram, isNull);
        final alpha = programs.programById('a')!;
        expect(alpha.archived, isFalse); // not archived, just not followed
        expect(alpha.workouts.single.exercises.length, 1);
        expect(alpha.schedule, isNotEmpty);

        final reloaded = await _programs();
        expect(reloaded.activeProgramId, isNull);
        expect(reloaded.programById('a'), isNotNull);
      },
    );

    test('deactivating a program that is not active does nothing', () async {
      seedProfileAndPrograms([
        _program('a', 'Alpha'),
        _program('b', 'Beta'),
      ], activeProgramId: 'a');
      final programs = await _programs();
      await programs.deactivateProgram('b');
      expect(programs.activeProgramId, 'a');
    });
  });

  // ---------------------------------------------------------------------
  group('deletion', () {
    test('deleting an inactive program leaves the active one alone', () async {
      seedProfileAndPrograms([
        _program('a', 'Alpha'),
        _program('b', 'Beta'),
      ], activeProgramId: 'a');
      final programs = await _programs();

      await programs.deleteProgram('b');

      expect(programs.programById('b'), isNull);
      expect(programs.activeProgramId, 'a');
      expect(programs.programById('a')!.workouts.single.exercises.length, 1);
    });

    test('deleting the active program leaves nothing active', () async {
      seedProfileAndPrograms([
        _program('a', 'Alpha'),
        _program('b', 'Beta'),
      ], activeProgramId: 'a');
      final programs = await _programs();

      await programs.deleteProgram('a');

      expect(programs.activeProgramId, isNull);
      expect(programs.activeProgram, isNull);
      // Nothing is promoted in its place.
      expect(programs.programById('b'), isNotNull);

      final reloaded = await _programs();
      expect(reloaded.activeProgramId, isNull);
    });

    test('its scheduled days go with it', () async {
      seedProfileAndPrograms([
        _program('a', 'Alpha'),
        _program('b', 'Beta'),
      ], activeProgramId: 'a');
      final programs = await _programs();
      await programs.deleteProgram('a');

      // Nothing refers to the deleted program any more.
      for (final program in programs.programs) {
        expect(program.id, isNot('a'));
        for (final scheduled in program.schedule) {
          expect(
            program.workouts.any((w) => w.id == scheduled.workoutId),
            isTrue,
          );
        }
      }
      // And B's own schedule is untouched.
      expect(programs.programById('b')!.schedule.length, Weekday.values.length);
    });

    test('an unfinished workout from a deleted program is dropped', () async {
      final program = _program('a', 'Alpha');
      seedProfileAndPrograms([program], activeProgramId: 'a');
      final programs = await _programs();
      final sessions = await _sessions();

      await sessions.startSession(program, program.workouts.single);
      expect(sessions.activeSession, isNotNull);

      final dropped = await sessions.discardSessionForProgram('a');
      await programs.deleteProgram('a');

      expect(dropped, isTrue);
      expect(sessions.activeSession, isNull);

      // And it stays gone after a restart.
      final reloaded = await _sessions();
      expect(reloaded.activeSession, isNull);
    });

    test('an unfinished workout from another program is kept', () async {
      final beta = _program('b', 'Beta');
      seedProfileAndPrograms([
        _program('a', 'Alpha'),
        beta,
      ], activeProgramId: 'b');
      final programs = await _programs();
      final sessions = await _sessions();
      await sessions.startSession(beta, beta.workouts.single);

      final dropped = await sessions.discardSessionForProgram('a');
      await programs.deleteProgram('a');

      expect(dropped, isFalse);
      expect(sessions.activeSession, isNotNull);
      expect(sessions.activeSession!.programId, 'b');
    });

    test('completed history survives deleting its program', () async {
      final program = _program('a', 'Alpha');
      seedProfileAndPrograms([program], activeProgramId: 'a');
      final programs = await _programs();
      final sessions = await _sessions();

      await sessions.startSession(program, program.workouts.single);
      final log = sessions.activeSession!.exerciseLogs.single;
      await sessions.logSet(
        exerciseLogId: log.id,
        setNumber: 1,
        weightKg: 40,
        reps: 10,
      );
      await sessions.completeSession();

      await sessions.discardSessionForProgram('a');
      await programs.deleteProgram('a');

      expect(sessions.completedSessions.length, 1);
      final reloaded = await _sessions();
      expect(reloaded.completedSessions.single.workoutName, 'Alpha Day');
    });
  });

  // ---------------------------------------------------------------------
  group('Home follows the active program', () {
    void useTallScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> launch(WidgetTester tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(AnthrofitApp(authService: FakeAuthService()));
      await tester.pumpAndSettle();
    }

    Future<void> openProgram(WidgetTester tester, String name) async {
      await tapAndSettle(
        tester,
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Program'),
        ),
      );
      await tapAndSettle(tester, find.text(name));
    }

    Future<void> goHome(WidgetTester tester) => tapAndSettle(
      tester,
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Home'),
      ),
    );

    testWidgets('with no active program it says so', (tester) async {
      seedProfileAndPrograms([_program('a', 'Alpha')]);
      await launch(tester);
      expect(find.text('No active program'), findsOneWidget);
      expect(find.text('Alpha Day'), findsNothing);
    });

    testWidgets('activating one from its status shows its workout', (
      tester,
    ) async {
      seedProfileAndPrograms([_program('a', 'Alpha')]);
      await launch(tester);
      expect(find.text('No active program'), findsOneWidget);

      await openProgram(tester, 'Alpha');
      await tapAndSettle(tester, find.text('Not active'));
      expect(find.text('Follow Alpha?'), findsOneWidget);
      await tapAndSettle(tester, find.widgetWithText(TextButton, 'Activate'));

      await tester.pageBack();
      await tester.pumpAndSettle();

      await goHome(tester);
      expect(find.text('No active program'), findsNothing);
      expect(find.text('Alpha Day'), findsOneWidget);
    });

    testWidgets('activating another says which one it replaces', (
      tester,
    ) async {
      seedProfileAndPrograms([
        _program('a', 'Alpha'),
        _program('b', 'Beta'),
      ], activeProgramId: 'a');
      await launch(tester);
      expect(find.text('Alpha Day'), findsOneWidget);

      await openProgram(tester, 'Beta');
      await tapAndSettle(tester, find.text('Not active'));
      expect(
        find.textContaining('This will stop following Alpha'),
        findsOneWidget,
      );
      await tapAndSettle(tester, find.widgetWithText(TextButton, 'Activate'));

      await tester.pageBack();
      await tester.pumpAndSettle();

      await goHome(tester);
      expect(find.text('Beta Day'), findsOneWidget);
      expect(find.text('Alpha Day'), findsNothing);
    });

    testWidgets('deactivating from the status empties Home', (tester) async {
      seedProfileAndPrograms([_program('a', 'Alpha')], activeProgramId: 'a');
      await launch(tester);
      expect(find.text('Alpha Day'), findsOneWidget);

      await openProgram(tester, 'Alpha');
      await tapAndSettle(tester, find.text('Active'));
      expect(find.text('Stop following Alpha?'), findsOneWidget);
      await tapAndSettle(tester, find.text('Stop following'));

      await tester.pageBack();
      await tester.pumpAndSettle();

      await goHome(tester);
      expect(find.text('No active program'), findsOneWidget);
      expect(find.text('Alpha Day'), findsNothing);
    });

    testWidgets('deleting a program with a workout in progress clears Home', (
      tester,
    ) async {
      final program = _program('a', 'Alpha');
      seedAppData(
        programs: [program],
        activeProgramId: 'a',
        activeSession: WorkoutSession(
          id: 's1',
          programId: 'a',
          programName: 'Alpha',
          workoutId: 'a-w',
          workoutName: 'Alpha Day',
          startedAt: DateTime(2026, 10, 5, 9),
          exerciseLogs: [
            ExerciseLog.fromPlanned(
              testPlanned('a-p', 'machine_chest_press', sets: 1),
              'Machine Chest Press',
            ),
          ],
        ),
      );
      await launch(tester);
      expect(find.text('Workout in progress'), findsOneWidget);

      await openProgram(tester, 'Alpha');
      await tapAndSettle(tester, find.text('Delete program'));
      expect(
        find.textContaining('discard the workout you have in progress'),
        findsOneWidget,
      );
      await tapAndSettle(tester, find.text('Delete'));

      await goHome(tester);
      // No stale workout, and no program to show one for.
      expect(find.text('Workout in progress'), findsNothing);
      expect(find.text('Alpha Day'), findsNothing);
      expect(find.text('No active program'), findsOneWidget);

      final saved = await tester.runAsync(() => SessionRepository().load());
      expect(saved!.activeSession, isNull);
    });
  });
}
