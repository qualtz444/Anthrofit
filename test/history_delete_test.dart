import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/data/session_repository.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/screens/history/workout_history_detail_screen.dart';
import 'package:anthrofit/state/session_controller.dart';
import 'package:anthrofit/state/session_scope.dart';

import 'test_helpers.dart';

WorkoutSession _done(String id, String name, DateTime end) => WorkoutSession(
  id: id,
  programId: 'prog1',
  workoutId: 'w-$id',
  workoutName: name,
  startedAt: end.subtract(const Duration(minutes: 45)),
  completedAt: end,
  exerciseLogs: const [],
);

Future<SessionController> _controllerWith(List<WorkoutSession> sessions) async {
  seedNoProfile();
  await SessionRepository().save(SessionData(sessions: sessions));
  final controller = SessionController(SessionRepository());
  await controller.load();
  return controller;
}

void main() {
  test('deleting a completed workout removes it, and stays removed', () async {
    final c = await _controllerWith([
      _done('a', 'Upper A', DateTime(2026, 10, 1, 9)),
      _done('b', 'Lower A', DateTime(2026, 10, 2, 9)),
    ]);
    await c.deleteCompletedSession('a');
    expect(c.completedSessions.map((s) => s.id), ['b']);

    final reloaded = SessionController(SessionRepository());
    await reloaded.load();
    expect(reloaded.completedSessions.map((s) => s.id), ['b']);
  });

  test('an unknown id changes nothing', () async {
    final c = await _controllerWith([
      _done('a', 'Upper A', DateTime(2026, 10, 1, 9)),
    ]);
    await c.deleteCompletedSession('missing');
    expect(c.completedSessions.length, 1);
  });

  testWidgets('the detail screen deletes after confirming, then goes back', (
    tester,
  ) async {
    final session = _done('a', 'Upper A', DateTime(2026, 10, 1, 9));
    final c = await _controllerWith([session]);
    await tester.pumpWidget(
      SessionScope(
        controller: c,
        child: const MaterialApp(home: Scaffold(body: Text('History list'))),
      ),
    );
    Navigator.of(tester.element(find.text('History list'))).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutHistoryDetailScreen(session: session),
      ),
    );
    await tester.pumpAndSettle();

    // Cancel keeps it.
    await tester.tap(find.byTooltip('Delete workout'));
    await tester.pumpAndSettle();
    expect(find.text('Delete workout?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.completedSessions.length, 1);

    // Delete removes it and returns to the list.
    await tester.tap(find.byTooltip('Delete workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(c.completedSessions, isEmpty);
    expect(find.text('History list'), findsOneWidget);
    expect(find.text('Workout deleted'), findsOneWidget);
  });

  group('deleting one exercise', () {
    WorkoutSession twoExercises() => WorkoutSession(
      id: 'w',
      programId: 'prog1',
      workoutId: 'w-1',
      workoutName: 'Upper A',
      startedAt: DateTime(2026, 10, 14, 9),
      completedAt: DateTime(2026, 10, 14, 10),
      exerciseLogs: [
        testLog('press', 'Chest Press', [(40, 10)]),
        testLog('row', 'Seated Row', [(35, 12)]),
      ],
    );

    test('removes only that exercise, and stays removed', () async {
      final c = await _controllerWith([twoExercises()]);
      final gone = await c.deleteCompletedExercise(
        sessionId: 'w',
        exerciseLogId: 'log-press',
      );
      expect(gone, isFalse);
      expect(
        c.completedSessions.single.exerciseLogs.map((l) => l.exerciseName),
        ['Seated Row'],
      );
      final reloaded = SessionController(SessionRepository());
      await reloaded.load();
      expect(reloaded.completedSessions.single.exerciseLogs, hasLength(1));
    });

    test('deleting the last exercise removes the workout', () async {
      final c = await _controllerWith([twoExercises()]);
      await c.deleteCompletedExercise(sessionId: 'w', exerciseLogId: 'log-press');
      final gone = await c.deleteCompletedExercise(
        sessionId: 'w',
        exerciseLogId: 'log-row',
      );
      expect(gone, isTrue);
      expect(c.completedSessions, isEmpty);
    });

    testWidgets('the detail screen deletes one exercise after asking', (
      tester,
    ) async {
      final session = twoExercises();
      final c = await _controllerWith([session]);
      await tester.pumpWidget(
        SessionScope(
          controller: c,
          child: MaterialApp(
            home: WorkoutHistoryDetailScreen(session: session),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chest Press'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('delete-exercise-log-press')));
      await tester.pumpAndSettle();
      expect(find.text('Delete Chest Press?'), findsOneWidget);
      expect(find.textContaining('The rest of the workout stays'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Chest Press'), findsNothing);
      expect(find.text('Seated Row'), findsOneWidget);
      expect(c.completedSessions.single.exerciseLogs, hasLength(1));
    });
  });
}
