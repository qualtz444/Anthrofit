import '../core/json_utils.dart';
import 'exercise_log.dart';

/// One performance of a Workout. Created when the user taps Start Workout.
/// A completed session (completedAt != null) is a History entry.
class WorkoutSession {
  final String id;
  final String? programId;

  /// Frozen copy of the program's name when the session started, so history
  /// still reads correctly after the program is renamed, archived or deleted.
  /// Empty for sessions saved before this was recorded.
  final String programName;
  final String workoutId;
  final String workoutName; // frozen copy, survives renames/deletes
  final DateTime startedAt;
  final DateTime? completedAt;
  final List<ExerciseLog> exerciseLogs;
  final bool guidedMode;

  /// Seconds the workout screen was actually open, counted while the app is
  /// in front. Null for sessions saved before this was tracked.
  final int? activeSeconds;

  const WorkoutSession({
    required this.id,
    this.programId,
    this.programName = '',
    required this.workoutId,
    required this.workoutName,
    required this.startedAt,
    this.completedAt,
    this.exerciseLogs = const [],
    this.guidedMode = false,
    this.activeSeconds,
  });

  bool get isCompleted => completedAt != null;

  /// How long the workout took. Null while the session is still in progress.
  ///
  /// The time the workout screen was open, so a workout started, left for
  /// hours and finished later only counts the time spent on it. Sessions
  /// saved before that was tracked fall back to start-to-finish.
  Duration? get duration {
    final end = completedAt;
    if (end == null) return null;
    final active = activeSeconds;
    if (active != null) return Duration(seconds: active);
    return end.difference(startedAt);
  }

  int get completedSetCount =>
      exerciseLogs.fold(0, (sum, log) => sum + log.completedSets.length);

  WorkoutSession copyWith({
    DateTime? completedAt,
    List<ExerciseLog>? exerciseLogs,
    int? activeSeconds,
  }) {
    return WorkoutSession(
      id: id,
      programId: programId,
      programName: programName,
      workoutId: workoutId,
      workoutName: workoutName,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
      exerciseLogs: exerciseLogs ?? this.exerciseLogs,
      guidedMode: guidedMode,
      activeSeconds: activeSeconds ?? this.activeSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'programId': programId,
    'programName': programName,
    'workoutId': workoutId,
    'workoutName': workoutName,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'exerciseLogs': exerciseLogs.map((e) => e.toJson()).toList(),
    'guidedMode': guidedMode,
    'activeSeconds': activeSeconds,
  };

  factory WorkoutSession.fromJson(Map<String, dynamic> json) {
    final rawProgramId = json['programId'];
    return WorkoutSession(
      id: parseString(json['id']),
      programId: rawProgramId is String ? rawProgramId : null,
      programName: parseString(json['programName']),
      workoutId: parseString(json['workoutId']),
      workoutName: parseString(json['workoutName']),
      startedAt: parseDate(json['startedAt']) ?? DateTime.now(),
      completedAt: parseDate(json['completedAt']),
      exerciseLogs: parseMapList(
        json['exerciseLogs'],
      ).map(ExerciseLog.fromJson).toList(),
      guidedMode: json['guidedMode'] == true,
      activeSeconds: json['activeSeconds'] is num
          ? (json['activeSeconds'] as num).toInt()
          : null,
    );
  }
}
