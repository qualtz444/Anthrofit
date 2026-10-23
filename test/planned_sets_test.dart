import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anthrofit/app.dart';
import 'package:anthrofit/auth/account_store.dart';
import 'package:anthrofit/core/set_input.dart';
import 'package:anthrofit/core/set_labels.dart';
import 'package:anthrofit/data/exercise_library.dart';
import 'package:anthrofit/data/profile_repository.dart';
import 'package:anthrofit/data/program_repository.dart';
import 'package:anthrofit/data/session_repository.dart';
import 'package:anthrofit/data/training_stats.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/screens/exercises/exercise_detail_screen.dart';
import 'package:anthrofit/state/program_controller.dart';
import 'package:anthrofit/state/session_controller.dart';

import 'test_helpers.dart';

/// Warm-up 10 reps / 20 kg / 60s, two Working sets 8-12 / 40 kg / 90s,
/// and a Failure set (no rep target) / 40 kg / 120s.
List<PlannedSet> _mixedSets() => const [
  PlannedSet(
    setType: SetType.warmUp,
    targetRepMin: 10,
    targetRepMax: 10,
    targetLoadKg: 20,
    restSeconds: 60,
  ),
  PlannedSet(
    setType: SetType.working,
    targetRepMin: 8,
    targetRepMax: 12,
    targetLoadKg: 40,
    restSeconds: 90,
  ),
  PlannedSet(
    setType: SetType.working,
    targetRepMin: 8,
    targetRepMax: 12,
    targetLoadKg: 40,
    restSeconds: 90,
  ),
  PlannedSet(setType: SetType.failure, targetLoadKg: 40, restSeconds: 120),
];

TrainingProgram _mixedProgram(Weekday day) {
  return TrainingProgram(
    id: 'prog1',
    name: 'Test Plan',
    workouts: [
      Workout(
        id: 'w-upper',
        name: 'Upper A',
        exercises: [
          PlannedExercise(
            id: 'p1',
            exerciseId: 'machine_chest_press',
            plannedSets: _mixedSets(),
          ),
        ],
      ),
    ],
    schedule: [ScheduledWorkout(day: day, workoutId: 'w-upper')],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  // The exercise catalogue is an asset now, so it has to be loaded.
  useExerciseLibrary();

  final now = DateTime.now();
  final today = Weekday.fromDateTime(now);

  // ---------------------------------------------------------------------
  group('PlannedSet', () {
    test('labels', () {
      expect(SetType.warmUp.label, 'Warm-up');
      expect(SetType.working.label, 'Working Set');
      expect(SetType.failure.label, 'Failure');
      expect(SetType.working.shortLabel, 'Working');
    });

    test('target reps are a range, a single number, or none', () {
      const range = PlannedSet(
        setType: SetType.working,
        targetRepMin: 8,
        targetRepMax: 12,
        restSeconds: 90,
      );
      const single = PlannedSet(
        setType: SetType.warmUp,
        targetRepMin: 10,
        targetRepMax: 10,
        restSeconds: 60,
      );
      const none = PlannedSet(setType: SetType.failure, restSeconds: 120);
      expect(range.repRangeLabel, '8–12');
      expect(single.repRangeLabel, '10');
      expect(none.repRangeLabel, isNull);
      expect(none.hasRepTarget, isFalse);
    });

    test('every field survives JSON, including a blank load and no reps', () {
      for (final set in _mixedSets()) {
        final back = PlannedSet.fromJson(
          jsonDecode(jsonEncode(set.toJson())) as Map<String, dynamic>,
        );
        expect(back.setType, set.setType);
        expect(back.targetRepMin, set.targetRepMin);
        expect(back.targetRepMax, set.targetRepMax);
        expect(back.targetLoadKg, set.targetLoadKg);
        expect(back.restSeconds, set.restSeconds);
      }
      final blank = PlannedSet.defaultWorking();
      final back = PlannedSet.fromJson(blank.toJson());
      expect(back.targetLoadKg, isNull); // never filled in automatically
    });

    test('odd saved values fall back safely', () {
      final s = PlannedSet.fromJson({
        'setType': 'somethingNew',
        'targetRepMin': 0,
        'targetLoadKg': 0,
      });
      expect(s.setType, SetType.working);
      expect(s.targetRepMin, isNull);
      expect(s.targetRepMax, isNull);
      expect(s.targetLoadKg, isNull);
      expect(s.restSeconds, 90);

      final swapped = PlannedSet.fromJson({
        'targetRepMin': 10,
        'targetRepMax': 6,
        'restSeconds': 30,
      });
      expect(swapped.targetRepMax, 10);
      expect(swapped.restSeconds, 30);
    });
  });

  group('PlannedExercise', () {
    test('a new exercise starts with 3 Working sets of 8-12, 90s, no load', () {
      final p = PlannedExercise.withDefaults('machine_chest_press');
      expect(p.plannedSets.length, 3);
      for (final s in p.plannedSets) {
        expect(s.setType, SetType.working);
        expect(s.repRangeLabel, '8–12');
        expect(s.targetLoadKg, isNull);
        expect(s.restSeconds, 90);
      }
    });

    test('sets that differ in type, reps, load and rest are all kept', () {
      final p = PlannedExercise(
        id: 'p',
        exerciseId: 'machine_chest_press',
        plannedSets: _mixedSets(),
        note: 'n',
      );
      final back = PlannedExercise.fromJson(
        jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>,
      );
      expect(back.plannedSets.map((s) => s.setType).toList(), [
        SetType.warmUp,
        SetType.working,
        SetType.working,
        SetType.failure,
      ]);
      expect(back.plannedSets.map((s) => s.targetLoadKg).toList(), [
        20,
        40,
        40,
        40,
      ]);
      expect(back.plannedSets.map((s) => s.restSeconds).toList(), [
        60,
        90,
        90,
        120,
      ]);
      expect(back.plannedSets.last.repRangeLabel, isNull);
      expect(back.note, 'n');
    });

    test(
      'OLD format: one shared prescription becomes individual Working sets',
      () {
        final old = PlannedExercise.fromJson({
          'id': 'pe',
          'exerciseId': 'machine_chest_press',
          'sets': 3,
          'repMin': 8,
          'repMax': 12,
          'restSeconds': 90,
          'note': 'Pause at the bottom',
        });
        expect(old.plannedSets.length, 3);
        for (final s in old.plannedSets) {
          expect(s.setType, SetType.working);
          expect(s.targetRepMin, 8);
          expect(s.targetRepMax, 12);
          expect(s.targetLoadKg, isNull);
          expect(s.restSeconds, 90);
        }
        expect(old.note, 'Pause at the bottom');
      },
    );

    test('OLD format with missing pieces still loads', () {
      final bare = PlannedExercise.fromJson({'id': 'pe', 'exerciseId': 'x'});
      expect(bare.plannedSets.length, 3);
      expect(bare.plannedSets.first.repRangeLabel, '8–12');
      expect(bare.plannedSets.first.restSeconds, 90);

      final custom = PlannedExercise.fromJson({
        'id': 'pe',
        'exerciseId': 'x',
        'sets': 5,
        'repMin': 5,
        'repMax': 5,
        'restSeconds': 0,
      });
      expect(custom.plannedSets.length, 5);
      expect(custom.plannedSets.first.repRangeLabel, '5');
      expect(custom.plannedSets.first.restSeconds, 0);
    });

    test(
      'an old saved program loads with its planned sets, nothing lost',
      () async {
        final oldProgram = {
          'id': 'p1',
          'name': 'Old Plan',
          'workouts': [
            {
              'id': 'w1',
              'name': 'Upper A',
              'focus': '',
              'exercises': [
                {
                  'id': 'pe1',
                  'exerciseId': 'machine_chest_press',
                  'sets': 4,
                  'repMin': 6,
                  'repMax': 10,
                  'restSeconds': 120,
                  'note': '',
                },
              ],
            },
          ],
          'schedule': [
            {'day': 'monday', 'workoutId': 'w1'},
          ],
          'createdAt': '2026-01-01T00:00:00.000',
          'updatedAt': '2026-01-01T00:00:00.000',
        };
        SharedPreferences.setMockInitialValues({
          ProgramRepository.storageKey: jsonEncode({
            'activeProgramId': 'p1',
            'programs': [oldProgram],
          }),
        });

        final c = ProgramController(ProgramRepository());
        await c.load();
        final program = c.programs.single;
        expect(program.name, 'Old Plan');
        expect(program.workoutForDay(Weekday.monday)?.name, 'Upper A');
        final planned = program.workouts.single.exercises.single;
        expect(planned.plannedSets.length, 4);
        expect(
          planned.plannedSets.every((s) => s.setType == SetType.working),
          isTrue,
        );
        expect(planned.plannedSets.first.repRangeLabel, '6–10');
        expect(planned.plannedSets.first.restSeconds, 120);
        expect(program.workouts.single.totalSets, 4);

        // Saving writes the new format, and it reloads the same.
        await c.saveProgram(program);
        final again = ProgramController(ProgramRepository());
        await again.load();
        expect(
          again
              .programs
              .single
              .workouts
              .single
              .exercises
              .single
              .plannedSets
              .length,
          4,
        );
      },
    );
  });

  group('set text', () {
    test('compact labels', () {
      final sets = _mixedSets();
      expect(plannedSetDetails(sets[0]), '10 reps · 20 kg · Rest 60s');
      expect(plannedSetDetails(sets[1]), '8–12 reps · 40 kg · Rest 90s');
      expect(plannedSetDetails(sets[3]), 'To Failure · 40 kg · Rest 120s');
      expect(plannedTargetLabel(sets[3]), 'To Failure · 40 kg');
      expect(
        plannedSetDetails(PlannedSet.defaultWorking()),
        '8–12 reps · Rest 90s',
      );
    });

    test('summary of the sets', () {
      expect(
        plannedSetsSummary(PlannedExercise.withDefaults('x').plannedSets),
        '3 sets',
      );
      expect(
        plannedSetsSummary(_mixedSets()),
        '4 sets · 1 warm-up, 2 working, 1 failure',
      );
    });

    test('number parsing used by the set editor', () {
      expect(parseWholeNumber(' 12 '), 12);
      expect(parseWholeNumber('0'), 0);
      expect(parseWholeNumber(''), isNull);
      expect(parseWholeNumber('1.5'), isNull);
      expect(parseWholeNumber('-3'), isNull);
      expect(parseWholeNumber('9' * 25), isNull);

      expect(parseOptionalWeight('').value, isNull);
      expect(parseOptionalWeight('').error, isNull);
      expect(parseOptionalWeight('42,5').value, 42.5);
      expect(parseOptionalWeight('-1').error, "Weight can't be negative");
      expect(parseOptionalWeight('1e5').error, isNotNull);
    });
  });

  // ---------------------------------------------------------------------
  group('sessions keep the set type', () {
    Future<SessionController> fresh() async {
      seedNoProfile();
      final c = SessionController(SessionRepository());
      await c.load();
      return c;
    }

    test(
      'a session starts with one log per planned set, typed and targeted',
      () async {
        final c = await fresh();
        final program = _mixedProgram(Weekday.monday);
        await c.startSession(
          program,
          program.workouts.single,
          now: DateTime(2026, 10, 5, 9),
        );

        final log = c.activeSession!.exerciseLogs.single;
        expect(log.sets.map((s) => s.setType).toList(), [
          SetType.warmUp,
          SetType.working,
          SetType.working,
          SetType.failure,
        ]);
        expect(log.plannedSets.map((s) => s.restSeconds).toList(), [
          60,
          90,
          90,
          120,
        ]);
        expect(log.plannedSetFor(3)!.repRangeLabel, isNull);
        expect(log.plannedSetFor(9), isNull);
      },
    );

    test(
      'logging keeps the type, differs from the target, and leaves the plan alone',
      () async {
        final c = await fresh();
        final program = _mixedProgram(Weekday.monday);
        final before = jsonEncode(program.toJson());
        await c.startSession(
          program,
          program.workouts.single,
          now: DateTime(2026, 10, 5, 9),
        );
        final log = c.activeSession!.exerciseLogs.single;

        await c.logSet(
          exerciseLogId: log.id,
          setNumber: 1,
          weightKg: 20,
          reps: 10,
        );
        await c.logSet(
          exerciseLogId: log.id,
          setNumber: 2,
          weightKg: 42.5,
          reps: 8,
        );
        await c.logSet(
          exerciseLogId: log.id,
          setNumber: 4,
          weightKg: 40,
          reps: 7,
        );

        final sets = c.activeSession!.exerciseLogs.single.sets;
        expect(sets[0].setType, SetType.warmUp);
        expect(sets[1].setType, SetType.working);
        expect(sets[1].weightKg, 42.5); // not the 40 kg target
        expect(sets[3].setType, SetType.failure);
        expect(sets[2].isCompleted, isFalse);

        // Correcting a set keeps its type too.
        await c.logSet(
          exerciseLogId: log.id,
          setNumber: 1,
          weightKg: 22.5,
          reps: 10,
        );
        expect(
          c.activeSession!.exerciseLogs.single.sets[0].setType,
          SetType.warmUp,
        );

        expect(jsonEncode(program.toJson()), before);
      },
    );

    test(
      'set types and plan survive a restart, in progress and completed',
      () async {
        final c = await fresh();
        final program = _mixedProgram(Weekday.monday);
        await c.startSession(
          program,
          program.workouts.single,
          now: DateTime(2026, 10, 5, 9),
        );
        final log = c.activeSession!.exerciseLogs.single;
        for (var n = 1; n <= 4; n++) {
          await c.logSet(
            exerciseLogId: log.id,
            setNumber: n,
            weightKg: 40,
            reps: 8,
          );
          if (n == 2) {
            final midway = SessionController(SessionRepository());
            await midway.load();
            final resumed = midway.activeSession!.exerciseLogs.single;
            expect(resumed.sets.map((s) => s.setType).toList(), [
              SetType.warmUp,
              SetType.working,
              SetType.working,
              SetType.failure,
            ]);
            expect(resumed.plannedSets.length, 4);
          }
        }
        await c.completeSession(completedAt: DateTime(2026, 10, 5, 9, 40));

        final reloaded = SessionController(SessionRepository());
        await reloaded.load();
        final saved = reloaded.completedSessions.single.exerciseLogs.single;
        expect(saved.sets.map((s) => s.setType).toList(), [
          SetType.warmUp,
          SetType.working,
          SetType.working,
          SetType.failure,
        ]);
        expect(saved.plannedSets.map((s) => s.targetLoadKg).toList(), [
          20,
          40,
          40,
          40,
        ]);
        expect(saved.plannedSets.last.repRangeLabel, isNull);
      },
    );

    test('old logged sets have no type and load as Working', () {
      final set = SetLog.fromJson({
        'setNumber': 1,
        'weightKg': 40.0,
        'reps': 10,
        'isCompleted': true,
      });
      expect(set.setType, SetType.working);
      expect(set.weightKg, 40);
      expect(set.reps, 10);

      final typed = SetLog.fromJson(
        SetLog(setNumber: 1, setType: SetType.failure, reps: 5).toJson(),
      );
      expect(typed.setType, SetType.failure);
    });
  });

  group('warm-up sets in the numbers', () {
    WorkoutSession session() => WorkoutSession(
      id: 's',
      workoutId: 'w',
      workoutName: 'Upper A',
      startedAt: DateTime(2026, 10, 5, 9),
      completedAt: DateTime(2026, 10, 5, 10),
      exerciseLogs: [
        testLog(
          'machine_chest_press',
          'Machine Chest Press',
          [(20.0, 10), (42.5, 8), (40.0, 9), (40.0, 7)],
          types: const [
            SetType.warmUp,
            SetType.working,
            SetType.working,
            SetType.failure,
          ],
        ),
      ],
    );

    test('volume, set counts and records leave warm-ups out', () {
      final s = session();
      final summary = summarize([s]);
      expect(summary.volumeKg, 980); // 340 + 360 + 280, not + 200
      expect(summary.sets, 3);
      expect(summary.reps, 24);
      expect(summary.weightedSets, 3);

      final history = exerciseHistory([s], 'machine_chest_press');
      expect(history.single.sets.length, 3);
      expect(history.single.sets.every(isWorkSet), isTrue);
      final records = personalRecords(history);
      expect(records.heaviestKg, 42.5);
      expect(records.repsAtHeaviest, 8);
    });

    test('History still counts every completed set', () {
      expect(session().completedSetCount, 4);
    });

    test('an exercise with only warm-ups is not a performance', () {
      final onlyWarmUp = WorkoutSession(
        id: 's2',
        workoutId: 'w',
        workoutName: 'W',
        startedAt: DateTime(2026, 10, 5, 9),
        completedAt: DateTime(2026, 10, 5, 10),
        exerciseLogs: [
          testLog(
            'machine_chest_press',
            'Machine Chest Press',
            [(20.0, 10)],
            types: const [SetType.warmUp],
          ),
        ],
      );
      expect(exercisesPerformed([onlyWarmUp]), isEmpty);
      expect(exerciseHistory([onlyWarmUp], 'machine_chest_press'), isEmpty);
      expect(summarize([onlyWarmUp]).sets, 0);
    });
  });

  // ---------------------------------------------------------------------
  group('screens', () {
    void useTallScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Future<void> launchApp(WidgetTester tester) async {
      await tester.pumpWidget(AnthrofitApp(authService: FakeAuthService()));
      await tester.pumpAndSettle();
    }

    Future<void> restartApp(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await launchApp(tester);
    }

    Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> openTab(WidgetTester tester, String label) => tapAndSettle(
      tester,
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );

    Finder workoutCard() => find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('workout-card-'),
    );

    String boxText(WidgetTester tester, int i) => tester
        .widget<TextFormField>(find.byType(TextFormField).at(i))
        .controller!
        .text;

    /// Fields in the set editor: 4 per set (min reps, max reps, load, rest),
    /// in order, then the note.
    Future<void> openNewExerciseEditor(WidgetTester tester) async {
      seedAppData();
      useTallScreen(tester);
      await launchApp(tester);
      await openTab(tester, 'Program');
      await tapAndSettle(tester, find.byKey(const ValueKey('create-program')));
      await completeProgramSetup(tester);
      await tapAndSettle(tester, find.text('Add workout'));
      await tapAndSettle(tester, find.text('Custom'));
      await tapAndSettle(tester, find.text('Add exercises'));
      await tester.tap(find.text('Machine Chest Press'));
      await tester.pump();
      await tapAndSettle(tester, find.text('Add 1 exercise'));
      await tapAndSettle(tester, find.text('Machine Chest Press'));
      expect(find.text('Edit exercise'), findsOneWidget);
    }

    testWidgets('a new exercise shows 3 Working sets and each can be changed', (
      tester,
    ) async {
      await openNewExerciseEditor(tester);

      expect(find.text('Set 1'), findsOneWidget);
      expect(find.text('Set 2'), findsOneWidget);
      expect(find.text('Set 3'), findsOneWidget);
      expect(find.text('Set 4'), findsNothing);
      for (var i = 0; i < 3; i++) {
        final chip = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, 'Working Set').at(i),
        );
        expect(chip.selected, isTrue);
      }
      expect(boxText(tester, 0), '8');
      expect(boxText(tester, 1), '12');
      expect(boxText(tester, 2), ''); // no target load is invented
      expect(boxText(tester, 3), '90');
    });

    testWidgets('warm-up, working and failure sets with their own values', (
      tester,
    ) async {
      await openNewExerciseEditor(tester);
      final fields = find.byType(TextFormField);

      // Set 1 becomes a warm-up: 10 reps, 20 kg, 60s.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Warm-up').at(0));
      await tester.pump();
      await tester.enterText(fields.at(0), '10');
      await tester.enterText(fields.at(1), '');
      await tester.enterText(fields.at(2), '20');
      await tester.enterText(fields.at(3), '60');
      // Sets 2 and 3 stay Working with a 40 kg target.
      await tester.enterText(fields.at(6), '40');
      await tester.enterText(fields.at(10), '40');
      // A failure set is added: no rep target, 40 kg, 120s.
      await tapAndSettle(tester, find.text('Add failure set'));
      expect(find.text('Set 4'), findsOneWidget);
      expect(boxText(tester, 12), ''); // no reps = To Failure
      await tester.enterText(fields.at(14), '40');
      await tester.enterText(fields.at(15), '120');
      await tapAndSettle(tester, find.text('Done'));

      expect(find.text('Edit exercise'), findsNothing);
      expect(
        find.text('4 sets · 1 warm-up, 2 working, 1 failure'),
        findsOneWidget,
      );

      // Reopen: everything was kept.
      await tapAndSettle(tester, find.text('Machine Chest Press'));
      expect(boxText(tester, 0), '10');
      expect(boxText(tester, 1), '');
      expect(boxText(tester, 2), '20');
      expect(boxText(tester, 3), '60');
      expect(boxText(tester, 6), '40');
      expect(boxText(tester, 12), '');
      expect(boxText(tester, 14), '40');
      expect(boxText(tester, 15), '120');
      final failureChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Failure').at(3),
      );
      expect(failureChip.selected, isTrue);
    });

    testWidgets('a working set needs reps, a failure set does not', (
      tester,
    ) async {
      await openNewExerciseEditor(tester);
      final fields = find.byType(TextFormField);

      await tester.enterText(fields.at(0), '');
      await tapAndSettle(tester, find.text('Done'));
      expect(find.text('Enter reps'), findsOneWidget);
      expect(find.text('Edit exercise'), findsOneWidget);

      // Make it a Failure set with no reps: allowed.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Failure').at(0));
      await tester.pump();
      await tester.enterText(fields.at(1), ''); // clear max too
      await tapAndSettle(tester, find.text('Done'));
      expect(find.text('Edit exercise'), findsNothing);
    });

    testWidgets('a set can be removed, but the last one cannot', (
      tester,
    ) async {
      await openNewExerciseEditor(tester);

      await tapAndSettle(tester, find.byTooltip('Remove set').first);
      await tapAndSettle(tester, find.byTooltip('Remove set').first);
      expect(find.text('Set 2'), findsNothing);
      final lastRemove = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline),
      );
      expect(lastRemove.onPressed, isNull);
    });

    testWidgets('sets can be reordered', (tester) async {
      await openNewExerciseEditor(tester);
      await tapAndSettle(tester, find.text('Add warm-up set'));
      bool selected(String label, int i) => tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label).at(i))
          .selected;
      expect(selected('Warm-up', 3), isTrue);

      // Drag the 4th set up past the 3rd.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.drag_handle).at(3)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.moveBy(const Offset(0, -180));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(selected('Warm-up', 2), isTrue);
      expect(selected('Warm-up', 3), isFalse);
    });

    testWidgets(
      'planned sets show in Workout Detail and Exercise Detail, and survive restart',
      (tester) async {
        seedAppData(programs: [_mixedProgram(today)], activeProgramId: 'prog1');
        useTallScreen(tester);
        await launchApp(tester);
        await openTab(tester, 'Program');
        await tapAndSettle(tester, find.text('Test Plan'));
        await tapAndSettle(tester, workoutCard());

        void expectLines() {
          expect(find.text('Warm-up'), findsOneWidget);
          expect(find.text('Working'), findsNWidgets(2));
          expect(find.text('Failure'), findsOneWidget);
          expect(find.text('10 reps · 20 kg · Rest 60s'), findsOneWidget);
          expect(find.text('8–12 reps · 40 kg · Rest 90s'), findsNWidgets(2));
          expect(find.text('To Failure · 40 kg · Rest 120s'), findsOneWidget);
        }

        expectLines();
        expect(find.text('1 exercise · 4 sets'), findsOneWidget);

        // Opened from a workout, Exercise Detail shows the same sets.
        await tapAndSettle(tester, find.text('Machine Chest Press'));
        expect(find.text('This workout'), findsOneWidget);
        expectLines();
        await tester.pageBack();
        await tester.pumpAndSettle();

        // Restart: unchanged.
        await restartApp(tester);
        await openTab(tester, 'Program');
        await tapAndSettle(tester, find.text('Test Plan'));
        await tapAndSettle(tester, workoutCard());
        expectLines();
      },
    );

    testWidgets('Exercise Detail from the library shows no fake prescription', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseDetailScreen(
            exercise: ExerciseLibrary.byId('machine_chest_press')!,
          ),
        ),
      );
      expect(find.text('Primary muscles'), findsOneWidget);
      expect(find.text('This workout'), findsNothing);
      expect(find.textContaining('Rest '), findsNothing);
    });

    testWidgets(
      'a session follows each set: type, target, prefill, rest, and saves the types',
      (tester) async {
        final program = _mixedProgram(today);
        final programBefore = jsonEncode(program.toJson());
        seedAppData(programs: [program], activeProgramId: 'prog1');
        useTallScreen(tester);
        await launchApp(tester);

        String field(int i) => tester
            .widget<TextField>(find.byType(TextField).at(i))
            .controller!
            .text;
        Future<void> complete({String? weight, required String reps}) async {
          if (weight != null) {
            await tester.enterText(find.byType(TextField).at(0), weight);
          }
          await tester.enterText(find.byType(TextField).at(1), reps);
          await tester.tap(find.text('Complete set'));
          await tester.pump();
          await tester.pump();
        }

        await startWorkout(tester);
        expect(
          find.text('4 sets · 1 warm-up, 2 working, 1 failure'),
          findsOneWidget,
        );

        // Set 1: Warm-up. The target load pre-fills the weight.
        expect(find.text('WARM-UP'), findsOneWidget);
        expect(find.text('Target: 10 reps · 20 kg'), findsOneWidget);
        expect(field(0), '20');
        expect(field(1), '');
        await complete(reps: '10');
        expect(find.text('Warm-up · '), findsOneWidget);
        expect(find.text('20 kg × 10'), findsOneWidget);
        expect(find.text('01:00'), findsOneWidget); // that set's own rest
        await closeRestSheet(tester);

        // Set 2: Working. The warm-up's numbers are not carried over.
        expect(find.text('WORKING SET'), findsOneWidget);
        expect(find.text('Target: 8–12 reps · 40 kg'), findsOneWidget);
        expect(field(0), '40');
        expect(field(1), '');
        await complete(weight: '42.5', reps: '8'); // differs from the target
        expect(find.text('42.5 kg × 8'), findsOneWidget);
        expect(find.text('01:30'), findsOneWidget);
        await closeRestSheet(tester);

        // Set 3: the target (40) wins over the previous actual (42.5).
        expect(field(0), '40');
        expect(field(1), '8');
        await complete(reps: '9');
        await closeRestSheet(tester);

        // Set 4: Failure, no rep target.
        expect(find.text('FAILURE'), findsOneWidget);
        expect(find.text('Target: To Failure · 40 kg'), findsOneWidget);
        expect(field(0), '40');
        await complete(reps: '7');

        await tapAndSettle(tester, find.text('Complete workout'));
        await tapAndSettle(tester, find.text('Save workout'));

        // Saved with the types; the program is untouched.
        final data = await tester.runAsync(() => SessionRepository().load());
        final log = data!.sessions.single.exerciseLogs.single;
        expect(log.sets.map((s) => s.setType).toList(), [
          SetType.warmUp,
          SetType.working,
          SetType.working,
          SetType.failure,
        ]);
        expect(log.sets.map((s) => s.weightKg).toList(), [20, 42.5, 40, 40]);
        expect(log.sets.map((s) => s.reps).toList(), [10, 8, 9, 7]);
        expect(log.plannedSets.map((s) => s.targetLoadKg).toList(), [
          20,
          40,
          40,
          40,
        ]);
        expect(
          summarize([data.sessions.single]).volumeKg,
          980,
        ); // warm-up excluded
        final programs = await tester.runAsync(
          () => ProgramRepository().load(),
        );
        expect(jsonEncode(programs!.programs.single.toJson()), programBefore);

        // History shows each set's type, actual values and the saved target.
        // (The session was started from Home, so saving returned there.)
        await openTab(tester, 'Progress');
        await tapAndSettle(tester, find.text('Workout history'));
        await tapAndSettle(
          tester,
          find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('history-card-'),
          ),
        );
        expect(find.text('Set 1 · Warm-up'), findsOneWidget);
        expect(find.text('Set 2 · Working'), findsOneWidget);
        expect(find.text('Set 4 · Failure'), findsOneWidget);
        expect(find.text('20 kg × 10'), findsOneWidget);
        expect(find.text('42.5 kg × 8'), findsOneWidget);
        expect(find.text('Target: 10 reps · 20 kg'), findsOneWidget);
        expect(find.text('Target: To Failure · 40 kg'), findsOneWidget);
        expect(find.textContaining('980 kg'), findsOneWidget);
      },
    );

    testWidgets(
      'a session saved before set types existed still reads correctly',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          AccountStore.guestModeKey: 'guest',
          ProfileRepository.storageKey: jsonEncode(sampleProfile.toJson()),
          SessionRepository.storageKey: jsonEncode({
            'activeSession': null,
            'sessions': [
              {
                'id': 's',
                'workoutId': 'w',
                'workoutName': 'Old Upper',
                'startedAt': '2026-01-01T09:00:00.000',
                'completedAt': '2026-01-01T09:40:00.000',
                'exerciseLogs': [
                  {
                    'id': 'l',
                    'exerciseId': 'machine_chest_press',
                    'plannedExerciseId': 'p',
                    'exerciseName': 'Machine Chest Press',
                    'targetSets': 3,
                    'targetRepMin': 8,
                    'targetRepMax': 12,
                    'targetRestSeconds': 90,
                    'sets': [
                      {
                        'setNumber': 1,
                        'weightKg': 20.0,
                        'reps': 10,
                        'isCompleted': true,
                      },
                    ],
                  },
                ],
              },
            ],
          }),
        });
        useTallScreen(tester);
        await launchApp(tester);
        await openTab(tester, 'Progress');
        await tapAndSettle(tester, find.text('Workout history'));
        await tapAndSettle(
          tester,
          find.byKey(const ValueKey('history-card-s')),
        );

        expect(find.text('Old Upper'), findsOneWidget);
        expect(find.text('Set 1 · Working'), findsOneWidget);
        expect(find.text('20 kg × 10'), findsOneWidget);
        expect(find.text('Target: 8–12 reps'), findsOneWidget);
      },
    );
  });
}
