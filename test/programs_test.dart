import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anthrofit/app.dart';
import 'package:anthrofit/core/program_labels.dart';
import 'package:anthrofit/data/profile_repository.dart';
import 'package:anthrofit/data/program_repository.dart';
import 'package:anthrofit/data/session_repository.dart';
import 'package:anthrofit/data/workout_templates.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/state/program_controller.dart';
import 'package:anthrofit/state/session_controller.dart';

import 'test_helpers.dart';

/// A program of three workouts (Push, Pull, Legs). One workout per entry of
/// [days], in order, so days: [Mon, Wed, Fri] gives Mon -> Push, Wed -> Pull,
/// Fri -> Legs.
TrainingProgram _prog(
  String id,
  String name, {
  List<Weekday> days = const [],
  TrainingGoal? goal,
  bool archived = false,
}) {
  final workouts = [
    Workout(
      id: '$id-w1',
      name: 'Push',
      exercises: [testPlanned('$id-p1', 'barbell_bench_press')],
    ),
    Workout(
      id: '$id-w2',
      name: 'Pull',
      exercises: [testPlanned('$id-p2', 'lat_pulldown')],
    ),
    Workout(
      id: '$id-w3',
      name: 'Legs',
      exercises: [testPlanned('$id-p3', 'leg_press')],
    ),
  ];
  return TrainingProgram(
    id: id,
    name: name,
    goal: goal,
    archived: archived,
    workouts: workouts,
    schedule: [
      for (var i = 0; i < days.length; i++)
        ScheduledWorkout(day: days[i], workoutId: workouts[i % 3].id),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

const _mwf = [Weekday.monday, Weekday.wednesday, Weekday.friday];
const _mttf = [
  Weekday.monday,
  Weekday.tuesday,
  Weekday.thursday,
  Weekday.friday,
];

void main() {
  // The exercise catalogue is an asset now, so it has to be loaded.
  useExerciseLibrary();

  final now = DateTime.now();

  // ---------------------------------------------------------------------
  group('program model', () {
    test('goal and archived survive JSON; old programs have neither', () {
      final p = _prog('a', 'A', goal: TrainingGoal.getStronger, archived: true);
      final back = TrainingProgram.fromJson(
        jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>,
      );
      expect(back.goal, TrainingGoal.getStronger);
      expect(back.archived, isTrue);

      final old = TrainingProgram.fromJson({
        'id': 'old',
        'name': 'Old',
        'workouts': <dynamic>[],
        'schedule': <dynamic>[],
      });
      expect(old.goal, isNull);
      expect(old.archived, isFalse);

      final odd = TrainingProgram.fromJson({
        'id': 'x',
        'name': 'X',
        'goal': 'madeUp',
      });
      expect(odd.goal, isNull);
    });

    test('status text and compact days', () {
      final a = _prog('a', 'A', days: _mwf);
      final b = _prog('b', 'B', days: _mttf, archived: true);
      final c = _prog('c', 'C');
      expect(programStatusLine(a, isActive: true), 'Active · M/W/F');
      expect(programStatusLine(b, isActive: false), 'Archived · M/T/Th/F');
      expect(
        programStatusLine(c, isActive: false),
        'Not active · No training days',
      );
      expect(compactDays([Weekday.saturday, Weekday.sunday]), 'Sa/Su');
    });

    test('a duplicate is fully independent', () {
      final original = _prog(
        'orig',
        'Push Pull Legs',
        days: _mwf,
        goal: TrainingGoal.buildMuscle,
      );
      final copy = original.duplicate();

      expect(copy.id, isNot(original.id));
      expect(copy.name, 'Push Pull Legs Copy');
      expect(copy.goal, TrainingGoal.buildMuscle);
      expect(copy.archived, isFalse);

      final originalIds = {
        for (final w in original.workouts) w.id,
        for (final w in original.workouts) ...w.exercises.map((e) => e.id),
      };
      final copyIds = {
        for (final w in copy.workouts) w.id,
        for (final w in copy.workouts) ...w.exercises.map((e) => e.id),
      };
      expect(originalIds.intersection(copyIds), isEmpty);

      // Same content, same library exercises, same planned sets.
      expect(copy.workouts.map((w) => w.name).toList(), [
        'Push',
        'Pull',
        'Legs',
      ]);
      expect(
        copy.workouts.first.exercises.first.exerciseId,
        'barbell_bench_press',
      );
      expect(copy.workouts.first.exercises.first.plannedSets.length, 3);

      // The schedule points at the COPY's workouts, on the same days.
      expect(copy.trainingDays, _mwf);
      expect(copy.workoutForDay(Weekday.monday)!.id, copy.workouts.first.id);
      expect(
        copy.workouts.map((w) => w.id).toSet().intersection({
          for (final w in original.workouts) w.id,
        }),
        isEmpty,
      );

      expect(original.duplicate(name: 'Mine').name, 'Mine');
    });
  });

  // ---------------------------------------------------------------------
  group('ProgramController', () {
    Future<ProgramController> fresh() async {
      seedNoProfile();
      final c = ProgramController(ProgramRepository());
      await c.load();
      return c;
    }

    Future<ProgramController> reload() async {
      final c = ProgramController(ProgramRepository());
      await c.load();
      return c;
    }

    test('two programs can be created and both survive a restart', () async {
      final c = await fresh();
      await c.saveProgram(
        _prog('a', 'Program A', days: _mwf, goal: TrainingGoal.buildMuscle),
      );
      await c.saveProgram(
        _prog('b', 'Program B', days: _mttf, goal: TrainingGoal.getStronger),
      );

      final again = await reload();
      expect(again.programs.map((p) => p.name).toList(), [
        'Program A',
        'Program B',
      ]);
      expect(again.programById('a')!.goal, TrainingGoal.buildMuscle);
      expect(again.programById('b')!.goal, TrainingGoal.getStronger);
      expect(again.programById('b')!.trainingDays, _mttf);
      expect(again.programById('a')!.workouts.length, 3);
    });

    test('only the first program ever created becomes active', () async {
      final c = await fresh();
      await c.saveProgram(_prog('a', 'A'));
      expect(c.activeProgramId, 'a');
      await c.saveProgram(_prog('b', 'B'));
      expect(c.activeProgramId, 'a'); // B is saved but not active
    });

    test('editing one program does not touch another', () async {
      final c = await fresh();
      await c.saveProgram(_prog('a', 'A', days: _mwf));
      await c.saveProgram(_prog('b', 'B', days: _mwf));
      final bBefore = jsonEncode(c.programById('b')!.toJson());

      final a = c.programById('a')!;
      await c.saveProgram(
        a.copyWith(
          name: 'A renamed',
          goal: TrainingGoal.loseFat,
          workouts: [a.workouts.first.copyWith(name: 'Only one')],
          schedule: const [],
        ),
      );

      expect(c.programById('a')!.name, 'A renamed');
      expect(c.programById('a')!.workouts.length, 1);
      expect(jsonEncode(c.programById('b')!.toJson()), bBefore);
      expect(jsonEncode((await reload()).programById('b')!.toJson()), bBefore);
    });

    test(
      'activating B makes A inactive, loses nothing, and persists',
      () async {
        final c = await fresh();
        await c.saveProgram(_prog('a', 'A', days: _mwf));
        await c.saveProgram(_prog('b', 'B', days: _mttf));
        final aBefore = jsonEncode(c.programById('a')!.toJson());

        await c.setActiveProgram('b');
        expect(c.activeProgramId, 'b');
        expect(c.activeProgram!.name, 'B');
        expect(c.programs.where((p) => p.id == c.activeProgramId).length, 1);
        expect(jsonEncode(c.programById('a')!.toJson()), aBefore);

        expect((await reload()).activeProgramId, 'b');
      },
    );

    test(
      'archiving the active program clears it, and nothing else activates',
      () async {
        final c = await fresh();
        await c.saveProgram(_prog('a', 'A', days: _mwf));
        await c.saveProgram(_prog('b', 'B'));

        await c.archiveProgram('a');
        expect(c.activeProgramId, isNull);
        expect(c.activeProgram, isNull);
        expect(c.programById('a')!.archived, isTrue);
        expect(c.programById('a')!.workouts.length, 3); // nothing deleted
        expect(c.programById('b')!.archived, isFalse);

        final again = await reload();
        expect(again.activeProgramId, isNull);
        expect(again.programById('a')!.archived, isTrue);
      },
    );

    test(
      'archiving a program that is not active leaves the active one alone',
      () async {
        final c = await fresh();
        await c.saveProgram(_prog('a', 'A'));
        await c.saveProgram(_prog('b', 'B'));
        await c.archiveProgram('b');
        expect(c.activeProgramId, 'a');
        expect(c.programById('b')!.archived, isTrue);
      },
    );

    test('an archived program can be activated again', () async {
      final c = await fresh();
      await c.saveProgram(_prog('a', 'A'));
      await c.archiveProgram('a');
      expect(c.activeProgramId, isNull);

      await c.setActiveProgram('a');
      expect(c.activeProgramId, 'a');
      expect(c.programById('a')!.archived, isFalse);
      expect((await reload()).activeProgram!.id, 'a');
    });

    test(
      'a saved active id that points at an archived program is ignored',
      () async {
        SharedPreferences.setMockInitialValues({
          ProgramRepository.storageKey: jsonEncode({
            'activeProgramId': 'a',
            'programs': [_prog('a', 'A', archived: true).toJson()],
          }),
        });
        final c = await reload();
        expect(c.activeProgramId, isNull);
        expect(c.programs.single.archived, isTrue);
      },
    );

    test(
      'deleting removes only that program; deleting the active one clears it',
      () async {
        final c = await fresh();
        await c.saveProgram(_prog('a', 'A'));
        await c.saveProgram(_prog('b', 'B'));

        await c.deleteProgram('b'); // not active
        expect(c.programs.map((p) => p.id).toList(), ['a']);
        expect(c.activeProgramId, 'a');

        await c.deleteProgram('a'); // active
        expect(c.programs, isEmpty);
        expect(c.activeProgramId, isNull);
        expect((await reload()).programs, isEmpty);
      },
    );

    test('duplicating saves a separate, inactive copy', () async {
      final c = await fresh();
      await c.saveProgram(_prog('a', 'Push Pull Push', days: _mwf));
      final copy = await c.duplicateProgram('a');

      expect(copy, isNotNull);
      expect(c.programs.length, 2);
      expect(c.activeProgramId, 'a'); // the copy is not active
      expect(copy!.name, 'Push Pull Push Copy');

      // Edit the copy; the original does not change.
      final originalBefore = jsonEncode(c.programById('a')!.toJson());
      await c.saveProgram(
        copy.copyWith(
          name: 'Renamed copy',
          workouts: [copy.workouts.first.copyWith(name: 'Changed')],
        ),
      );
      expect(jsonEncode(c.programById('a')!.toJson()), originalBefore);
      expect(c.programById(copy.id)!.workouts.first.name, 'Changed');

      expect(await c.duplicateProgram('missing'), isNull);
    });

    test('the program goal is separate from the profile goal', () async {
      seedNoProfile();
      await ProfileRepository().save(sampleProfile); // Build muscle
      final c = ProgramController(ProgramRepository());
      await c.load();
      await c.saveProgram(_prog('a', 'A', goal: TrainingGoal.getStronger));

      expect(c.programById('a')!.goal, TrainingGoal.getStronger);
      final profile = await ProfileRepository().load();
      expect(profile!.goal, TrainingGoal.buildMuscle);
    });

    test(
      'generated programs have no training days until the user picks some',
      () async {
        final workouts = buildWorkoutsForProgram(ProgramTemplate.pushPullLegs);
        final c = await fresh();
        await c.saveProgram(
          TrainingProgram(
            id: 'g',
            name: 'Generated',
            goal: TrainingGoal.buildMuscle,
            workouts: workouts,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );
        expect(c.programById('g')!.schedule, isEmpty);
        expect(c.programById('g')!.trainingDays, isEmpty);

        // The user assigns Mon, Tue, Thu to Push, Pull, Legs: exactly those days.
        final g = c.programById('g')!;
        await c.saveProgram(
          g.copyWith(
            schedule: [
              ScheduledWorkout(day: Weekday.monday, workoutId: workouts[0].id),
              ScheduledWorkout(day: Weekday.tuesday, workoutId: workouts[1].id),
              ScheduledWorkout(
                day: Weekday.thursday,
                workoutId: workouts[2].id,
              ),
            ],
          ),
        );
        final again = (await reload()).programById('g')!;
        expect(again.trainingDays, [
          Weekday.monday,
          Weekday.tuesday,
          Weekday.thursday,
        ]);
        expect(again.workoutForDay(Weekday.thursday)!.name, 'Legs');
        expect(again.workoutForDay(Weekday.wednesday), isNull); // no fake day
      },
    );
  });

  // ---------------------------------------------------------------------
  group('history stays readable', () {
    Future<void> logAll(SessionController s) async {
      for (final log in s.activeSession!.exerciseLogs) {
        for (final set in log.sets) {
          await s.logSet(
            exerciseLogId: log.id,
            setNumber: set.setNumber,
            weightKg: 40,
            reps: 10,
          );
        }
      }
    }

    test('a session keeps the program name it was done under', () async {
      seedNoProfile();
      final programs = ProgramController(ProgramRepository());
      await programs.load();
      await programs.saveProgram(_prog('a', 'Push Pull Push', days: _mwf));
      final sessions = SessionController(SessionRepository());
      await sessions.load();

      final program = programs.programById('a')!;
      await sessions.startSession(program, program.workouts.first);
      await logAll(sessions);
      await sessions.completeSession();

      // Rename the program. The saved session does not follow.
      await programs.saveProgram(program.copyWith(name: 'Hypertrophy PPL'));
      expect(programs.programById('a')!.name, 'Hypertrophy PPL');
      final reloaded = SessionController(SessionRepository());
      await reloaded.load();
      expect(reloaded.completedSessions.single.programName, 'Push Pull Push');
      expect(reloaded.completedSessions.single.programId, 'a');
    });

    test(
      'archiving or deleting a program keeps its completed sessions',
      () async {
        seedNoProfile();
        final programs = ProgramController(ProgramRepository());
        await programs.load();
        await programs.saveProgram(_prog('a', 'A', days: _mwf));
        final sessions = SessionController(SessionRepository());
        await sessions.load();
        final program = programs.programById('a')!;
        await sessions.startSession(program, program.workouts.first);
        await logAll(sessions);
        await sessions.completeSession();

        await programs.archiveProgram('a');
        await programs.deleteProgram('a');
        expect(programs.programs, isEmpty);

        final reloaded = SessionController(SessionRepository());
        await reloaded.load();
        final session = reloaded.completedSessions.single;
        expect(session.programName, 'A');
        expect(session.workoutName, 'Push');
        expect(session.completedSetCount, 3);
      },
    );

    test('a session saved before program names existed still loads', () {
      final s = WorkoutSession.fromJson({
        'id': 's',
        'programId': 'gone',
        'workoutId': 'w',
        'workoutName': 'Old',
        'startedAt': '2026-01-01T09:00:00.000',
      });
      expect(s.programName, '');
      expect(s.programId, 'gone');
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

    /// Program A (active, M/W/F), B (archived, M/T/Th/F), C (not active, no days).
    void seedThree({List<WorkoutSession> sessions = const []}) {
      seedAppData(
        programs: [
          _prog('a', 'Program A', days: _mwf, goal: TrainingGoal.buildMuscle),
          _prog(
            'b',
            'Program B',
            days: _mttf,
            goal: TrainingGoal.getStronger,
            archived: true,
          ),
          _prog('c', 'Program C'),
        ],
        activeProgramId: 'a',
        sessions: sessions,
      );
    }

    bool isSelected(WidgetTester tester, String chipLabel) => tester
        .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, chipLabel))
        .selected;

    testWidgets('My programs shows each program like a folder', (tester) async {
      seedThree();
      useTallScreen(tester);
      await launchApp(tester);
      await openTab(tester, 'Program');

      expect(find.text('My programs'), findsOneWidget);
      expect(find.text('Program A'), findsOneWidget);
      expect(find.text('Active · M/W/F'), findsOneWidget);
      expect(find.text('Archived · M/T/Th/F'), findsOneWidget);
      expect(find.text('Not active · No training days'), findsOneWidget);
      expect(find.text('3 workouts'), findsNWidgets(3));
      expect(find.text('Create program'), findsOneWidget);
    });

    testWidgets('program detail shows goal, schedule and workouts', (
      tester,
    ) async {
      seedThree();
      useTallScreen(tester);
      await launchApp(tester);
      await openTab(tester, 'Program');
      await tapAndSettle(tester, find.text('Program A'));

      expect(find.text('Goal'), findsOneWidget);
      expect(find.text('Build muscle'), findsOneWidget);
      // The week as day boxes: training days show a workout, not Rest.
      Finder restOn(String day) => find.descendant(
        of: find.byKey(ValueKey('schedule-day-$day')),
        matching: find.text('Rest'),
      );
      expect(restOn('monday'), findsNothing);
      expect(restOn('friday'), findsNothing);
      expect(restOn('tuesday'), findsOneWidget);
      expect(find.text('Push'), findsWidgets);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Active program'), findsOneWidget);

      // A program saved before goals existed says so instead of guessing.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.text('Program C'));
      expect(find.text('Not set'), findsOneWidget);
      expect(find.textContaining('No training days yet'), findsOneWidget);
    });

    testWidgets('only actions that make sense are shown for each state', (
      tester,
    ) async {
      seedThree();
      useTallScreen(tester);
      await launchApp(tester);
      await openTab(tester, 'Program');

      // Active: no Activate.
      await tapAndSettle(tester, find.text('Program A'));
      expect(find.text('Activate'), findsNothing);
      expect(find.text('Archive'), findsOneWidget);
      expect(find.text('Duplicate'), findsOneWidget);
      // Each part is edited where it lives, so there is no Edit program.
      expect(find.byTooltip('Rename program'), findsOneWidget);
      expect(find.byTooltip('Edit schedule'), findsOneWidget);
      expect(find.text('Delete program'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Archived: Activate, but no Archive.
      await tapAndSettle(tester, find.text('Program B'));
      expect(find.text('Activate'), findsOneWidget);
      expect(find.text('Archive'), findsNothing);
      expect(find.text('Duplicate'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Not active, not archived: both.
      await tapAndSettle(tester, find.text('Program C'));
      expect(find.text('Activate'), findsOneWidget);
      expect(find.text('Archive'), findsOneWidget);
    });

    testWidgets('activating switches the active program and survives restart', (
      tester,
    ) async {
      seedThree();
      useTallScreen(tester);
      await launchApp(tester);
      await openTab(tester, 'Program');

      await tapAndSettle(tester, find.text('Program C'));
      await tapAndSettle(tester, find.text('Activate'));
      expect(find.text('Program C is now active'), findsOneWidget);
      expect(find.text('Active program'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Active · No training days'), findsOneWidget); // C
      expect(find.text('Not active · M/W/F'), findsOneWidget); // A
      expect(find.text('Active program: Program C'), findsOneWidget);

      await restartApp(tester);
      await openTab(tester, 'Program');
      expect(find.text('Active · No training days'), findsOneWidget);
      expect(find.text('Not active · M/W/F'), findsOneWidget);
      expect(find.text('Archived · M/T/Th/F'), findsOneWidget);
    });

    testWidgets('an archived program can be activated again', (tester) async {
      seedThree();
      useTallScreen(tester);
      await launchApp(tester);
      await openTab(tester, 'Program');

      await tapAndSettle(tester, find.text('Program B'));
      await tapAndSettle(tester, find.text('Activate'));
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Active · M/T/Th/F'), findsOneWidget);
      expect(find.text('Archived · M/T/Th/F'), findsNothing);
      expect(find.text('Not active · M/W/F'), findsOneWidget);
    });

    testWidgets('archiving the active program leaves nothing active', (
      tester,
    ) async {
      seedThree();
      useTallScreen(tester);
      await launchApp(tester);
      await openTab(tester, 'Program');

      await tapAndSettle(tester, find.text('Program A'));
      await tapAndSettle(tester, find.text('Archive'));
      expect(
        find.text('Program A archived. No program is active now.'),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();

      // It is still listed, now archived, and no other program took over.
      expect(find.text('Archived · M/W/F'), findsOneWidget);
      expect(find.text('Not active · No training days'), findsOneWidget); // C
      expect(find.textContaining('Active ·'), findsNothing);
      expect(find.text('No active program'), findsOneWidget);
      expect(find.text('Start workout'), findsNothing);

      // Home says so too, and offers to create one.
      await openTab(tester, 'Home');
      expect(find.text('No active program'), findsOneWidget);
      expect(find.text('Create program'), findsOneWidget);
      expect(find.text('Start workout'), findsNothing);

      // Restart: still none active, A still archived.
      await restartApp(tester);
      expect(find.text('No active program'), findsOneWidget);
      await openTab(tester, 'Program');
      expect(find.text('Archived · M/W/F'), findsOneWidget);
    });

    testWidgets('duplicating creates an independent, inactive copy', (
      tester,
    ) async {
      seedThree();
      useTallScreen(tester);
      await launchApp(tester);
      await openTab(tester, 'Program');

      await tapAndSettle(tester, find.text('Program A'));
      await tapAndSettle(tester, find.text('Duplicate'));
      expect(find.text('Created Program A Copy'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Program A'), findsOneWidget);
      expect(find.text('Program A Copy'), findsOneWidget);
      expect(find.text('Active · M/W/F'), findsOneWidget); // the original
      expect(find.text('Not active · M/W/F'), findsOneWidget); // the copy

      // Rename the copy. The original keeps its name.
      await tapAndSettle(tester, find.text('Program A Copy'));
      await tapAndSettle(tester, find.byTooltip('Rename program'));
      await tester.enterText(
        find.byKey(const ValueKey('rename-field')),
        'Copy renamed',
      );
      await tapAndSettle(tester, find.text('Save'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Program A'), findsOneWidget);
      expect(find.text('Copy renamed'), findsOneWidget);
      expect(find.text('Program A Copy'), findsNothing);
    });

    testWidgets('deleting asks first, then removes only that program', (
      tester,
    ) async {
      seedThree();
      useTallScreen(tester);
      await launchApp(tester);
      await openTab(tester, 'Program');

      await tapAndSettle(tester, find.text('Program A'));
      await tapAndSettle(tester, find.text('Delete program'));
      expect(find.text('Delete this program?'), findsOneWidget);
      expect(
        find.text(
          'This will remove the program and its workouts. '
          'Completed workout history will be kept.',
        ),
        findsOneWidget,
      );

      await tapAndSettle(tester, find.text('Cancel')); // nothing happens
      expect(find.text('Delete this program?'), findsNothing);
      expect(find.text('Program A'), findsWidgets);

      await tapAndSettle(tester, find.text('Delete program'));
      await tapAndSettle(tester, find.text('Delete'));

      // Back on My programs: A is gone, B and C are untouched, none is active.
      expect(find.text('Program A'), findsNothing);
      expect(find.text('Program B'), findsOneWidget);
      expect(find.text('Program C'), findsOneWidget);
      expect(find.text('Archived · M/T/Th/F'), findsOneWidget);
      expect(find.text('No active program'), findsOneWidget);
    });

    testWidgets('a deleted program does not delete history', (tester) async {
      final done = DateTime(now.year, now.month, now.day, 10);
      seedThree(
        sessions: [
          WorkoutSession(
            id: 's1',
            programId: 'a',
            programName: 'Program A',
            workoutId: 'a-w1',
            workoutName: 'Push',
            startedAt: done.subtract(const Duration(minutes: 40)),
            completedAt: done,
            exerciseLogs: [
              testLog('barbell_bench_press', 'Barbell Bench Press', [
                (40.0, 10),
              ]),
            ],
          ),
        ],
      );
      useTallScreen(tester);
      await launchApp(tester);
      await openTab(tester, 'Program');
      await tapAndSettle(tester, find.text('Program A'));
      await tapAndSettle(tester, find.text('Delete program'));
      await tapAndSettle(tester, find.text('Delete'));
      expect(find.text('Program A'), findsNothing);

      await openTab(tester, 'Progress');
      await tapAndSettle(tester, find.text('Workout history'));
      await tapAndSettle(tester, find.byKey(const ValueKey('history-card-s1')));
      await tapAndSettle(tester, find.byKey(const ValueKey('history-details')));
      expect(find.text('Push'), findsOneWidget);
      expect(find.text('Program'), findsOneWidget); // the label
      expect(find.text('Program A'), findsOneWidget); // its saved name
      expect(find.text('40 kg × 10'), findsOneWidget);
    });

    testWidgets('renaming a program does not rename old history', (
      tester,
    ) async {
      final done = DateTime(now.year, now.month, now.day, 10);
      seedAppData(
        programs: [
          _prog(
            'a',
            'Push Pull Push',
            days: _mwf,
            goal: TrainingGoal.buildMuscle,
          ),
        ],
        activeProgramId: 'a',
        sessions: [
          WorkoutSession(
            id: 's1',
            programId: 'a',
            programName: 'Push Pull Push',
            workoutId: 'a-w1',
            workoutName: 'Push',
            startedAt: done.subtract(const Duration(minutes: 40)),
            completedAt: done,
            exerciseLogs: [
              testLog('barbell_bench_press', 'Barbell Bench Press', [
                (40.0, 10),
              ]),
            ],
          ),
        ],
      );
      useTallScreen(tester);
      await launchApp(tester);
      await openTab(tester, 'Program');
      await tapAndSettle(tester, find.text('Push Pull Push'));
      await tapAndSettle(tester, find.byTooltip('Rename program'));
      await tester.enterText(
        find.byKey(const ValueKey('rename-field')),
        'Hypertrophy PPL',
      );
      await tapAndSettle(tester, find.text('Save'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Hypertrophy PPL'), findsOneWidget);

      await openTab(tester, 'Progress');
      await tapAndSettle(tester, find.text('Workout history'));
      await tapAndSettle(tester, find.byKey(const ValueKey('history-card-s1')));
      await tapAndSettle(tester, find.byKey(const ValueKey('history-details')));
      expect(find.text('Push Pull Push'), findsOneWidget);
      expect(find.text('Hypertrophy PPL'), findsNothing);
    });

    testWidgets('create: goal starts as the profile goal, can be overridden, '
        'and the profile is not changed', (tester) async {
      seedAppData();
      useTallScreen(tester);
      await launchApp(tester);
      await openTab(tester, 'Program');
      await tapAndSettle(tester, find.byKey(const ValueKey('create-program')));
      expect(find.text('Set up program'), findsOneWidget);
      await tapAndSettle(tester, find.text('Continue'));

      // 1. Goal: the profile goal (Build muscle) is preselected, and can be
      // overridden for this program only.
      expect(
        find.text('What is the main goal for this program?'),
        findsOneWidget,
      );
      expect(isSelected(tester, 'Build muscle'), isTrue);
      expect(isSelected(tester, 'Get stronger'), isFalse);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Get stronger'));
      await tester.pump();
      expect(isSelected(tester, 'Get stronger'), isTrue);
      expect(isSelected(tester, 'Build muscle'), isFalse);

      // 2. The structure step. The default name follows the structure until
      // the user types one of their own.
      await advanceSetupTo(
        tester,
        setupStructureTile(ProgramTemplate.pushPullLegs),
      );
      await tapAndSettle(tester, setupStructureTile(ProgramTemplate.custom));
      await tapSetupContinue(tester);

      String nameText() => tester
          .widget<TextField>(find.byKey(const ValueKey('program-name')))
          .controller!
          .text;
      expect(nameText(), 'My Program');

      // Going back and choosing another structure updates the default name.
      await tapAndSettle(tester, setupBackButton);
      await tapAndSettle(
        tester,
        setupStructureTile(ProgramTemplate.pushPullLegs),
      );
      await tapSetupContinue(tester);
      expect(nameText(), 'Push Pull Legs Program');

      // Once the user names it themselves, the structure stops overwriting it.
      await tester.enterText(
        find.byKey(const ValueKey('program-name')),
        'Summer Cut',
      );
      await tester.pump();
      await tapAndSettle(tester, setupBackButton);
      await tapAndSettle(
        tester,
        setupStructureTile(ProgramTemplate.upperLower),
      );
      await tapSetupContinue(tester);
      expect(nameText(), 'Summer Cut');
      await tapAndSettle(tester, setupBackButton);
      await tapAndSettle(
        tester,
        setupStructureTile(ProgramTemplate.pushPullLegs),
      );
      await tapSetupContinue(tester);
      expect(nameText(), 'Summer Cut');

      // 3. Generate.
      await tapSetupContinue(tester);

      // 4. Review: the generated workouts, the goal and the name carried over.
      expect(find.text('New program'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'Summer Cut',
      );
      expect(
        isSelected(tester, 'Get stronger'),
        isTrue,
      ); // carried into the planner
      expect(find.text('Push'), findsOneWidget);
      expect(find.text('Pull'), findsOneWidget);
      expect(find.text('Legs'), findsOneWidget);
      expect(
        find.text('Schedule'),
        findsNothing,
      ); // no days picked for the user
      expect(
        find.textContaining('Your profile: 4 training days per week'),
        findsOneWidget,
      );

      // 5. The user picks the real days, and which workout goes on each.
      for (final day in ['Mon', 'Wed', 'Fri']) {
        await tester.tap(find.widgetWithText(FilterChip, day));
        await tester.pump();
      }
      await tester.tap(find.widgetWithText(FilterChip, 'Push').at(0)); // Mon
      await tester.tap(find.widgetWithText(FilterChip, 'Pull').at(1)); // Wed
      await tester.tap(find.widgetWithText(FilterChip, 'Legs').at(2)); // Fri
      await tester.pump();
      await tapAndSettle(tester, find.text('Save program'));

      // Saved: first program ever, so active. Folder card shows the real days.
      expect(find.text('Summer Cut'), findsOneWidget);
      expect(find.text('Active · M/W/F'), findsOneWidget);
      expect(find.text('3 workouts'), findsOneWidget);

      // Goal, schedule and structure survive a restart.
      await restartApp(tester);
      await openTab(tester, 'Program');
      expect(find.text('Active · M/W/F'), findsOneWidget);
      await tapAndSettle(tester, find.text('Summer Cut'));
      expect(find.text('Get stronger'), findsOneWidget);
      // The week as day boxes: training days show a workout, not Rest.
      Finder restOn(String day) => find.descendant(
        of: find.byKey(ValueKey('schedule-day-$day')),
        matching: find.text('Rest'),
      );
      expect(restOn('monday'), findsNothing);
      expect(restOn('friday'), findsNothing);
      expect(restOn('tuesday'), findsOneWidget);
      expect(find.text('Push'), findsWidgets);

      // The profile goal never changed.
      final profile = await tester.runAsync(() => ProfileRepository().load());
      expect(profile!.goal, TrainingGoal.buildMuscle);
      final saved = await tester.runAsync(() => ProgramRepository().load());
      expect(saved!.programs.single.goal, TrainingGoal.getStronger);
    });

    testWidgets('create: a second program is saved but not made active', (
      tester,
    ) async {
      seedAppData(
        programs: [
          _prog('a', 'Program A', days: _mwf, goal: TrainingGoal.buildMuscle),
        ],
        activeProgramId: 'a',
      );
      useTallScreen(tester);
      await launchApp(tester);
      await openTab(tester, 'Program');

      await tapAndSettle(tester, find.byKey(const ValueKey('create-program')));
      await completeProgramSetup(tester, template: ProgramTemplate.fullBody);
      expect(find.text('Full Body'), findsOneWidget); // the generated workout
      await tester.tap(find.widgetWithText(FilterChip, 'Tue'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterChip, 'Full Body'));
      await tester.pump();
      await tapAndSettle(tester, find.text('Save program'));

      expect(find.text('Active · M/W/F'), findsOneWidget); // A is still active
      expect(find.text('Not active · T'), findsOneWidget); // the new one
      expect(find.text('Full Body Program'), findsOneWidget);
    });

    testWidgets('Custom starts with no workouts', (tester) async {
      seedAppData();
      useTallScreen(tester);
      await launchApp(tester);
      await openTab(tester, 'Program');
      await tapAndSettle(tester, find.byKey(const ValueKey('create-program')));
      await completeProgramSetup(tester);

      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'My Program',
      );
      expect(find.byTooltip('Remove workout'), findsNothing);
      expect(find.text('Add workout'), findsOneWidget);
    });
  });
}
