import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anthrofit/app.dart';
import 'package:anthrofit/core/format.dart';
import 'package:anthrofit/data/profile_repository.dart';
import 'package:anthrofit/data/program_repository.dart';
import 'package:anthrofit/data/session_repository.dart';
import 'package:anthrofit/data/training_stats.dart';
import 'package:anthrofit/models/models.dart';

import 'test_helpers.dart';

// ---------------------------------------------------------------------------
// Builders
// ---------------------------------------------------------------------------

PlannedExercise _chestPress({int sets = 3}) =>
    testPlanned('p-chest', 'machine_chest_press', sets: sets);

/// Upper A (chest press) on [upperDay]. Lower A (leg press) on [lowerDay], if given.
TrainingProgram _program(Weekday upperDay, {Weekday? lowerDay}) {
  return TrainingProgram(
    id: 'prog1',
    name: 'Test Plan',
    workouts: [
      Workout(id: 'w-upper', name: 'Upper A', exercises: [_chestPress()]),
      if (lowerDay != null)
        Workout(
          id: 'w-lower',
          name: 'Lower A',
          exercises: [testPlanned('p-leg', 'leg_press', sets: 1, rest: 60)],
        ),
    ],
    schedule: [
      ScheduledWorkout(day: upperDay, workoutId: 'w-upper'),
      if (lowerDay != null)
        ScheduledWorkout(day: lowerDay, workoutId: 'w-lower'),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

SetLog _set(int n, double? weight, int reps) => SetLog(
  setNumber: n,
  weightKg: weight,
  reps: reps,
  isCompleted: true,
  completedAt: DateTime(2026, 1, 1),
);

void main() {
  // The exercise catalogue is an asset now, so it has to be loaded.
  useExerciseLibrary();

  final now = DateTime.now();
  final today = Weekday.fromDateTime(now);
  final otherDay = Weekday.values[(today.index + 1) % 7];

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
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );

  /// Weight (optional) and reps, then Complete set.
  Future<void> completeSet(
    WidgetTester tester, {
    String? weight,
    required String reps,
  }) async {
    final fields = find.byType(TextField);
    if (weight != null) await tester.enterText(fields.at(0), weight);
    await tester.enterText(fields.at(1), reps);
    await tester.tap(find.text('Complete set'));
    await tester.pump();
    await tester.pump();
    await closeRestSheet(tester);
  }

  Finder workoutCard() => find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('workout-card-'),
  );

  // ---------------------------------------------------------------------
  group('saved data that cannot be read', () {
    test('is kept as a copy and treated as empty, never a crash', () async {
      SharedPreferences.setMockInitialValues({
        ProfileRepository.storageKey: 'not json',
        ProgramRepository.storageKey: '[1, 2]',
        SessionRepository.storageKey: '{broken',
      });

      expect(await ProfileRepository().load(), isNull);
      expect((await ProgramRepository().load()).programs, isEmpty);
      expect((await SessionRepository().load()).sessions, isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('user_profile.unreadable'), 'not json');
      expect(prefs.getString('program_data.unreadable'), '[1, 2]');
      expect(prefs.getString('session_data.unreadable'), '{broken');
    });

    test('an older session without newer fields still loads', () async {
      // Saved before "targetNote" existed.
      SharedPreferences.setMockInitialValues({
        SessionRepository.storageKey:
            '{"activeSession":null,"sessions":[{"id":"s","workoutId":"w",'
            '"workoutName":"Old","startedAt":"2026-01-01T09:00:00.000",'
            '"completedAt":"2026-01-01T09:40:00.000","exerciseLogs":[{"id":"l",'
            '"exerciseId":"x","plannedExerciseId":"p","exerciseName":"Thing",'
            '"targetSets":3,"targetRepMin":8,"targetRepMax":12,'
            '"targetRestSeconds":90,"sets":[{"setNumber":1,"weightKg":20.0,'
            '"reps":10,"isCompleted":true}]}]}]}',
      });
      final data = await SessionRepository().load();
      final session = data.sessions.single;
      expect(session.workoutName, 'Old');
      expect(session.exerciseLogs.single.targetNote, '');
      // The old shared target became three Working planned sets, and the old
      // logged set (which had no type) loads as Working.
      final log = session.exerciseLogs.single;
      expect(log.plannedSets.length, 3);
      expect(log.plannedSets.first.setType, SetType.working);
      expect(log.plannedSets.first.repRangeLabel, '8–12');
      expect(log.plannedSets.first.restSeconds, 90);
      expect(log.sets.single.setType, SetType.working);
      expect(session.duration, const Duration(minutes: 40));
      expect(summarize([session]).volumeKg, 200);
    });
  });

  group('formatting never shows NaN or Infinity', () {
    test('numbers', () {
      expect(formatNumber(double.infinity), '—');
      expect(formatNumber(double.nan), '—');
      expect(formatThousands(double.infinity), '—');
      expect(formatNumber(42.5), '42.5');
    });

    test('relative dates and greeting', () {
      final t = DateTime(2026, 10, 5);
      expect(formatRelativeDate(DateTime(2026, 10, 5, 23), today: t), 'Today');
      expect(formatRelativeDate(DateTime(2026, 10, 4), today: t), 'Yesterday');
      expect(
        formatRelativeDate(DateTime(2026, 9, 30), today: t),
        'September 30',
      );
      expect(greetingFor(5), 'Good morning');
      expect(greetingFor(11), 'Good morning');
      expect(greetingFor(12), 'Good afternoon');
      expect(greetingFor(17), 'Good afternoon');
      expect(greetingFor(18), 'Good evening');
    });

    test('best set of a session', () {
      ExerciseEntry entry(List<(double?, int)> sets) => ExerciseEntry(
        date: DateTime(2026, 10, 5),
        exerciseName: 'X',
        sets: [
          for (var i = 0; i < sets.length; i++)
            _set(i + 1, sets[i].$1, sets[i].$2),
        ],
      );
      final weighted = entry([(40.0, 10), (42.5, 8), (42.5, 9)]).bestSet!;
      expect(weighted.weightKg, 42.5);
      expect(weighted.reps, 9);
      final bodyweight = entry([(null, 12), (0.0, 15)]).bestSet!;
      expect(bodyweight.reps, 15);
      expect(entry(const []).bestSet, isNull);
    });
  });

  // ---------------------------------------------------------------------
  group('Home', () {
    testWidgets('no program: says so and offers to create one', (tester) async {
      seedAppData();
      useTallScreen(tester);
      await launchApp(tester);

      expect(find.textContaining('Test User'), findsOneWidget); // greeting
      expect(find.text('No active program'), findsOneWidget);
      expect(find.text('No completed workouts yet.'), findsOneWidget);
      expect(find.text('Start workout'), findsNothing);
      // First time: a scan is offered first, not "Create program".
      expect(find.text('Run your first scan'), findsOneWidget);
      expect(find.text('Create program'), findsNothing);

      await tapAndSettle(tester, find.byKey(const ValueKey('create-program')));
      expect(find.text('Set up program'), findsOneWidget);
      await completeProgramSetup(tester);
      expect(find.text('New program'), findsOneWidget);
    });

    testWidgets('today\'s workout can be started, then resumed', (
      tester,
    ) async {
      seedAppData(programs: [_program(today)], activeProgramId: 'prog1');
      useTallScreen(tester);
      await launchApp(tester);

      expect(find.text("Today's workout"), findsOneWidget);
      expect(find.text('Upper A'), findsOneWidget);
      expect(find.text('1 exercise · 3 sets'), findsOneWidget);

      await startWorkout(tester);
      expect(find.text('Exercise 1 of 1'), findsOneWidget);

      // Leave: Home now offers Resume instead of starting a second session.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.text('Leave workout'));
      expect(find.text('Workout in progress'), findsOneWidget);
      expect(find.text('Resume workout'), findsOneWidget);
      expect(find.text('Start workout'), findsNothing);

      await tapAndSettle(tester, find.text('Resume workout'));
      expect(find.text('Exercise 1 of 1'), findsOneWidget);
    });

    testWidgets('a rest day never shows another day\'s workout', (
      tester,
    ) async {
      seedAppData(programs: [_program(otherDay)], activeProgramId: 'prog1');
      useTallScreen(tester);
      await launchApp(tester);

      expect(find.text('Rest day'), findsOneWidget);
      expect(find.text('Upper A'), findsNothing);
      expect(find.text('Start workout'), findsNothing);
    });

    testWidgets('an unfinished workout from a past launch can be resumed', (
      tester,
    ) async {
      final planned = _chestPress();
      final fresh = ExerciseLog.fromPlanned(planned, 'Machine Chest Press');
      final unfinished = WorkoutSession(
        id: 'active1',
        programId: 'prog1',
        workoutId: 'w-upper',
        workoutName: 'Upper A',
        startedAt: DateTime(2026, 10, 5, 9),
        exerciseLogs: [
          fresh.copyWith(sets: [_set(1, 40.0, 10), ...fresh.sets.skip(1)]),
        ],
      );
      seedAppData(
        programs: [_program(today)],
        activeProgramId: 'prog1',
        activeSession: unfinished,
      );
      useTallScreen(tester);
      await launchApp(tester);

      expect(find.text('Workout in progress'), findsOneWidget);
      expect(find.text('1 set logged'), findsOneWidget);
      await tapAndSettle(tester, find.text('Resume workout'));
      expect(find.text('40 kg × 10'), findsOneWidget);
      expect(find.text('1 / 3 sets completed'), findsOneWidget);
    });

    testWidgets('recent progress and activity come from the last workout', (
      tester,
    ) async {
      final end = DateTime(now.year, now.month, now.day, 10);
      final session = WorkoutSession(
        id: 's1',
        programId: 'prog1',
        workoutId: 'w-upper',
        workoutName: 'Upper A',
        startedAt: end.subtract(const Duration(minutes: 47)),
        completedAt: end,
        exerciseLogs: [
          testLog('machine_chest_press', 'Machine Chest Press', [
            (40.0, 10),
            (42.5, 8),
            (42.5, 9),
          ]),
        ],
      );
      seedAppData(sessions: [session]);
      useTallScreen(tester);
      await launchApp(tester);

      expect(find.text('Recent progress'), findsOneWidget);
      expect(find.text('Machine Chest Press'), findsOneWidget);
      expect(find.text('42.5 kg × 9'), findsOneWidget);
      expect(find.text('Recent activity'), findsOneWidget);
      expect(find.text('Upper A'), findsOneWidget);
      expect(find.text('Today · 47 min'), findsOneWidget);
      expect(
        find.text('This week: 1 workout · Current streak: 1 week'),
        findsOneWidget,
      );

      await tapAndSettle(tester, find.text('View history'));
      expect(find.text('History'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------
  group('Program tab and Profile tab', () {
    testWidgets('shows the active program, its weekly schedule and today', (
      tester,
    ) async {
      seedAppData(
        programs: [_program(today, lowerDay: otherDay)],
        activeProgramId: 'prog1',
      );
      useTallScreen(tester);
      await launchApp(tester);
      await openTab(tester, 'Program');

      expect(find.text('Active program: Test Plan'), findsOneWidget);
      // The Personalized Plan is always one tap away; with no scan yet it
      // says a scan comes first.
      expect(
        find.byKey(const ValueKey('open-personalized-plan')),
        findsOneWidget,
      );
      expect(
        find.text('Do a body scan to get a plan built for you'),
        findsOneWidget,
      );
      // The week as a row of day boxes: workout name or Rest.
      Finder inDay(Weekday d, String text) => find.descendant(
        of: find.byKey(ValueKey('schedule-day-${d.name}')),
        matching: find.text(text),
      );
      expect(inDay(today, 'Upper A'), findsOneWidget);
      expect(inDay(otherDay, 'Lower A'), findsOneWidget);
      final restDay = Weekday.values.firstWhere(
        (d) => d != today && d != otherDay,
      );
      expect(inDay(restDay, 'Rest'), findsOneWidget);
      expect(find.text('Lower A'), findsOneWidget); // schedule only
      expect(find.text('Upper A'), findsNWidgets(2)); // today card + schedule
      expect(find.text('Start workout'), findsOneWidget);
      expect(find.text('Test Plan'), findsOneWidget); // in the program list
      final days = [today, otherDay]
        ..sort((a, b) => a.index.compareTo(b.index));
      expect(
        find.text('Active · ${days.map((d) => d.compactLabel).join('/')}'),
        findsOneWidget,
      );
      expect(find.text('2 workouts'), findsOneWidget);
    });

    testWidgets('a rest day is shown on the Program tab too', (tester) async {
      seedAppData(programs: [_program(otherDay)], activeProgramId: 'prog1');
      useTallScreen(tester);
      await launchApp(tester);
      await openTab(tester, 'Program');

      expect(find.text('Rest day'), findsOneWidget);
      expect(find.text('Start workout'), findsNothing);
    });

    testWidgets('Profile shows Personal and Training and can be edited', (
      tester,
    ) async {
      seedAppData();
      useTallScreen(tester);
      await launchApp(tester);
      await openTab(tester, 'Profile');

      expect(find.text('Training profile'), findsOneWidget);
      expect(find.text('Test User'), findsOneWidget);
      expect(find.text('170 cm'), findsOneWidget);
      expect(find.text('65.5 kg'), findsOneWidget);
      expect(find.text('Build muscle'), findsOneWidget);
      expect(find.text('60 min'), findsOneWidget);
      expect(find.text('Machines · Cables'), findsOneWidget);

      await tapAndSettle(tester, find.text('Edit profile'));
      expect(find.text('Edit profile'), findsOneWidget); // the form's title
    });
  });

  // ---------------------------------------------------------------------
  group('Planning', () {
    testWidgets('exercises can be reordered inside a workout', (tester) async {
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
      await tester.tap(find.text('Leg Press'));
      await tester.pump();
      await tapAndSettle(tester, find.text('Add 2 exercises'));

      double y(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(y('Machine Chest Press') < y('Leg Press'), isTrue);

      // Drag the first row's handle down past the second row.
      // Drag the first row's handle down past the second row. The handle has
      // to be held before ReorderableListView picks the item up.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.drag_handle).first),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.moveBy(const Offset(0, 250));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(y('Leg Press') < y('Machine Chest Press'), isTrue);
    });
  });

  // ---------------------------------------------------------------------
  group('the whole baseline, start to finish', () {
    testWidgets(
      'profile, program, workout, restart, history, progress, edit, resume',
      (tester) async {
        seedNoProfile();
        useTallScreen(tester);
        await launchApp(tester);

        // 1. Profile setup.
        await fillProfileSetup(tester, name: 'Test User');
        await tapAndSettle(tester, find.text('Save profile'));
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.text('No active program'), findsOneWidget);

        // 2. Create a program (training today) from Home.
        await tapAndSettle(
          tester,
          find.byKey(const ValueKey('create-program')),
        );
        await completeProgramSetup(tester, name: 'My Plan');
        await tester.tap(find.widgetWithText(FilterChip, today.shortLabel));
        await tester.pump();
        await tapAndSettle(tester, find.text('Add workout'));
        await tapAndSettle(tester, find.text('Custom'));
        await tester.enterText(find.byType(TextFormField).first, 'Upper A');
        await tapAndSettle(tester, find.text('Add exercises'));
        await tester.tap(find.text('Machine Chest Press'));
        await tester.pump();
        await tapAndSettle(tester, find.text('Add 1 exercise'));
        await tapAndSettle(tester, find.text('Done'));
        await tester.tap(find.widgetWithText(FilterChip, 'Upper A'));
        await tester.pump();
        await tapAndSettle(tester, find.text('Save program'));

        // 3. Today's workout is on Home. Do it: 3 sets of 40 kg x 10.
        expect(find.text("Today's workout"), findsOneWidget);
        expect(find.text('1 exercise · 3 sets'), findsOneWidget);
        await startWorkout(tester);
        await completeSet(tester, weight: '40', reps: '10');
        await completeSet(tester, reps: '10');
        await completeSet(tester, reps: '10');
        await tapAndSettle(tester, find.text('Complete workout'));
        await tapAndSettle(tester, find.text('Save workout'));
        expect(find.text('Completed today'), findsOneWidget);
        expect(find.text('Recent activity'), findsOneWidget);

        // 4. Close and reopen the app. Home still shows it.
        await restartApp(tester);
        expect(find.text('40 kg × 10'), findsOneWidget);

        // History opens from Home and shows the actual sets.
        await tapAndSettle(tester, find.text('View history'));
        await tapAndSettle(tester, find.text('Upper A').first);
        expect(find.text('40 kg × 10'), findsNWidgets(3));
        expect(find.text('Target: 8–12 reps'), findsNWidgets(3));
        await tester.pageBack(); // detail -> history
        await tester.pumpAndSettle();
        await tester.pageBack(); // history -> home
        await tester.pumpAndSettle();

        // 5. Progress reflects it.
        await openTab(tester, 'Progress');
        // Strength: the chest press is listed, done once.
        expect(find.textContaining('1 session · Last:'), findsOneWidget);
        await tapAndSettle(
          tester,
          find.widgetWithText(Tab, 'Muscle Distribution'),
        );
        expect(find.text('Weekly frequency'), findsOneWidget);

        // 6. Edit the program: chest press becomes 4 sets.
        await openTab(tester, 'Program');
        await tapAndSettle(tester, find.text('My Plan'));
        await tapAndSettle(tester, workoutCard());
        // Changing what a workout contains goes through Edit workout.
        await tapAndSettle(tester, find.text('Edit workout'));
        await tapAndSettle(tester, find.text('Machine Chest Press'));
        await tapAndSettle(tester, find.text('Add working set')); // 3 -> 4 sets
        await tapAndSettle(tester, find.text('Done')); // exercise
        await tapAndSettle(tester, find.text('Done')); // workout editor
        expect(find.text('8–12 reps · Rest 90s'), findsNWidgets(4));
        await tester.pageBack(); // workout detail -> program detail
        await tester.pumpAndSettle();
        await tester.pageBack(); // program detail -> tabs
        await tester.pumpAndSettle();

        // 7. The old session still says 3 sets.
        await openTab(tester, 'Progress');
        await tapAndSettle(tester, find.text('Workout history'));
        await tapAndSettle(tester, find.text('Upper A').first);
        // Still exactly the 3 sets planned back then, not the 4 planned now.
        expect(find.text('Target: 8–12 reps'), findsNWidgets(3));
        expect(find.text('40 kg × 10'), findsNWidgets(3));
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();

        // 8. Start the workout again, log one set, leave, restart, resume.
        await openTab(tester, 'Home');
        await startWorkout(tester);
        await completeSet(tester, weight: '40', reps: '10');
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tapAndSettle(tester, find.text('Leave workout'));
        expect(find.text('Resume workout'), findsOneWidget);

        await restartApp(tester);
        expect(find.text('Resume workout'), findsOneWidget);
        await tapAndSettle(tester, find.text('Resume workout'));
        expect(find.text('40 kg × 10'), findsOneWidget);
        expect(find.text('1 / 4 sets completed'), findsOneWidget);
      },
    );
  });
}
