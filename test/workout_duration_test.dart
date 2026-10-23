import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/models/models.dart';

// A workout's duration is the time the workout screen was open, so a
// workout started, left for hours and finished later is not counted as
// hours long.

WorkoutSession _session({int? activeSeconds}) => WorkoutSession(
  id: 's',
  workoutId: 'w',
  workoutName: 'Upper A',
  startedAt: DateTime(2026, 10, 14, 10),
  completedAt: DateTime(2026, 10, 14, 14, 37), // 4 h 37 min later
  activeSeconds: activeSeconds,
);

void main() {
  test('the time on screen is the duration, not start to finish', () {
    expect(_session(activeSeconds: 75).duration, const Duration(seconds: 75));
  });

  test('older sessions without it still show start to finish', () {
    expect(
      _session().duration,
      const Duration(hours: 4, minutes: 37),
    );
  });

  test('a workout still in progress has no duration', () {
    final s = WorkoutSession(
      id: 's',
      workoutId: 'w',
      workoutName: 'Upper A',
      startedAt: DateTime(2026, 10, 14, 10),
      activeSeconds: 30,
    );
    expect(s.duration, isNull);
  });

  test('the active time survives a save and load, and copyWith', () {
    final back = WorkoutSession.fromJson(_session(activeSeconds: 75).toJson());
    expect(back.activeSeconds, 75);
    expect(back.copyWith(exerciseLogs: const []).activeSeconds, 75);
    expect(WorkoutSession.fromJson(_session().toJson()).activeSeconds, isNull);
  });
}
