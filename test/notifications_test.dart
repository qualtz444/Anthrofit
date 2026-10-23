import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/notifications/app_notifications.dart';
import 'package:anthrofit/notifications/reminder_settings.dart';
import 'package:anthrofit/screens/session/rest_timer.dart';

class _FakeNotifications implements AppNotifications {
  final List<String> calls = [];
  Duration? restAfter;
  String? restBody;

  @override
  Future<bool> requestPermission() async {
    calls.add('permission');
    return true;
  }

  @override
  Future<void> scheduleRestOver({
    required Duration after,
    required String body,
  }) async {
    calls.add('rest');
    restAfter = after;
    restBody = body;
  }

  @override
  Future<void> cancelRestOver() async => calls.add('cancel');

  @override
  Future<void> syncWorkoutReminders(
    TrainingProgram? program,
    ReminderSettings settings,
  ) async => calls.add('sync');
}

TrainingProgram _program() => TrainingProgram(
  id: 'p',
  name: 'PPL',
  workouts: const [
    Workout(id: 'push', name: 'Push', exercises: []),
    Workout(id: 'pull', name: 'Pull', exercises: []),
  ],
  schedule: const [
    ScheduledWorkout(day: Weekday.monday, workoutId: 'pull'),
    ScheduledWorkout(day: Weekday.wednesday, workoutId: 'push'),
  ],
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  group('when a weekly reminder first fires', () {
    // Wednesday 14 October 2026, 10:00.
    final now = DateTime(2026, 10, 14, 10);

    test('later today counts as today', () {
      expect(
        nextWeekly(now, Weekday.wednesday, 18, 30),
        DateTime(2026, 10, 14, 18, 30),
      );
    });

    test('a time already passed today moves to next week', () {
      expect(
        nextWeekly(now, Weekday.wednesday, 7, 0),
        DateTime(2026, 10, 21, 7),
      );
    });

    test('another day is the next one of that day', () {
      expect(nextWeekly(now, Weekday.monday, 7, 0), DateTime(2026, 10, 19, 7));
      expect(nextWeekly(now, Weekday.friday, 7, 0), DateTime(2026, 10, 16, 7));
    });
  });

  group('training-day reminders', () {
    final now = DateTime(2026, 10, 14, 10);

    test('one per training day, naming its workout', () {
      final list = remindersFor(
        _program(),
        const ReminderSettings(enabled: true, hour: 6, minute: 30),
        now,
      );
      expect(list.map((r) => r.day), [Weekday.monday, Weekday.wednesday]);
      expect(list.first.title, 'Workout today: Pull');
      expect(list.first.id, kReminderIdBase + Weekday.monday.index);
      expect(list.first.firstAt, DateTime(2026, 10, 19, 6, 30));
      expect(list.last.title, 'Workout today: Push');
    });

    test('none when off, or with no active program', () {
      expect(remindersFor(_program(), const ReminderSettings(), now), isEmpty);
      expect(
        remindersFor(null, const ReminderSettings(enabled: true), now),
        isEmpty,
      );
    });

    test('the setting survives saving, and bad data reads as off', () {
      const s = ReminderSettings(enabled: true, hour: 19, minute: 45);
      expect(ReminderSettings.decode(s.encode()), s);
      expect(ReminderSettings.decode('junk'), const ReminderSettings());
      expect(ReminderSettings.decode('1|25|0'), const ReminderSettings());
    });
  });

  group('rest alert', () {
    late AppNotifications original;
    late _FakeNotifications fake;

    setUp(() {
      original = appNotifications;
      fake = _FakeNotifications();
      appNotifications = fake;
    });
    tearDown(() => appNotifications = original);

    Future<void> goTo(WidgetTester tester, List<AppLifecycleState> states) async {
      for (final s in states) {
        tester.binding.handleAppLifecycleStateChanged(s);
        await tester.pump();
      }
    }

    testWidgets('leaving mid-rest asks the phone to say when it is over, '
        'and coming back cancels it', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RestTimer(seconds: 90, alertText: 'Time for Lat Pulldown.'),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 10));

      await goTo(tester, [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      expect(fake.calls, ['rest']);
      expect(fake.restAfter, const Duration(seconds: 80));
      expect(fake.restBody, 'Time for Lat Pulldown.');

      await goTo(tester, [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      expect(fake.calls, ['rest', 'cancel']);
      // Still counting down after coming back.
      expect(find.text('01:20'), findsOneWidget);
    });

    testWidgets('no alert when the rest is not running', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: RestTimer(seconds: 5))),
      );
      await tester.pump(const Duration(seconds: 6));
      await goTo(tester, [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      expect(fake.calls, isEmpty);
      await goTo(tester, [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
    });
  });
}
