import '../core/id.dart';
import '../data/training_stats.dart';
import '../progress/strength_trends.dart';
import '../models/models.dart';
import 'community_models.dart';

/// Turns a finished workout into a post. Pure and deterministic: it reads
/// only the workout and the user's own completed history, and it never
/// includes anything from scans, body weight or photos.
///
/// A record is a top weight heavier than the top weight of every earlier
/// completed session for that exercise. The first time an exercise is done
/// is not a record: there is nothing to beat.
WorkoutPost buildWorkoutPost({
  required WorkoutSession session,
  required List<WorkoutSession> history,
  required CommunityProfile author,
  required List<String> friendUids,
  DateTime? now,
}) {
  final exercises = <PostExercise>[];
  final records = <PostRecord>[];
  var totalSets = 0;
  var volume = 0.0;

  for (final log in session.exerciseLogs) {
    if (log.skipped) continue;
    final sets = workSetsOf(log);
    if (sets.isEmpty) continue;
    totalSets += sets.length;

    SetLog? top;
    for (final s in sets) {
      if (isWeightedSet(s)) volume += s.weightKg! * (s.reps ?? 0);
      final better =
          top == null ||
          (s.weightKg ?? 0) > (top.weightKg ?? 0) ||
          ((s.weightKg ?? 0) == (top.weightKg ?? 0) &&
              (s.reps ?? 0) > (top.reps ?? 0));
      if (better) top = s;
    }
    exercises.add(
      PostExercise(
        name: log.exerciseName,
        sets: sets.length,
        topWeightKg: (top?.weightKg ?? 0) > 0 ? top!.weightKg : null,
        topReps: top?.reps,
      ),
    );

    final topKg = top?.weightKg ?? 0;
    if (topKg <= 0) continue;
    double? previousBest;
    for (final past in history) {
      if (!past.isCompleted || past.id == session.id) continue;
      for (final l in past.exerciseLogs) {
        if (l.skipped || l.exerciseId != log.exerciseId) continue;
        for (final s in workSetsOf(l)) {
          final kg = s.weightKg ?? 0;
          if (kg > (previousBest ?? 0)) previousBest = kg;
        }
      }
    }
    if (previousBest != null && topKg > previousBest) {
      records.add(PostRecord(exercise: log.exerciseName, weightKg: topKg));
    }
  }

  return WorkoutPost(
    // One post per workout: sharing again cannot duplicate it.
    id: '${author.uid}_${session.id}',
    authorUid: author.uid,
    authorHandle: author.handle,
    authorName: author.displayName,
    audience: {author.uid, ...friendUids}.toList(),
    createdAt: session.completedAt ?? now ?? DateTime.now(),
    workoutName: session.workoutName,
    durationMinutes: session.duration?.inMinutes ?? 0,
    totalSets: totalSets,
    volumeKg: volume,
    exercises: exercises,
    records: records,
  );
}

/// A program shared so friends can copy it.
///
/// Its setup and every exercise note are left out: the setup may come from
/// a body proportion scan, and notes can carry setup tips from it. Body data
/// is never shared, so friends get exercises, sets, reps, rest and schedule.
WorkoutPost buildProgramPost({
  required TrainingProgram program,
  required CommunityProfile author,
  required List<String> friendUids,
  DateTime? now,
}) {
  final created = now ?? DateTime.now();
  final json = program.toJson()
    ..['setup'] = null
    ..['workouts'] = [
      for (final w in program.workouts)
        Workout(
          id: w.id,
          name: w.name,
          focus: w.focus,
          exercises: [
            for (final e in w.exercises) e.copyWith(note: ''),
          ],
        ).toJson(),
    ];
  var sets = 0;
  for (final w in program.workouts) {
    for (final e in w.exercises) {
      sets += e.plannedSets.length;
    }
  }
  return WorkoutPost(
    id: '${author.uid}_program_${generateId()}',
    authorUid: author.uid,
    authorHandle: author.handle,
    authorName: author.displayName,
    audience: {author.uid, ...friendUids}.toList(),
    createdAt: created,
    workoutName: program.name,
    durationMinutes: 0,
    totalSets: sets,
    volumeKg: 0,
    exercises: const [],
    records: const [],
    kind: PostKind.program,
    program: json,
  );
}

/// Training progress over [range] (30 days by default), from completed workouts only:
/// how many workouts and sets, and each exercise's top weight first vs
/// latest session in the period. Body weight, body fat and scans are never
/// included.
///
/// An exercise needs two sessions with a weighted top set in the period to
/// show a change, and only changes (up or down) are listed, largest first.
WorkoutPost buildProgressPost({
  required List<WorkoutSession> sessions,
  required CommunityProfile author,
  required List<String> friendUids,
  DateTime? today,
  ProgressRange range = ProgressRange.month1,
  int maxChanges = 5,
}) {
  final now = today ?? DateTime.now();
  final done = [
    for (final s in sessions)
      if (s.isCompleted) s,
  ];
  final inRange = sessionsInRange(done, range, now);
  final summary = summarize(inRange);
  final changes = topWeightChanges(done, range, now);

  return WorkoutPost(
    id: '${author.uid}_progress_${generateId()}',
    authorUid: author.uid,
    authorHandle: author.handle,
    authorName: author.displayName,
    audience: {author.uid, ...friendUids}.toList(),
    createdAt: now,
    workoutName: 'My progress',
    durationMinutes: 0,
    totalSets: summary.sets,
    volumeKg: 0,
    exercises: const [],
    records: const [],
    kind: PostKind.progress,
    workoutCount: inRange.length,
    periodDays: range.days ?? 0,
    changes: changes.take(maxChanges).toList(),
  );
}

/// Each exercise's top weight, first vs latest session in [range], for every
/// exercise whose top weight changed (up or down), largest change first.
/// An exercise needs two sessions with a weighted top set to show a change.
List<PostChange> topWeightChanges(
  List<WorkoutSession> completed,
  ProgressRange range,
  DateTime today,
) {
  final names = <String, String>{};
  for (final s in sessionsInRange(completed, range, today)) {
    for (final l in s.exerciseLogs) {
      if (!l.skipped) names[l.exerciseId] = l.exerciseName;
    }
  }
  final changes = <PostChange>[];
  for (final e in names.entries) {
    final weighted = [
      for (final x in exerciseSessions(completed, e.key, range, today))
        if (x.topWeightKg != null) x,
    ];
    if (weighted.length < 2) continue;
    final from = weighted.first.topWeightKg!;
    final to = weighted.last.topWeightKg!;
    if (from == to) continue;
    changes.add(PostChange(exercise: e.value, fromKg: from, toKg: to));
  }
  changes.sort(
    (a, b) => (b.toKg - b.fromKg).abs().compareTo((a.toKg - a.fromKg).abs()),
  );
  return changes;
}
