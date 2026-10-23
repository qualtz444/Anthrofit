import 'package:flutter/foundation.dart';

import '../core/id.dart';
import '../data/exercise_library.dart';
import '../data/session_repository.dart';
import '../models/models.dart';

/// Owns workout sessions: the one in progress and the completed ones.
///
/// A session only ever COPIES what it needs from the plan (see
/// ExerciseLog.fromPlanned). Nothing here changes a Program, Workout,
/// PlannedExercise, or Exercise.
///
/// Every change is saved first; memory only updates if the save worked.
class SessionController extends ChangeNotifier {
  SessionController(this._repository);

  final SessionRepository _repository;

  WorkoutSession? _active;
  List<WorkoutSession> _completed = const [];
  // Same list instance until something changes, so reading it is cheap.
  List<WorkoutSession> _completedView = const [];
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  /// The workout in progress, or null.
  WorkoutSession? get activeSession => _active;

  /// Completed sessions, oldest first. Phase 7 reads these.
  List<WorkoutSession> get completedSessions => _completedView;

  Future<void> load() async {
    try {
      final data = await _repository.load();
      _active = data.activeSession;
      _completed = data.sessions;
    } catch (_) {
      _active = null;
      _completed = const [];
    }
    _completedView = List.unmodifiable(_completed);
    _isLoaded = true;
    notifyListeners();
  }

  /// Starts a new session from a workout, with the exercises in plan order and
  /// one blank set per planned set. Replaces any session already in progress,
  /// so callers should ask the user first.
  Future<WorkoutSession> startSession(
    TrainingProgram program,
    Workout workout, {
    bool guidedMode = false,
    DateTime? now,
  }) async {
    final session = WorkoutSession(
      id: generateId(),
      programId: program.id,
      programName: program.name,
      workoutId: workout.id,
      workoutName: workout.name,
      startedAt: now ?? DateTime.now(),
      guidedMode: guidedMode,
      exerciseLogs: [
        for (final planned in workout.exercises)
          ExerciseLog.fromPlanned(
            planned,
            ExerciseLibrary.byId(planned.exerciseId)?.name ??
                'Unknown exercise',
          ),
      ],
    );
    await _commit(active: session, completed: _completed);
    return session;
  }

  /// Drops an unfinished workout that belongs to [programId].
  ///
  /// Called when a program is deleted: a workout in progress cannot outlive
  /// the program it came from, or Home keeps offering to resume something
  /// that no longer exists.
  ///
  /// COMPLETED sessions are untouched. History records what was actually
  /// done, and deleting a program does not undo having trained.
  ///
  /// Returns true if an unfinished workout was dropped.
  Future<bool> discardSessionForProgram(String programId) async {
    final session = _active;
    if (session == null || session.programId != programId) return false;
    await _commit(active: null, completed: _completed);
    return true;
  }

  /// Starts a session for ONE exercise, with no program behind it.
  ///
  /// The whole thing is made here and thrown away when the session ends:
  /// nothing is added to the user's programs, and the saved session simply
  /// has no program name, which history already handles.
  Future<WorkoutSession> startQuickSession(
    Exercise exercise, {
    PlannedExercise? planned,
    bool guidedMode = false,
    DateTime? now,
  }) async {
    // The caller can hand over a prescription the user set up; otherwise the
    // usual defaults for that kind of exercise.
    final prescription =
        planned ??
        PlannedExercise.withDefaults(
          exercise.id,
          isCardio: exercise.exerciseType == ExerciseType.cardio,
        );
    final session = WorkoutSession(
      id: generateId(),
      programId: '',
      programName: '',
      workoutId: '',
      workoutName: exercise.name,
      startedAt: now ?? DateTime.now(),
      guidedMode: guidedMode,
      exerciseLogs: [ExerciseLog.fromPlanned(prescription, exercise.name)],
    );
    await _commit(active: session, completed: _completed);
    return session;
  }

  /// Marks an exercise as skipped, or un-skips it.
  ///
  /// The log stays in the session so history shows what was skipped. Anything
  /// already logged is kept but stops counting: completedSets is empty while
  /// skipped, so progression and the progress figures ignore it.
  Future<void> setSkipped({
    required String exerciseLogId,
    required bool skipped,
  }) async {
    final session = _active;
    if (session == null) return;
    await _commit(
      active: session.copyWith(
        exerciseLogs: [
          for (final log in session.exerciseLogs)
            log.id == exerciseLogId ? log.copyWith(skipped: skipped) : log,
        ],
      ),
      completed: _completed,
    );
  }

  /// Swaps one exercise for another, for THIS session only.
  ///
  /// The log keeps its id and its planned sets, so the prescription carries
  /// over, but it now records the exercise actually performed. The program is
  /// untouched. Anything already logged against the old exercise is cleared,
  /// because those sets were not done on this movement.
  Future<void> substituteExercise({
    required String exerciseLogId,
    required Exercise replacement,
  }) async {
    final session = _active;
    if (session == null) return;
    await _commit(
      active: session.copyWith(
        exerciseLogs: [
          for (final log in session.exerciseLogs)
            if (log.id != exerciseLogId)
              log
            else
              log.copyWith(
                exerciseId: replacement.id,
                exerciseName: replacement.name,
                skipped: false,
                // Keep the first thing it stood in for, so swapping twice
                // still reports the exercise that was planned.
                substitutedForName: log.wasSubstituted
                    ? log.substitutedForName
                    : log.exerciseName,
                sets: [
                  for (final set in log.sets)
                    SetLog(setNumber: set.setNumber, setType: set.setType),
                ],
              ),
        ],
      ),
      completed: _completed,
    );
  }

  /// Adds a set to an exercise during the session.
  ///
  /// It copies the last planned set, so an extra set matches the ones before
  /// it. The program is not changed: the user is asked at the end whether to
  /// keep the new count.
  Future<void> addSet({
    required String exerciseLogId,
    SetType setType = SetType.working,
  }) async {
    final session = _active;
    if (session == null) return;
    await _commit(
      active: session.copyWith(
        exerciseLogs: [
          for (final log in session.exerciseLogs)
            if (log.id != exerciseLogId)
              log
            else
              log.copyWith(
                plannedSets: [
                  ...log.plannedSets,
                  (log.plannedSets.isEmpty
                          ? PlannedSet.defaultWorking()
                          : log.plannedSets.last)
                      .copyWith(setType: setType),
                ],
                sets: [
                  ...log.sets,
                  SetLog(setNumber: log.sets.length + 1, setType: setType),
                ],
              ),
        ],
      ),
      completed: _completed,
    );
  }

  /// Removes a set from an exercise during the session.
  ///
  /// The sets after it are renumbered, so they stay 1, 2, 3. The last
  /// remaining set cannot be removed: an exercise with no sets is not an
  /// exercise.
  Future<void> removeSet({
    required String exerciseLogId,
    required int setNumber,
  }) async {
    final session = _active;
    if (session == null) return;
    await _commit(
      active: session.copyWith(
        exerciseLogs: [
          for (final log in session.exerciseLogs)
            if (log.id != exerciseLogId || log.sets.length <= 1)
              log
            else
              log.copyWith(
                plannedSets: [
                  for (var i = 0; i < log.plannedSets.length; i++)
                    if (i != setNumber - 1) log.plannedSets[i],
                ],
                sets: _renumbered(
                  log.sets.where((s) => s.setNumber != setNumber).toList(),
                ),
              ),
        ],
      ),
      completed: _completed,
    );
  }

  /// The same sets numbered 1, 2, 3 again after one was removed.
  static List<SetLog> _renumbered(List<SetLog> sets) => [
    for (var i = 0; i < sets.length; i++) _renumber(sets[i], i + 1),
  ];

  /// A copy of [set] with a new position in the list.
  static SetLog _renumber(SetLog set, int setNumber) => SetLog(
    setNumber: setNumber,
    setType: set.setType,
    weightKg: set.weightKg,
    reps: set.reps,
    durationSeconds: set.durationSeconds,
    isCompleted: set.isCompleted,
    completedAt: set.completedAt,
    skipped: set.skipped,
  );

  /// Skips one set, or puts it back.
  ///
  /// A skipped set stops the exercise waiting for it, but never counts as
  /// performance. Anything logged against it is cleared, because a skipped
  /// set was not performed.
  Future<void> setSetSkipped({
    required String exerciseLogId,
    required int setNumber,
    required bool skipped,
  }) => _changeSet(
    exerciseLogId: exerciseLogId,
    setNumber: setNumber,
    change: (set) =>
        skipped ? set.cleared().copyWith(skipped: true) : set.cleared(),
  );

  /// Puts a set back to waiting, clearing what was logged.
  ///
  /// For a set completed by mistake: correcting one set should never mean
  /// discarding the whole workout.
  Future<void> clearSet({
    required String exerciseLogId,
    required int setNumber,
  }) => _changeSet(
    exerciseLogId: exerciseLogId,
    setNumber: setNumber,
    change: (set) => set.cleared(),
  );

  /// Changes the planned rest of one set, for THIS session only. The program
  /// keeps its own rest times.
  Future<void> setRestSeconds({
    required String exerciseLogId,
    required int setIndex,
    required int seconds,
  }) async {
    final session = _active;
    if (session == null) return;
    await _commit(
      active: session.copyWith(
        exerciseLogs: [
          for (final log in session.exerciseLogs)
            if (log.id != exerciseLogId)
              log
            else
              log.copyWith(
                plannedSets: [
                  for (var i = 0; i < log.plannedSets.length; i++)
                    i == setIndex
                        ? log.plannedSets[i].copyWith(restSeconds: seconds)
                        : log.plannedSets[i],
                ],
              ),
        ],
      ),
      completed: _completed,
    );
  }

  Future<void> _changeSet({
    required String exerciseLogId,
    required int setNumber,
    required SetLog Function(SetLog) change,
  }) async {
    final session = _active;
    if (session == null) return;
    await _commit(
      active: session.copyWith(
        exerciseLogs: [
          for (final log in session.exerciseLogs)
            if (log.id != exerciseLogId)
              log
            else
              log.copyWith(
                sets: [
                  for (final set in log.sets)
                    set.setNumber == setNumber ? change(set) : set,
                ],
              ),
        ],
      ),
      completed: _completed,
    );
  }

  /// Records what actually happened for one set, and marks it completed.
  /// Also used to correct a set that was already completed.
  /// [weightKg] null means no external load (bodyweight).
  Future<void> logSet({
    required String exerciseLogId,
    required int setNumber,
    required double? weightKg,
    required int reps,
    int? durationSeconds,
    DateTime? now,
    int? restBeforeSeconds,
  }) async {
    final session = _active;
    if (session == null) {
      throw StateError('There is no workout in progress.');
    }
    final logs = [
      for (final log in session.exerciseLogs)
        if (log.id == exerciseLogId)
          log.copyWith(
            sets: [
              for (final set in log.sets)
                if (set.setNumber == setNumber)
                  SetLog(
                    setNumber: set.setNumber,
                    setType: set.setType,
                    weightKg: weightKg,
                    reps: reps,
                    durationSeconds: durationSeconds,
                    isCompleted: true,
                    completedAt: set.completedAt ?? now ?? DateTime.now(),
                    // An edit keeps the time measured when it was first done.
                    restBeforeSeconds: set.isCompleted
                        ? set.restBeforeSeconds
                        : restBeforeSeconds,
                  )
                else
                  set,
            ],
          )
        else
          log,
    ];
    await _commit(
      active: session.copyWith(exerciseLogs: logs),
      completed: _completed,
    );
  }

  /// Finishes the session in progress and saves it with the completed ones.
  /// Every set must be dealt with: completed or skipped (a whole skipped
  /// exercise counts as dealt with). Skipped sets are saved as skipped and
  /// never count as done.
  ///
  /// [activeSeconds] is the time the workout screen was open, which is what
  /// the saved duration shows (see WorkoutSession.duration).
  Future<void> completeSession({
    DateTime? completedAt,
    int? activeSeconds,
  }) async {
    final session = _active;
    if (session == null) {
      throw StateError('There is no workout in progress.');
    }
    final allDone = session.exerciseLogs.every(
      (log) => log.skipped || log.sets.every((s) => s.isSettled),
    );
    if (!allDone) {
      throw StateError(
        'Complete or skip every set before finishing the workout.',
      );
    }
    final finished = session.copyWith(
      completedAt: completedAt ?? DateTime.now(),
      activeSeconds: activeSeconds,
    );
    await _commit(active: null, completed: [..._completed, finished]);
  }

  /// Adds [time] to the workout in progress's active time. Called when the
  /// workout screen goes to the background or is left, so time away from it
  /// is not counted. Does nothing when no workout is in progress.
  Future<void> addActiveTime(Duration time) async {
    final session = _active;
    if (session == null || time <= Duration.zero) return;
    await _commit(
      active: session.copyWith(
        activeSeconds: (session.activeSeconds ?? 0) + time.inSeconds,
      ),
      completed: _completed,
    );
  }

  /// Removes one completed workout, for a record logged by mistake. Saved
  /// first like every change, so Progress, history and progression all
  /// recalculate without it. Unknown ids are ignored.
  Future<void> deleteCompletedSession(String sessionId) async {
    if (!_completed.any((s) => s.id == sessionId)) return;
    await _commit(
      active: _active,
      completed: [
        for (final s in _completed)
          if (s.id != sessionId) s,
      ],
    );
  }

  /// Removes one exercise from a completed workout, for an exercise logged
  /// by mistake. When no exercise with a completed set would be left, the
  /// whole workout is removed instead (an empty workout is not a workout).
  /// Returns true when the whole workout went. Unknown ids change nothing.
  Future<bool> deleteCompletedExercise({
    required String sessionId,
    required String exerciseLogId,
  }) async {
    final index = _completed.indexWhere((s) => s.id == sessionId);
    if (index < 0) return false;
    final session = _completed[index];
    if (!session.exerciseLogs.any((l) => l.id == exerciseLogId)) return false;
    final logs = [
      for (final l in session.exerciseLogs)
        if (l.id != exerciseLogId) l,
    ];
    if (!logs.any((l) => l.completedSets.isNotEmpty)) {
      await deleteCompletedSession(sessionId);
      return true;
    }
    await _commit(
      active: _active,
      completed: [
        for (final s in _completed)
          s.id == sessionId ? s.copyWith(exerciseLogs: logs) : s,
      ],
    );
    return false;
  }

  /// Throws away the session in progress (nothing is added to completed).
  Future<void> discardActiveSession() async {
    if (_active == null) return;
    await _commit(active: null, completed: _completed);
  }

  Future<void> _commit({
    required WorkoutSession? active,
    required List<WorkoutSession> completed,
  }) async {
    await _repository.save(
      SessionData(activeSession: active, sessions: completed),
    );
    _active = active;
    _completed = completed;
    _completedView = List.unmodifiable(completed);
    notifyListeners();
  }
}
