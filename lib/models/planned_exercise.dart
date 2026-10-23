import '../core/id.dart';
import '../core/json_utils.dart';
import 'enums.dart';
import 'planned_set.dart';

/// How an Exercise is PRESCRIBED inside a Workout: which exercise, one
/// PlannedSet per set, and an optional note.
/// Points to the library by [exerciseId]; never copies the definition.
/// Order = position in Workout.exercises (reordering = moving in the list).
class PlannedExercise {
  final String id;
  final String exerciseId;

  /// In performing order. Each set has its own type, reps, load and rest.
  final List<PlannedSet> plannedSets;
  final String note;

  const PlannedExercise({
    required this.id,
    required this.exerciseId,
    required this.plannedSets,
    this.note = '',
  });

  /// A new exercise with the default prescription: 3 Working sets of 8-12
  /// reps, 90 sec rest, no target load.
  ///
  /// Cardio instead gets one bout of 10 minutes, because reps and rest mean
  /// nothing on a treadmill. [isCardio] is passed in rather than looked up,
  /// so this model stays independent of the exercise library.
  factory PlannedExercise.withDefaults(
    String exerciseId, {
    bool isCardio = false,
  }) {
    return PlannedExercise(
      id: generateId(),
      exerciseId: exerciseId,
      plannedSets: isCardio
          ? const [
              PlannedSet(
                setType: SetType.working,
                targetDurationSeconds: 600,
                restSeconds: 0,
              ),
            ]
          : List.generate(
              PlannedSet.defaultSetCount,
              (_) => PlannedSet.defaultWorking(),
            ),
    );
  }

  int get setCount => plannedSets.length;

  PlannedExercise copyWith({
    String? exerciseId,
    List<PlannedSet>? plannedSets,
    String? note,
  }) {
    return PlannedExercise(
      id: id,
      exerciseId: exerciseId ?? this.exerciseId,
      plannedSets: plannedSets ?? this.plannedSets,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'exerciseId': exerciseId,
    'plannedSets': plannedSets.map((s) => s.toJson()).toList(),
    'note': note,
  };

  /// Reads both formats.
  ///  New: a "plannedSets" list.
  ///  Old (before individual sets): one shared prescription ("sets",
  ///  "repMin", "repMax", "restSeconds"). It becomes that many Working sets
  ///  with the same reps and rest, and no target load.
  factory PlannedExercise.fromJson(Map<String, dynamic> json) {
    final raw = json['plannedSets'];
    var sets = raw is List
        ? parseMapList(raw).map(PlannedSet.fromJson).toList()
        : <PlannedSet>[];
    if (sets.isEmpty) sets = _fromOldPrescription(json);

    return PlannedExercise(
      id: parseString(json['id']),
      exerciseId: parseString(json['exerciseId']),
      plannedSets: sets,
      note: parseString(json['note']),
    );
  }

  static List<PlannedSet> _fromOldPrescription(Map<String, dynamic> json) {
    final oldCount = parseInt(json['sets']);
    final count = oldCount > 0 ? oldCount : PlannedSet.defaultSetCount;

    final oldMin = parseInt(json['repMin']);
    final hasRange = oldMin > 0;
    final min = hasRange ? oldMin : PlannedSet.defaultRepMin;
    final oldMax = parseInt(json['repMax']);
    final max = hasRange
        ? (oldMax >= oldMin ? oldMax : oldMin)
        : PlannedSet.defaultRepMax;

    final oldRest = json['restSeconds'];
    final rest = oldRest is num && oldRest >= 0
        ? oldRest.toInt()
        : PlannedSet.defaultRestSeconds;

    return List.generate(
      count,
      (_) => PlannedSet(
        setType: SetType.working,
        targetRepMin: min,
        targetRepMax: max,
        restSeconds: rest,
      ),
    );
  }
}
