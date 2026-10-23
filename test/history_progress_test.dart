import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/app.dart';
import 'package:anthrofit/core/format.dart';
import 'package:anthrofit/data/session_repository.dart';
import 'package:anthrofit/data/training_stats.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/screens/history/history_calendar.dart';
import 'package:anthrofit/screens/progress/exercise_progress_screen.dart';
import 'package:anthrofit/state/session_controller.dart';
import 'package:anthrofit/state/session_scope.dart';

import 'test_helpers.dart';

// ---------------------------------------------------------------------------
// Test data builders
// ---------------------------------------------------------------------------

SetLog _set(int n, double? weight, int reps) => SetLog(
  setNumber: n,
  weightKg: weight,
  reps: reps,
  isCompleted: true,
  completedAt: DateTime(2026, 1, 1),
);

WorkoutSession _session(
  String id,
  String name,
  DateTime end,
  List<ExerciseLog> logs, {
  int minutes = 47,
}) {
  return WorkoutSession(
    id: id,
    programId: 'prog1',
    workoutId: 'w-$id',
    workoutName: name,
    startedAt: end.subtract(Duration(minutes: minutes)),
    completedAt: end,
    exerciseLogs: logs,
  );
}

/// Machine Chest Press 40x10, 40x9, 42.5x8 (volume 1100) and Push-Up 12, 11 (no weight).
List<ExerciseLog> _upperLogs() => [
  testLog('machine_chest_press', 'Machine Chest Press', [
    (40.0, 10),
    (40.0, 9),
    (42.5, 8),
  ]),
  testLog('push_up', 'Push-Up', [(null, 12), (null, 11)]),
];

/// The CURRENT program says 4 x 6-10 for chest press. Old sessions say 3 x 8-12.
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
            sets: 4,
            repMin: 6,
            repMax: 10,
          ),
        ],
      ),
      Workout(
        id: 'w-lower',
        name: 'Lower A',
        exercises: [testPlanned('p2', 'leg_press', sets: 1, rest: 60)],
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

void main() {
  // The exercise catalogue is an asset now, so it has to be loaded.
  useExerciseLibrary();

  // ---------------------------------------------------------------------
  // Pure calculations. Oct 5, 2026 is a Monday.
  // ---------------------------------------------------------------------
  group('training stats', () {
    final today = DateTime(2026, 10, 8); // Thursday

    test('summarize: volume is weight x reps for weighted sets only', () {
      final s = _session(
        'a',
        'Upper A',
        DateTime(2026, 10, 5, 10),
        _upperLogs(),
      );
      final r = summarize([s]);
      expect(r.workouts, 1);
      expect(r.sets, 5);
      expect(r.reps, 50);
      expect(r.volumeKg, 1100); // 400 + 360 + 340
      expect(r.weightedSets, 3);
      expect(r.bodyweightSets, 2);
      expect(r.bodyweightReps, 23);
    });

    test('blank or zero weight is never given a made-up load', () {
      final s = _session('a', 'X', DateTime(2026, 10, 5, 10), [
        testLog('push_up', 'Push-Up', [(null, 10), (0.0, 10)]),
      ]);
      final r = summarize([s]);
      expect(r.volumeKg, 0);
      expect(r.weightedSets, 0);
      expect(r.bodyweightSets, 2);
      expect(r.bodyweightReps, 20);
    });

    test('sets that were not completed are ignored', () {
      final unfinished = SetLog(setNumber: 2, weightKg: 100, reps: 10);
      final log = testLog('machine_chest_press', 'Machine Chest Press', [
        (40.0, 10),
      ]);
      final s = _session('a', 'X', DateTime(2026, 10, 5, 10), [
        log.copyWith(sets: [...log.sets, unfinished]),
      ]);
      final r = summarize([s]);
      expect(r.sets, 1);
      expect(r.volumeKg, 400);
    });

    test('ranges: 1W is today and the 6 days before', () {
      final sessions = [
        _session('in', 'A', DateTime(2026, 10, 2, 10), []),
        _session('out', 'B', DateTime(2026, 10, 1, 10), []),
        _session('old', 'C', DateTime(2026, 8, 1, 10), []),
      ];
      List<String> ids(ProgressRange r) =>
          sessionsInRange(sessions, r, today).map((s) => s.id).toList()..sort();
      expect(ids(ProgressRange.week1), ['in']);
      expect(ids(ProgressRange.month1), ['in', 'out']);
      expect(ids(ProgressRange.month3), ['in', 'old', 'out']);
      expect(ids(ProgressRange.month6), ['in', 'old', 'out']);
      expect(ids(ProgressRange.allTime), ['in', 'old', 'out']);
    });

    test('weekly buckets run Monday to Sunday and end with this week', () {
      final sessions = [
        _session('a', 'A', DateTime(2026, 10, 5, 10), _upperLogs()),
        _session('b', 'B', DateTime(2026, 10, 7, 10), _upperLogs()),
        _session('c', 'C', DateTime(2026, 9, 28, 10), _upperLogs()),
      ];
      final three = weeklyBuckets(sessions, today, weeks: 3);
      expect(three.map((b) => b.weekStart).toList(), [
        DateTime(2026, 9, 21),
        DateTime(2026, 9, 28),
        DateTime(2026, 10, 5),
      ]);
      expect(three.map((b) => b.workouts).toList(), [0, 1, 2]);
      expect(three.last.volumeKg, 2200);

      final all = weeklyBuckets(sessions, today);
      expect(all.length, 2); // from the first session's week
      expect(all.first.weekStart, DateTime(2026, 9, 28));
    });

    test('this week and this month counts', () {
      final sessions = [
        _session('a', 'A', DateTime(2026, 10, 5, 10), []),
        _session('b', 'B', DateTime(2026, 10, 1, 10), []),
        _session('c', 'C', DateTime(2026, 9, 30, 10), []),
      ];
      expect(workoutsInWeekOf(sessions, today), 1);
      expect(workoutsInMonthOf(sessions, today), 2);
    });

    test('week streaks come only from completed sessions', () {
      WorkoutSession onMonday(int month, int day) =>
          _session('s$month-$day', 'A', DateTime(2026, month, day, 10), []);

      // Weeks of Sep 14, 21, 28. This week (Oct 5) has none yet, so the
      // streak continues from last week.
      final running = [onMonday(9, 14), onMonday(9, 21), onMonday(9, 28)];
      final a = weekStreaks(running, today);
      expect(a.current, 3);
      expect(a.longest, 3);

      // Run of 2 (Aug 31, Sep 7), a gap, then a run of 3 up to this week.
      final broken = [
        onMonday(8, 31),
        onMonday(9, 7),
        onMonday(9, 21),
        onMonday(9, 28),
        onMonday(10, 5),
      ];
      final b = weekStreaks(broken, today);
      expect(b.current, 3);
      expect(b.longest, 3);

      // Only an old session: no current streak.
      final c = weekStreaks([onMonday(8, 31)], today);
      expect(c.current, 0);
      expect(c.longest, 1);

      final none = weekStreaks(const [], today);
      expect(none.current, 0);
      expect(none.longest, 0);
    });

    test('scheduled days: only days up to today count, and only that week', () {
      final sessions = [
        _session('mon', 'A', DateTime(2026, 10, 5, 10), []),
        _session('tue', 'B', DateTime(2026, 10, 6, 10), []), // not scheduled
        _session('last', 'C', DateTime(2026, 10, 2, 10), []), // last week
      ];
      final r = scheduledThisWeek(sessions, {
        Weekday.monday,
        Weekday.wednesday,
        Weekday.friday,
        Weekday.saturday,
      }, today)!;
      // Mon and Wed are due by Thursday. Fri and Sat are still ahead.
      expect(r.opportunities, 2);
      expect(r.done, 1);
      expect(r.percent, 50);

      expect(scheduledThisWeek(sessions, <Weekday>{}, today), isNull);
    });

    test('exercise history, summaries, and records use actual logs only', () {
      final sessions = [
        _session('s1', 'A', DateTime(2026, 10, 1, 10), [
          testLog('machine_chest_press', 'Machine Chest Press', [
            (40.0, 10),
            (40.0, 9),
          ]),
        ]),
        _session('s2', 'A', DateTime(2026, 10, 3, 10), [
          testLog('machine_chest_press', 'Machine Chest Press', [(42.5, 9)]),
        ]),
        // Renamed in the library later: the newest saved name wins.
        _session('s3', 'A', DateTime(2026, 10, 5, 10), [
          testLog('machine_chest_press', 'Chest Press (machine)', [
            (45.0, 8),
            (45.0, 6),
          ]),
          testLog('push_up', 'Push-Up', [(null, 12), (0.0, 15)]),
        ]),
      ];

      final history = exerciseHistory(sessions, 'machine_chest_press');
      expect(history.map((e) => e.date).toList(), [
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 3),
        DateTime(2026, 10, 5),
      ]);
      expect(history.first.heaviestKg, 40);
      expect(history.last.mostReps, 8);

      final records = personalRecords(history);
      expect(records.heaviestKg, 45);
      expect(records.repsAtHeaviest, 8);
      expect(records.mostRepsNoWeight, isNull);

      final pushUp = personalRecords(exerciseHistory(sessions, 'push_up'));
      expect(pushUp.heaviestKg, isNull);
      expect(pushUp.mostRepsNoWeight, 15);

      final summaries = exercisesPerformed(sessions);
      expect(summaries.length, 2);
      final chest = summaries.firstWhere(
        (e) => e.exerciseId == 'machine_chest_press',
      );
      expect(chest.name, 'Chest Press (machine)');
      expect(chest.sessionCount, 3);
      expect(chest.lastPerformed, DateTime(2026, 10, 5));

      expect(exerciseHistory(sessions, 'not_there'), isEmpty);
    });

    test('same-day sessions group together and lists are ordered', () {
      final a = _session('a', 'A', DateTime(2026, 10, 5, 9), []);
      final b = _session('b', 'B', DateTime(2026, 10, 5, 18), []);
      final c = _session('c', 'C', DateTime(2026, 10, 3, 9), []);
      final grouped = sessionsByDate([a, b, c]);
      expect(grouped[DateTime(2026, 10, 5)]!.map((s) => s.id).toList(), [
        'b',
        'a',
      ]);
      expect(grouped[DateTime(2026, 10, 3)]!.length, 1);
      expect(newestFirst([a, c, b]).map((s) => s.id).toList(), ['b', 'a', 'c']);
      expect(oldestFirst([b, a, c]).map((s) => s.id).toList(), ['c', 'a', 'b']);
    });

    test('formatting', () {
      expect(formatThousands(12450), '12,450');
      expect(formatThousands(382.5), '382.5');
      expect(formatThousands(999), '999');
      expect(formatThousands(1234567), '1,234,567');
      expect(formatVolume(1100), '1,100 kg');
      expect(formatSetLog(_set(1, 42.5, 8)), '42.5 kg × 8');
      expect(formatSetLog(_set(1, 40, 10)), '40 kg × 10');
      expect(formatSetLog(_set(1, null, 12)), '12 reps');
      expect(formatSetLog(_set(1, 0, 12)), '12 reps');
      expect(formatDate(DateTime(2026, 10, 5), today: today), 'October 5');
      expect(
        formatDate(DateTime(2025, 10, 5), today: today),
        'October 5, 2025',
      );
      expect(formatShortDate(DateTime(2026, 10, 5)), 'Oct 5');
      expect(formatMonthYear(DateTime(2026, 10, 1)), 'October 2026');
    });
  });

  // ---------------------------------------------------------------------
  // Screens
  // ---------------------------------------------------------------------
  group('History and Progress screens', () {
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

    Future<void> openTab(WidgetTester tester, String label) => tapAndSettle(
      tester,
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );

    Future<void> openHistory(WidgetTester tester) async {
      await openTab(tester, 'Progress');
      await tapAndSettle(tester, find.text('Workout history'));
    }

    Finder dayKey(DateTime d) =>
        find.byKey(ValueKey('calendar-day-${calendarDateKey(d)}'));
    Finder markerKey(DateTime d) =>
        find.byKey(ValueKey('calendar-marker-${calendarDateKey(d)}'));

    // Today, 3 days ago, and 40 days ago.
    final now = DateTime.now();
    final todayEnd = DateTime(now.year, now.month, now.day, 10);
    final oldEnd = DateTime(now.year, now.month, now.day - 3, 10);
    final ancientEnd = DateTime(now.year, now.month, now.day - 40, 10);

    List<WorkoutSession> seedSessions() => [
      _session('s-ancient', 'Upper A', ancientEnd, [
        testLog('machine_chest_press', 'Machine Chest Press', [(30.0, 10)]),
      ], minutes: 30),
      _session('s-old', 'Lower A', oldEnd, [
        testLog('retired_ex', 'Retired Exercise', [(20.0, 12)]),
      ]),
      _session('s-today', 'Upper A', todayEnd, _upperLogs()),
    ];

    testWidgets('empty states before any workout is completed', (tester) async {
      seedAppData(programs: [_program()], activeProgramId: 'prog1');
      useTallScreen(tester);
      await launchApp(tester);

      await openTab(tester, 'Progress');
      expect(find.text('No workout data yet.'), findsOneWidget);
      expect(
        find.text(
          'Complete your first workout to start tracking your '
          'strength and training exposure.',
        ),
        findsOneWidget,
      );
      // No summary of zeroes before there is anything to sum.
      expect(find.byKey(const ValueKey('stat-Workouts')), findsNothing);
      // Body Progress stands on its own, with its own empty state.
      await tapAndSettle(tester, find.widgetWithText(Tab, 'Body Weight'));
      expect(find.text('No body measurements yet.'), findsOneWidget);

      await tapAndSettle(tester, find.text('Workout history'));
      expect(find.text('No completed workouts yet.'), findsOneWidget);
      expect(
        find.text('Complete a workout and it will appear here.'),
        findsOneWidget,
      );
    });

    testWidgets('history: calendar, day panel, list, and detail', (
      tester,
    ) async {
      seedAppData(
        programs: [_program()],
        activeProgramId: 'prog1',
        sessions: seedSessions(),
      );
      useTallScreen(tester);
      await launchApp(tester);
      await openHistory(tester);

      // Calendar shows this month, and marks days with a completed workout.
      expect(find.text(formatMonthYear(now)), findsOneWidget);
      expect(markerKey(DateTime(now.year, now.month, now.day)), findsOneWidget);
      final oldDate = DateTime(now.year, now.month, now.day - 3);
      if (oldDate.month == now.month) {
        expect(markerKey(oldDate), findsOneWidget);
      }
      final blankDay = [for (var d = 1; d <= 28; d++) d].firstWhere(
        (d) =>
            d != now.day && !(oldDate.month == now.month && d == oldDate.day),
      );
      final blank = DateTime(now.year, now.month, blankDay);
      expect(markerKey(blank), findsNothing);

      // Newest first, with name, duration, exercises and sets.
      final y = [
        for (final id in ['s-today', 's-old', 's-ancient'])
          tester.getTopLeft(find.byKey(ValueKey('history-card-$id'))).dy,
      ];
      expect(y[0] < y[1] && y[1] < y[2], isTrue);
      expect(
        find.text('47 min · 2 exercises · 5 sets'),
        findsNWidgets(2),
      ); // panel + list
      expect(find.text('47 min · 1 exercise · 1 set'), findsOneWidget);
      expect(find.text('30 min · 1 exercise · 1 set'), findsOneWidget);

      // A day with no workout.
      final panel = find.byKey(const ValueKey('selected-day-panel'));
      await tapAndSettle(tester, dayKey(blank));
      expect(
        find.descendant(of: panel, matching: find.text('No workouts')),
        findsOneWidget,
      );

      // A day with a workout lists it. Tap it to open the record.
      await tapAndSettle(
        tester,
        dayKey(DateTime(now.year, now.month, now.day)),
      );
      expect(
        find.descendant(of: panel, matching: find.text('No workouts')),
        findsNothing,
      );
      await tapAndSettle(
        tester,
        find.descendant(of: panel, matching: find.text('Upper A')),
      );

      // Detail: actual performance, target kept separate. The facts sit in
      // a folding "Workout details" panel, closed at first.
      expect(find.text('Upper A'), findsOneWidget);
      expect(find.text('Total volume'), findsNothing);
      await tapAndSettle(tester, find.text('Workout details'));
      expect(find.text('47 min'), findsOneWidget);
      expect(find.text('2 exercises · 5 sets'), findsOneWidget);
      expect(find.text('Total volume'), findsOneWidget);
      expect(find.text('1,100 kg'), findsOneWidget);
      expect(find.text('No weight logged'), findsOneWidget);
      expect(find.text('2 sets · 23 reps'), findsOneWidget);
      expect(find.text('Machine Chest Press'), findsOneWidget);
      expect(find.text('40 kg × 10'), findsOneWidget);
      expect(find.text('40 kg × 9'), findsOneWidget);
      expect(find.text('42.5 kg × 8'), findsOneWidget);
      expect(find.text('12 reps'), findsOneWidget);
      expect(find.text('11 reps'), findsOneWidget);

      // The program now says 4 x 6-10. The old session still says 3 x 8-12.
      expect(find.text('Target: 8–12 reps'), findsNWidgets(5)); // one per set
      expect(find.text('Target: 6–10 reps'), findsNothing);

      // An exercise that is not in the library still reads correctly.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapAndSettle(
        tester,
        find.byKey(const ValueKey('history-card-s-old')),
      );
      expect(find.text('Retired Exercise'), findsOneWidget);
      expect(find.text('20 kg × 12'), findsOneWidget);
    });

    testWidgets('progress numbers come from the logged sessions and ranges', (
      tester,
    ) async {
      seedAppData(
        programs: [_program()],
        activeProgramId: 'prog1',
        sessions: seedSessions(),
      );
      useTallScreen(tester);
      await launchApp(tester);
      await openTab(tester, 'Progress');

      // Strength: bodyweight sets are reported, with no weight invented.
      expect(
        find.text('Bodyweight: 2 sets · 23 reps (no weight logged)'),
        findsOneWidget,
      );

      // Distribution is on Muscle Distribution.
      await tapAndSettle(
        tester,
        find.widgetWithText(Tab, 'Muscle Distribution'),
      );
      expect(find.text('Weekly frequency'), findsOneWidget);
      // Frequency only: nothing about planned or missed workouts.
      expect(find.textContaining('Scheduled'), findsNothing);
      expect(find.textContaining('streak'), findsNothing);

      // 1M leaves out the session from 40 days ago.
      await tapAndSettle(tester, find.text('1M'));
      expect(find.text('Weekly frequency'), findsOneWidget);
      await tapAndSettle(tester, find.widgetWithText(Tab, 'Strength'));

      // Exercise list follows the range. The name is also in the strength
      // picker above it, so the list row is found by its tile.
      expect(
        find.widgetWithText(ListTile, 'Machine Chest Press'),
        findsOneWidget,
      );
      // Chest Press and Push-Up were both last done today, once each.
      expect(
        find.text('1 session · Last: ${formatDate(todayEnd, today: now)}'),
        findsNWidgets(2),
      );
    });

    testWidgets('exercise progress shows records and actual sets, by range', (
      tester,
    ) async {
      seedAppData(
        programs: [_program()],
        activeProgramId: 'prog1',
        sessions: seedSessions(),
      );
      useTallScreen(tester);
      await launchApp(tester);
      await openTab(tester, 'Progress');

      await tapAndSettle(
        tester,
        find.widgetWithText(ListTile, 'Machine Chest Press'),
      );

      // Records (all time) from logged sets only.
      expect(find.text('Heaviest weight'), findsOneWidget);
      expect(find.text('42.5 kg'), findsWidgets);

      // Both sessions, oldest first, with every logged set.
      expect(find.text('30 kg'), findsOneWidget);
      expect(find.text('42.5 kg'), findsWidgets);

      // 1W: only the recent session.
      await tapAndSettle(tester, find.text('1W'));
      expect(find.text('30 kg'), findsNothing);
      expect(find.text('42.5 kg'), findsWidgets);

      // Bodyweight exercise.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.widgetWithText(ListTile, 'Push-Up'));
      expect(find.text('Heaviest weight'), findsOneWidget);
      expect(find.text('Best set'), findsOneWidget);
    });

    testWidgets('an exercise with no records shows an empty state', (
      tester,
    ) async {
      seedNoProfile();
      final controller = SessionController(SessionRepository());
      await tester.pumpWidget(
        SessionScope(
          controller: controller,
          child: const MaterialApp(
            home: ExerciseProgressScreen(exerciseId: 'nothing'),
          ),
        ),
      );
      expect(
        find.text('No recorded performance for this exercise yet.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'a workout finished in a session appears in history and progress, and survives restart',
      (tester) async {
        seedAppData(programs: [_program()], activeProgramId: 'prog1');
        useTallScreen(tester);
        await launchApp(tester);

        // Do a real workout: Program -> Test Plan -> Lower A -> Start.
        await openTab(tester, 'Program');
        await tapAndSettle(tester, find.text('Test Plan'));
        await tapAndSettle(
          tester,
          find.byKey(const ValueKey('workout-card-w-lower')),
        );
        await startWorkout(tester);
        await tester.enterText(find.byType(TextField).at(0), '100');
        await tester.enterText(find.byType(TextField).at(1), '10');
        await tester.tap(find.text('Complete set'));
        await tester.pump();
        await tester.pump();
        await closeRestSheet(tester);
        await tapAndSettle(tester, find.text('Complete workout'));
        await tapAndSettle(tester, find.text('Save workout'));

        // Back to the Program tab, then Progress.
        await tester.pageBack(); // workout detail -> program
        await tester.pumpAndSettle();
        await tester.pageBack(); // program -> tabs
        await tester.pumpAndSettle();
        await openTab(tester, 'Progress');

        // Strength: the exercise is listed; its page has 100 kg × 10.
        await tapAndSettle(tester, find.textContaining('1 session · Last:'));
        expect(find.text('Heaviest weight'), findsOneWidget);
        expect(find.text('100 kg'), findsWidgets);
        expect(find.text('100 kg × 10'), findsOneWidget);
        expect(find.text('1,000 kg'), findsWidgets);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tapAndSettle(
          tester,
          find.widgetWithText(Tab, 'Muscle Distribution'),
        );
        expect(find.text('Weekly frequency'), findsOneWidget);

        // History shows it with today's date marked.
        await tapAndSettle(tester, find.text('Workout history'));
        expect(
          markerKey(DateTime(now.year, now.month, now.day)),
          findsOneWidget,
        );
        expect(
          find.text('Less than 1 min · 1 exercise · 1 set'),
          findsNWidgets(2),
        );
        await tapAndSettle(
          tester,
          find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('history-card-'),
          ),
        );
        expect(find.text('Lower A'), findsOneWidget);
        expect(find.text('100 kg × 10'), findsOneWidget);
        expect(find.textContaining('1,000 kg'), findsOneWidget);

        // Restart the app: still there.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await launchApp(tester);
        await openTab(tester, 'Progress');
        expect(find.textContaining('1 session · Last:'), findsOneWidget);
        await tapAndSettle(
          tester,
          find.widgetWithText(Tab, 'Muscle Distribution'),
        );
        expect(find.text('Weekly frequency'), findsOneWidget);
      },
    );
  });
}
