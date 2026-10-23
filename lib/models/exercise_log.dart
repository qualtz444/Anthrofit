import '../core/id.dart';
import '../core/json_utils.dart';
import 'enums.dart';
import 'planned_exercise.dart';
import 'planned_set.dart';

/// One ACTUAL set the user performed. Nullable values = not entered yet.
/// weightKg stays null for bodyweight sets.
/// [setType] is copied from the planned set when the session starts, so the
/// log keeps the set's classification. Sessions saved before set types
/// existed load as Working.
class SetLog {
  final int setNumber;
  final SetType setType;
  final double? weightKg;
  final int? reps;

  /// How long the set lasted, for cardio. Reps and load mean nothing on a
  /// treadmill, so a cardio set records time instead and leaves them null.
  final int? durationSeconds;
  final bool isCompleted;
  final DateTime? completedAt;

  /// The user skipped this set. It stops the exercise waiting for it, but
  /// nothing in it counts: a skipped set is never a completed set.
  final bool skipped;

  /// Seconds between finishing the previous set and finishing this one,
  /// measured only while the workout screen stayed open. Null for the first
  /// set, after a break (app closed, phone locked), and for older sessions.
  /// It includes doing this set, so it is "time between sets", not pure rest.
  final int? restBeforeSeconds;

  const SetLog({
    required this.setNumber,
    this.setType = SetType.working,
    this.weightKg,
    this.reps,
    this.durationSeconds,
    this.isCompleted = false,
    this.completedAt,
    this.skipped = false,
    this.restBeforeSeconds,
  });

  /// Done with, one way or the other: either logged or deliberately skipped.
  bool get isSettled => isCompleted || skipped;

  SetLog copyWith({
    int? setNumber,
    SetType? setType,
    double? weightKg,
    int? reps,
    int? durationSeconds,
    bool? isCompleted,
    DateTime? completedAt,
    bool? skipped,
    int? restBeforeSeconds,
  }) {
    return SetLog(
      setNumber: setNumber ?? this.setNumber,
      setType: setType ?? this.setType,
      weightKg: weightKg ?? this.weightKg,
      reps: reps ?? this.reps,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt ?? this.completedAt,
      skipped: skipped ?? this.skipped,
      restBeforeSeconds: restBeforeSeconds ?? this.restBeforeSeconds,
    );
  }

  /// Clears what was logged, so a set completed by mistake goes back to
  /// waiting. copyWith cannot do this: its null means "leave alone".
  SetLog cleared() => SetLog(setNumber: setNumber, setType: setType);

  Map<String, dynamic> toJson() => {
    'setNumber': setNumber,
    'setType': setType.name,
    'weightKg': weightKg,
    'reps': reps,
    'durationSeconds': durationSeconds,
    'isCompleted': isCompleted,
    'completedAt': completedAt?.toIso8601String(),
    'skipped': skipped,
    'restBeforeSeconds': restBeforeSeconds,
  };

  factory SetLog.fromJson(Map<String, dynamic> json) {
    return SetLog(
      setNumber: parseInt(json['setNumber'], 1),
      setType: enumByName(SetType.values, json['setType'], SetType.working),
      weightKg: parseNullableDouble(json['weightKg']),
      reps: parseNullableInt(json['reps']),
      durationSeconds: parseNullableInt(json['durationSeconds']),
      skipped: json['skipped'] == true,
      isCompleted: json['isCompleted'] == true,
      completedAt: parseDate(json['completedAt']),
      restBeforeSeconds: parseNullableInt(json['restBeforeSeconds']),
    );
  }
}

/// What ACTUALLY happened for one exercise in a session.
///
/// [plannedSets] is a frozen copy of the plan at session start, in the same
/// order as [sets], so editing the program later never rewrites history.
/// The plan itself (PlannedExercise) is never modified by logging.
class ExerciseLog {
  final String id;
  final String exerciseId;
  final String plannedExerciseId;
  final String exerciseName;
  final List<PlannedSet> plannedSets;
  final String targetNote;
  final List<SetLog> sets;

  /// The user skipped this exercise during the session. The log is kept so
  /// history shows what was skipped, but nothing in it counts as performance:
  /// progression ignores a skipped log entirely.
  final bool skipped;

  /// Set when this exercise replaced another one mid-session. The log records
  /// what was ACTUALLY performed, and this says what it stood in for, so
  /// history can show "instead of Barbell Bench Press". The program itself is
  /// never changed by a substitution.
  final String substitutedForName;

  const ExerciseLog({
    required this.id,
    required this.exerciseId,
    required this.plannedExerciseId,
    required this.exerciseName,
    this.plannedSets = const [],
    this.targetNote = '',
    this.sets = const [],
    this.skipped = false,
    this.substitutedForName = '',
  });

  /// Creates an empty log with one blank SetLog per planned set, each carrying
  /// that planned set's type.
  factory ExerciseLog.fromPlanned(
    PlannedExercise planned,
    String exerciseName,
  ) {
    return ExerciseLog(
      id: generateId(),
      exerciseId: planned.exerciseId,
      plannedExerciseId: planned.id,
      exerciseName: exerciseName,
      plannedSets: List.of(planned.plannedSets),
      targetNote: planned.note,
      sets: [
        for (var i = 0; i < planned.plannedSets.length; i++)
          SetLog(setNumber: i + 1, setType: planned.plannedSets[i].setType),
      ],
    );
  }

  /// The planned target for the set at [index], or null if there is none.
  PlannedSet? plannedSetFor(int index) =>
      index >= 0 && index < plannedSets.length ? plannedSets[index] : null;

  List<SetLog> get completedSets =>
      skipped ? const [] : sets.where((s) => s.isCompleted).toList();

  bool get wasSubstituted => substitutedForName.isNotEmpty;

  ExerciseLog copyWith({
    String? exerciseId,
    String? exerciseName,
    List<PlannedSet>? plannedSets,
    List<SetLog>? sets,
    bool? skipped,
    String? substitutedForName,
  }) {
    return ExerciseLog(
      id: id,
      exerciseId: exerciseId ?? this.exerciseId,
      plannedExerciseId: plannedExerciseId,
      exerciseName: exerciseName ?? this.exerciseName,
      plannedSets: plannedSets ?? this.plannedSets,
      targetNote: targetNote,
      sets: sets ?? this.sets,
      skipped: skipped ?? this.skipped,
      substitutedForName: substitutedForName ?? this.substitutedForName,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'exerciseId': exerciseId,
    'plannedExerciseId': plannedExerciseId,
    'exerciseName': exerciseName,
    'plannedSets': plannedSets.map((s) => s.toJson()).toList(),
    'skipped': skipped,
    'substitutedForName': substitutedForName,
    'targetNote': targetNote,
    'sets': sets.map((s) => s.toJson()).toList(),
  };

  /// Reads both formats.
  ///  New: a "plannedSets" list.
  ///  Old (before individual sets): one shared target ("targetSets",
  ///  "targetRepMin", "targetRepMax", "targetRestSeconds"). It becomes that
  ///  many Working planned sets. Old SetLogs have no type and load as Working.
  factory ExerciseLog.fromJson(Map<String, dynamic> json) {
    final sets = parseMapList(json['sets']).map(SetLog.fromJson).toList();
    final raw = json['plannedSets'];
    final planned = raw is List
        ? parseMapList(raw).map(PlannedSet.fromJson).toList()
        : _fromOldTargets(json, sets.length);

    return ExerciseLog(
      id: parseString(json['id']),
      exerciseId: parseString(json['exerciseId']),
      plannedExerciseId: parseString(json['plannedExerciseId']),
      exerciseName: parseString(json['exerciseName']),
      plannedSets: planned,
      targetNote: parseString(json['targetNote']),
      skipped: json['skipped'] == true,
      substitutedForName: parseString(json['substitutedForName']),
      sets: sets,
    );
  }

  static List<PlannedSet> _fromOldTargets(
    Map<String, dynamic> json,
    int setCount,
  ) {
    final oldCount = parseInt(json['targetSets']);
    final count = oldCount > 0 ? oldCount : setCount;
    final min = parseInt(json['targetRepMin']);
    final max = parseInt(json['targetRepMax']);
    final hasReps = min > 0;
    final rest = parseInt(
      json['targetRestSeconds'],
      PlannedSet.defaultRestSeconds,
    );

    return List.generate(
      count,
      (_) => PlannedSet(
        setType: SetType.working,
        targetRepMin: hasReps ? min : null,
        targetRepMax: hasReps ? (max >= min ? max : min) : null,
        restSeconds: rest < 0 ? PlannedSet.defaultRestSeconds : rest,
      ),
    );
  }
}
