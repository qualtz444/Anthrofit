import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/app.dart';
import 'package:anthrofit/core/format.dart';
import 'package:anthrofit/core/set_input.dart';
import 'package:anthrofit/data/session_repository.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/state/session_controller.dart';

import 'test_helpers.dart';

/// Upper A: Machine Chest Press (2 sets, 8-12, 90 sec) then Push-Up (2 sets, 8-15, 60 sec).
/// Lower A: Leg Press (1 set).
TrainingProgram _program() {
  return TrainingProgram(
    id: 'prog1',
    name: 'Test Plan',
    workouts: [
      Workout(
        id: 'w-upper',
        name: 'Upper A',
        exercises: [
          testPlanned(
            'p1',
            'machine_chest_press',
            sets: 2,
            note: 'Pause at the bottom',
          ),
          testPlanned('p2', 'push_up', sets: 2, repMax: 15, rest: 60),
        ],
      ),
      Workout(
        id: 'w-lower',
        name: 'Lower A',
        exercises: [testPlanned('p3', 'leg_press', sets: 1, rest: 60)],
      ),
    ],
    schedule: const [
      ScheduledWorkout(day: Weekday.monday, workoutId: 'w-upper'),
      ScheduledWorkout(day: Weekday.tuesday, workoutId: 'w-lower'),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

final DateTime _t0 = DateTime(2026, 10, 5, 9, 0);

void main() {
  // The exercise catalogue is an asset now, so it has to be loaded.
  useExerciseLibrary();

  // ---------------------------------------------------------------------
  group('parseSetInput', () {
    test('accepts weight and reps', () {
      final r = parseSetInput(weightText: '42.5', repsText: '8');
      expect(r.isValid, isTrue);
      expect(r.weightKg, 42.5);
      expect(r.reps, 8);
    });

    test('blank weight means no external load', () {
      final r = parseSetInput(weightText: '  ', repsText: '12');
      expect(r.isValid, isTrue);
      expect(r.weightKg, isNull);
    });

    test('zero weight is allowed; comma decimals are read', () {
      expect(parseSetInput(weightText: '0', repsText: '5').weightKg, 0);
      expect(parseSetInput(weightText: '42,5', repsText: '5').weightKg, 42.5);
    });

    test('reps are required, whole, and at least 1', () {
      expect(
        parseSetInput(weightText: '', repsText: '').repsError,
        'Enter reps',
      );
      expect(
        parseSetInput(weightText: '', repsText: '0').repsError,
        'Reps must be 1 or more',
      );
      expect(
        parseSetInput(weightText: '', repsText: '1.5').repsError,
        'Enter reps as a whole number',
      );
      expect(
        parseSetInput(weightText: '', repsText: '-3').repsError,
        'Enter reps as a whole number',
      );
      expect(parseSetInput(weightText: '', repsText: 'abc').isValid, isFalse);
    });

    test('negative, exponent, NaN and Infinity weights are rejected', () {
      expect(
        parseSetInput(weightText: '-5', repsText: '5').weightError,
        "Weight can't be negative",
      );
      for (final bad in ['1e5', 'NaN', 'Infinity', '4 0', '40kg', '--1']) {
        final r = parseSetInput(weightText: bad, repsText: '5');
        expect(r.isValid, isFalse, reason: bad);
        expect(r.weightKg, isNull, reason: bad);
      }
    });

    test('absurdly long numbers are rejected instead of overflowing', () {
      expect(
        parseSetInput(weightText: '', repsText: '9' * 25).isValid,
        isFalse,
      );
      expect(
        parseSetInput(weightText: '9' * 400, repsText: '5').isValid,
        isFalse,
      );
    });
  });

  group('format helpers', () {
    test('formatClock', () {
      expect(formatClock(90), '01:30');
      expect(formatClock(0), '00:00');
      expect(formatClock(5), '00:05');
    });

    test('formatDuration', () {
      expect(formatDuration(const Duration(seconds: 30)), 'Less than 1 min');
      expect(formatDuration(const Duration(minutes: 47)), '47 min');
      expect(formatDuration(const Duration(minutes: 65)), '1 h 5 min');
      expect(formatDuration(const Duration(minutes: 120)), '2 h');
    });
  });

  // ---------------------------------------------------------------------
  group('SessionController', () {
    Future<SessionController> fresh() async {
      seedNoProfile();
      final c = SessionController(SessionRepository());
      await c.load();
      return c;
    }

    Future<void> completeAllSets(SessionController c) async {
      for (final log in c.activeSession!.exerciseLogs) {
        for (final set in log.sets) {
          await c.logSet(
            exerciseLogId: log.id,
            setNumber: set.setNumber,
            weightKg: 40,
            reps: 10,
          );
        }
      }
    }

    test('starting creates an active session in plan order', () async {
      final c = await fresh();
      final program = _program();
      await c.startSession(program, program.workouts.first, now: _t0);

      final s = c.activeSession!;
      expect(s.programId, 'prog1');
      expect(s.workoutId, 'w-upper');
      expect(s.workoutName, 'Upper A');
      expect(s.startedAt, _t0);
      expect(s.isCompleted, isFalse);
      expect(s.duration, isNull);
      expect(s.exerciseLogs.map((l) => l.exerciseName).toList(), [
        'Machine Chest Press',
        'Push-Up',
      ]);

      final first = s.exerciseLogs.first;
      expect(first.plannedExerciseId, 'p1');
      expect(first.plannedSets.length, 2);
      expect(first.plannedSets.first.repRangeLabel, '8–12');
      expect(first.plannedSets.first.restSeconds, 90);
      expect(first.sets.every((x) => x.setType == SetType.working), isTrue);
      expect(first.targetNote, 'Pause at the bottom');
      expect(first.sets.length, 2);
      expect(first.sets.every((x) => !x.isCompleted), isTrue);
    });

    test(
      'actual values may differ from the targets and never change the plan',
      () async {
        final c = await fresh();
        final program = _program();
        final before = jsonEncode(program.toJson());
        await c.startSession(program, program.workouts.first, now: _t0);

        final log = c.activeSession!.exerciseLogs.first;
        // 7 reps is below the 8-12 target; 42.5 kg is whatever the user lifted.
        await c.logSet(
          exerciseLogId: log.id,
          setNumber: 1,
          weightKg: 42.5,
          reps: 7,
        );

        final set = c.activeSession!.exerciseLogs.first.sets.first;
        expect(set.isCompleted, isTrue);
        expect(set.weightKg, 42.5);
        expect(set.reps, 7);
        expect(set.completedAt, isNotNull);
        expect(
          c.activeSession!.exerciseLogs.first.sets[1].isCompleted,
          isFalse,
        );

        // The target snapshot and the program are untouched.
        expect(
          c.activeSession!.exerciseLogs.first.plannedSets.first.targetRepMin,
          8,
        );
        expect(jsonEncode(program.toJson()), before);
      },
    );

    test('a set can be corrected, including clearing the weight', () async {
      final c = await fresh();
      final program = _program();
      await c.startSession(program, program.workouts.first, now: _t0);
      final log = c.activeSession!.exerciseLogs.first;

      await c.logSet(
        exerciseLogId: log.id,
        setNumber: 1,
        weightKg: 40,
        reps: 10,
      );
      await c.logSet(
        exerciseLogId: log.id,
        setNumber: 1,
        weightKg: null,
        reps: 11,
      );

      final set = c.activeSession!.exerciseLogs.first.sets.first;
      expect(set.weightKg, isNull);
      expect(set.reps, 11);
      expect(set.isCompleted, isTrue);
    });

    test('a workout cannot be completed until every set is done', () async {
      final c = await fresh();
      final program = _program();
      await c.startSession(program, program.workouts.first, now: _t0);

      await expectLater(c.completeSession(), throwsA(isA<StateError>()));
      expect(c.activeSession, isNotNull);
      expect(c.completedSessions, isEmpty);
    });

    test('skipped sets and exercises do not stop a workout being saved', () async {
      final c = await fresh();
      final program = _program();
      await c.startSession(program, program.workouts.first, now: _t0);
      final logs = c.activeSession!.exerciseLogs;

      // First exercise: one set done, the rest skipped.
      final first = logs.first;
      await c.logSet(
        exerciseLogId: first.id,
        setNumber: first.sets.first.setNumber,
        weightKg: 40,
        reps: 8,
      );
      for (final set in first.sets.skip(1)) {
        await c.setSetSkipped(
          exerciseLogId: first.id,
          setNumber: set.setNumber,
          skipped: true,
        );
      }
      // Every other exercise: skipped whole.
      for (final log in logs.skip(1)) {
        await c.setSkipped(exerciseLogId: log.id, skipped: true);
      }

      await c.completeSession();
      expect(c.activeSession, isNull);
      final saved = c.completedSessions.single;
      expect(saved.completedSetCount, 1);
    });

    test(
      'completing saves duration and actual data, and survives a restart',
      () async {
        final c = await fresh();
        final program = _program();
        await c.startSession(program, program.workouts.first, now: _t0);
        await completeAllSets(c);
        await c.completeSession(
          completedAt: _t0.add(const Duration(minutes: 47)),
        );

        expect(c.activeSession, isNull);
        expect(c.completedSessions.length, 1);
        expect(
          c.completedSessions.single.duration,
          const Duration(minutes: 47),
        );

        final reloaded = SessionController(SessionRepository());
        await reloaded.load();
        expect(reloaded.activeSession, isNull);
        final saved = reloaded.completedSessions.single;
        expect(saved.workoutName, 'Upper A');
        expect(saved.isCompleted, isTrue);
        expect(saved.duration, const Duration(minutes: 47));
        expect(saved.completedSetCount, 4);
        expect(saved.exerciseLogs.first.sets.first.weightKg, 40);
        expect(saved.exerciseLogs.first.sets.first.reps, 10);
        expect(saved.exerciseLogs.first.targetNote, 'Pause at the bottom');
      },
    );

    test('a session in progress is saved and can be resumed', () async {
      final c = await fresh();
      final program = _program();
      await c.startSession(program, program.workouts.first, now: _t0);
      final log = c.activeSession!.exerciseLogs.first;
      await c.logSet(
        exerciseLogId: log.id,
        setNumber: 1,
        weightKg: 40,
        reps: 9,
      );

      final reloaded = SessionController(SessionRepository());
      await reloaded.load();
      final resumed = reloaded.activeSession!;
      expect(resumed.workoutId, 'w-upper');
      expect(resumed.startedAt, _t0);
      expect(resumed.exerciseLogs.first.sets.first.reps, 9);
      expect(resumed.exerciseLogs.first.sets.first.isCompleted, isTrue);
      expect(resumed.completedSetCount, 1);
    });

    test('discarding removes the session and saves nothing', () async {
      final c = await fresh();
      final program = _program();
      await c.startSession(program, program.workouts.first, now: _t0);
      await c.discardActiveSession();

      expect(c.activeSession, isNull);
      expect(c.completedSessions, isEmpty);
      final reloaded = SessionController(SessionRepository());
      await reloaded.load();
      expect(reloaded.activeSession, isNull);
    });

    test('starting again replaces the session in progress', () async {
      final c = await fresh();
      final program = _program();
      final first = await c.startSession(
        program,
        program.workouts.first,
        now: _t0,
      );
      final second = await c.startSession(
        program,
        program.workouts.last,
        now: _t0,
      );

      expect(second.id, isNot(first.id));
      expect(c.activeSession?.workoutName, 'Lower A');
      expect(c.completedSessions, isEmpty);
    });
  });

  // ---------------------------------------------------------------------
  group('Workout Session screen', () {
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
      await tapAndSettle(
        tester,
        find.byKey(ValueKey('workout-card-$workoutId')),
      );
    }

    Future<void> startUpperA(WidgetTester tester) async {
      seedProfileAndPrograms([_program()], activeProgramId: 'prog1');
      useTallScreen(tester);
      await launchApp(tester);
      await openWorkout(tester, 'w-upper');
      await startWorkout(tester);
    }

    /// Fills the inline inputs and taps Complete set.
    ///
    /// Found by label rather than position: a bodyweight exercise has no
    /// weight box, so the reps box is not always the second one.
    /// [weight] null leaves the weight box exactly as it is.
    /// Logs a set. The rest-and-coach pop-up that follows is closed unless
    /// [keepRest] is set, so the next step can use the screen underneath.
    Future<void> completeSet(
      WidgetTester tester, {
      String? weight,
      required String reps,
      bool keepRest = false,
    }) async {
      if (weight != null) {
        await tester.enterText(
          find.ancestor(
            of: find.text('Weight (kg)'),
            matching: find.byType(TextField),
          ),
          weight,
        );
      }
      await tester.enterText(
        find.ancestor(of: find.text('Reps'), matching: find.byType(TextField)),
        reps,
      );
      await tester.tap(find.text('Complete set'));
      await tester.pump();
      await tester.pump();
      if (!keepRest) await closeRestSheet(tester);
    }

    String fieldText(WidgetTester tester, int index) => tester
        .widget<TextField>(find.byType(TextField).at(index))
        .controller!
        .text;

    testWidgets('full workout: log sets, rest, next exercise, complete, save', (
      tester,
    ) async {
      await startUpperA(tester);

      // Start: first exercise, planned order, targets from the plan.
      expect(find.text('Exercise 1 of 2'), findsOneWidget);
      expect(find.text('0 / 4 sets completed'), findsOneWidget);
      expect(find.text('Machine Chest Press'), findsOneWidget);
      expect(find.text('Primary: Chest'), findsOneWidget);
      expect(find.text('Secondary: Triceps · Front Delts'), findsOneWidget);
      expect(find.text('2 sets'), findsOneWidget);
      expect(find.text('WORKING SET'), findsOneWidget);
      expect(find.text('Target: 8–12 reps'), findsOneWidget);
      expect(find.text('Pause at the bottom'), findsOneWidget);
      expect(find.text('Complete set'), findsOneWidget);
      // The bar is always shown now, disabled until the exercise is done.
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Next exercise'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Start rest'), findsNothing); // nothing to rest from yet

      // Set 1: 7 reps is below the 8-12 target and that is fine.
      await completeSet(tester, weight: '40', reps: '7', keepRest: true);
      expect(find.text('40 kg × 7'), findsOneWidget);
      expect(find.text('1 / 4 sets completed'), findsOneWidget);

      // The coach pops up with the rest timer and says it is rest time.
      expect(find.byKey(const ValueKey('rest-coach-sheet')), findsOneWidget);
      expect(
        find.text("Set 1 done. It's rest time: take 01:30 before set 2."),
        findsOneWidget,
      );

      // The rest timer starts by itself, from the planned 90 seconds.
      expect(find.text('01:30'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('01:29'), findsOneWidget);

      // Skipping it stops the countdown and shows the planned time again.
      await tester.tap(find.text('Skip rest'));
      await tester.pump();
      expect(find.text('01:30'), findsOneWidget);

      // It can be run again by hand, and reports when it finishes.
      await tester.tap(find.text('Start rest'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 90));
      expect(find.text('Rest complete'), findsOneWidget);
      expect(find.text('Restart rest'), findsOneWidget);
      expect(find.text('Rest is over. Time for set 2.'), findsOneWidget);

      // Start next set closes the pop-up.
      await closeRestSheet(tester);
      expect(find.byKey(const ValueKey('rest-coach-sheet')), findsNothing);

      // Set 2 starts pre-filled from set 1 and can be changed.
      expect(fieldText(tester, 0), '40');
      expect(fieldText(tester, 1), '7');
      await completeSet(tester, reps: '9');
      expect(find.text('40 kg × 9'), findsOneWidget);
      expect(find.text('2/2 sets completed'), findsOneWidget);
      expect(find.text('Complete set'), findsNothing);

      // Only now can the user move on.
      await tapAndSettle(tester, find.text('Next exercise'));
      expect(find.text('Exercise 2 of 2'), findsOneWidget);
      expect(find.text('Push-Up'), findsOneWidget);
      expect(find.text('Target: 8–15 reps'), findsOneWidget);
      // Bodyweight: one field, reps only, with no weight box at all.
      expect(find.byType(TextField), findsOneWidget);
      expect(fieldText(tester, 0), '');
      expect(find.text('Add weight'), findsOneWidget);

      // Bodyweight: reps only, no weight needed.
      await completeSet(tester, reps: '12');
      expect(find.text('12 reps'), findsOneWidget);
      await completeSet(tester, reps: '11');
      expect(find.text('11 reps'), findsOneWidget);
      // Last exercise, both sets done: the button offers to finish.
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Complete workout'),
            )
            .onPressed,
        isNotNull,
      );

      // Last exercise: Complete workout -> summary.
      await tapAndSettle(tester, find.text('Complete workout'));
      expect(find.text('Workout summary'), findsOneWidget);
      expect(find.text('Upper A'), findsOneWidget);
      expect(find.text('Workout complete · Less than 1 min'), findsOneWidget);
      expect(find.text('4'), findsOneWidget); // total sets
      // 40 × 7 + 40 × 9: the total, and the first exercise's own row.
      expect(find.text('640 kg'), findsNWidgets(2));
      expect(find.text('2 × 7–9'), findsOneWidget);
      expect(find.text('2 × 11–12'), findsOneWidget);
      expect(find.text('Bodyweight'), findsOneWidget);

      // A row opens to show every set.
      await tapAndSettle(tester, find.text('2 × 7–9'));
      expect(find.text('7 reps · 40 kg'), findsOneWidget);
      expect(find.text('9 reps · 40 kg'), findsOneWidget);

      // Save -> back on Workout Detail. The plan is unchanged.
      await tapAndSettle(tester, find.text('Save workout'));
      expect(find.text('Workout saved'), findsOneWidget);
      expect(find.text('Start workout'), findsOneWidget);
      expect(find.text('2 exercises · 4 sets'), findsOneWidget);
      expect(find.text('8–12 reps · Rest 90s'), findsNWidgets(2));

      // The completed session is in storage and nothing is left in progress.
      final saved = await tester.runAsync(() => SessionRepository().load());
      expect(saved!.activeSession, isNull);
      expect(saved.sessions.length, 1);
      final session = saved.sessions.single;
      expect(session.isCompleted, isTrue);
      expect(session.completedSetCount, 4);
      expect(session.exerciseLogs.first.sets.first.weightKg, 40);
      expect(session.exerciseLogs.first.sets.first.reps, 7);
      expect(session.exerciseLogs.last.sets.first.weightKg, isNull);
    });

    testWidgets(
      'guided workout counts each set, then uses normal set logging',
      (tester) async {
        seedProfileAndPrograms([_program()], activeProgramId: 'prog1');
        useTallScreen(tester);
        await launchApp(tester);
        await openWorkout(tester, 'w-upper');
        await startWorkout(tester, guided: true);

        expect(find.byKey(const ValueKey('guided-setup')), findsOneWidget);
        expect(find.byKey(const ValueKey('guided-start-tap')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('guided-workout-header')),
          findsOneWidget,
        );
        await tapAndSettle(tester, find.text('Count by tapping'));
        await tester.tap(find.byKey(const ValueKey('guided-weight-control')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('guided-weight')),
          '42.5',
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('guided-plus')));
        await tester.tap(find.byKey(const ValueKey('guided-done')));
        await tester.pumpAndSettle();

        expect(find.text('Exercise 1 of 2'), findsOneWidget);
        expect(find.text('0 / 4 sets completed'), findsOneWidget);
        expect(fieldText(tester, 0), '42.5');
        expect(fieldText(tester, 1), '1');
        await completeSet(tester, reps: '8');
        final logged = await tester.runAsync(() => SessionRepository().load());
        expect(
          logged!.activeSession!.exerciseLogs.first.sets.first.weightKg,
          closeTo(42.5, 1e-9),
        );

        expect(find.byKey(const ValueKey('guided-setup')), findsOneWidget);
        expect(find.textContaining('Set 2'), findsOneWidget);
        final active = await tester.runAsync(() => SessionRepository().load());
        expect(active!.activeSession!.guidedMode, isTrue);
        expect(active.activeSession!.completedSetCount, 1);

        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tapAndSettle(tester, find.text('Leave workout'));
        await tapAndSettle(tester, find.text('Resume workout'));
        expect(find.byKey(const ValueKey('guided-setup')), findsOneWidget);
        expect(find.textContaining('Set 2'), findsOneWidget);
      },
    );

    testWidgets('invalid input is explained and nothing is saved', (
      tester,
    ) async {
      await startUpperA(tester);

      await tester.tap(find.text('Complete set'));
      await tester.pump();
      expect(find.text('Enter reps'), findsOneWidget);

      await completeSet(tester, weight: '', reps: '0');
      expect(find.text('Reps must be 1 or more'), findsOneWidget);

      await completeSet(tester, weight: '', reps: '1.5');
      expect(find.text('Enter reps as a whole number'), findsOneWidget);

      await completeSet(tester, weight: '-5', reps: '5');
      expect(find.text("Weight can't be negative"), findsOneWidget);

      expect(find.textContaining('NaN'), findsNothing);
      expect(find.textContaining('Infinity'), findsNothing);
      expect(find.textContaining('null'), findsNothing);
      expect(find.text('0 / 4 sets completed'), findsOneWidget);
    });

    testWidgets('a completed set can be edited', (tester) async {
      await startUpperA(tester);
      await completeSet(tester, weight: '40', reps: '7');

      await tapAndSettle(tester, find.text('40 kg × 7'));
      expect(find.text('Edit set 1'), findsOneWidget);
      final dialogFields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogFields.at(0), '42.5');
      await tester.enterText(dialogFields.at(1), '8');
      await tapAndSettle(tester, find.text('Save'));

      expect(find.text('42.5 kg × 8'), findsOneWidget);
      expect(find.text('40 kg × 7'), findsNothing);
      expect(find.text('1 / 4 sets completed'), findsOneWidget);
    });

    testWidgets('leaving keeps progress and the workout can be resumed', (
      tester,
    ) async {
      await startUpperA(tester);
      await completeSet(tester, weight: '40', reps: '7');

      // Back asks first. "Keep working out" stays.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Leave workout?'), findsOneWidget);
      expect(
        find.text('Your current workout progress will be kept.'),
        findsOneWidget,
      );
      await tapAndSettle(tester, find.text('Keep working out'));
      expect(find.text('Exercise 1 of 2'), findsOneWidget);

      // "Leave workout" goes back to Workout Detail, which now offers Resume.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.text('Leave workout'));
      expect(find.text('Resume workout'), findsOneWidget);

      // Restart the whole app: the session is still in progress.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await launchApp(tester);
      await openWorkout(tester, 'w-upper');
      expect(find.text('Resume workout'), findsOneWidget);

      await tapAndSettle(tester, find.text('Resume workout'));
      expect(find.text('Exercise 1 of 2'), findsOneWidget);
      expect(find.text('40 kg × 7'), findsOneWidget);
      expect(find.text('1 / 4 sets completed'), findsOneWidget);
    });

    testWidgets('a workout can be discarded', (tester) async {
      await startUpperA(tester);
      await completeSet(tester, weight: '40', reps: '7');

      await tapAndSettle(tester, find.byTooltip('Workout options'));
      await tapAndSettle(tester, find.text('Discard workout'));
      expect(find.text('Discard workout?'), findsOneWidget);
      await tapAndSettle(tester, find.text('Discard'));

      expect(find.text('Start workout'), findsOneWidget);
      final saved = await tester.runAsync(() => SessionRepository().load());
      expect(saved!.activeSession, isNull);
      expect(saved.sessions, isEmpty);
    });

    testWidgets(
      'summary back returns to the session and summary can be discarded',
      (tester) async {
        await startUpperA(tester);
        await completeSet(tester, weight: '40', reps: '7');
        await completeSet(tester, weight: '40', reps: '9');
        await tapAndSettle(tester, find.text('Next exercise'));
        await completeSet(tester, reps: '12');
        await completeSet(tester, reps: '11');
        await tapAndSettle(tester, find.text('Complete workout'));

        expect(find.text('Workout summary'), findsOneWidget);
        expect(find.byKey(const ValueKey('summary-discard')), findsOneWidget);

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('Exercise 2 of 2'), findsOneWidget);
        expect(find.text('Complete workout'), findsOneWidget);

        await tapAndSettle(tester, find.text('Complete workout'));
        await tapAndSettle(
          tester,
          find.byKey(const ValueKey('summary-discard')),
        );
        expect(find.text('Discard workout?'), findsOneWidget);
        await tapAndSettle(
          tester,
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Discard'),
          ),
        );

        expect(find.text('Start workout'), findsOneWidget);
        final saved = await tester.runAsync(() => SessionRepository().load());
        expect(saved!.activeSession, isNull);
        expect(saved.sessions, isEmpty);
      },
    );

    testWidgets(
      'starting another workout asks what to do with the unfinished one',
      (tester) async {
        await startUpperA(tester);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tapAndSettle(tester, find.text('Leave workout'));

        // Back to the program, then open the other workout.
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tapAndSettle(
          tester,
          find.byKey(const ValueKey('workout-card-w-lower')),
        );
        expect(find.text('Start workout'), findsOneWidget);

        await tapAndSettle(tester, find.text('Start workout'));
        expect(find.text('Workout in progress'), findsOneWidget);
        await tapAndSettle(tester, find.text('Discard and start'));
        await tapAndSettle(
          tester,
          find.byKey(const ValueKey('start-manual-workout')),
        );

        expect(find.text('Exercise 1 of 1'), findsOneWidget);
        expect(find.text('Leg Press'), findsOneWidget);
      },
    );
  });
}
