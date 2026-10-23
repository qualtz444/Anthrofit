import '../core/json_utils.dart';
import 'enums.dart';

/// A reusable exercise DEFINITION: what the movement is.
/// No sets, reps, or history here. The exercise library is the source of truth.
class Exercise {
  final String id;
  final String name;
  final ExerciseType exerciseType;
  final MovementPattern movementPattern;
  final List<MuscleGroup> primaryMuscles;
  final List<MuscleGroup> secondaryMuscles;
  final List<EquipmentItem> equipment;

  /// Equipment an admin added (ids of admin equipment), needed on top of
  /// [equipment]. Empty for every built-in exercise.
  final List<String> extraEquipment;
  final ExperienceLevel experienceLevel;
  final Complexity complexity;
  final List<String> instructions;

  const Exercise({
    required this.id,
    required this.name,
    required this.exerciseType,
    required this.movementPattern,
    required this.primaryMuscles,
    this.secondaryMuscles = const [],
    required this.equipment,
    this.extraEquipment = const [],
    required this.experienceLevel,
    required this.complexity,
    this.instructions = const [],
  });

  /// Everything except [id], which never changes: programs and saved sessions
  /// refer to an exercise by its id.
  Exercise copyWith({
    String? name,
    ExerciseType? exerciseType,
    MovementPattern? movementPattern,
    List<MuscleGroup>? primaryMuscles,
    List<MuscleGroup>? secondaryMuscles,
    List<EquipmentItem>? equipment,
    List<String>? extraEquipment,
    ExperienceLevel? experienceLevel,
    Complexity? complexity,
    List<String>? instructions,
  }) {
    return Exercise(
      id: id,
      name: name ?? this.name,
      exerciseType: exerciseType ?? this.exerciseType,
      movementPattern: movementPattern ?? this.movementPattern,
      primaryMuscles: primaryMuscles ?? this.primaryMuscles,
      secondaryMuscles: secondaryMuscles ?? this.secondaryMuscles,
      equipment: equipment ?? this.equipment,
      extraEquipment: extraEquipment ?? this.extraEquipment,
      experienceLevel: experienceLevel ?? this.experienceLevel,
      complexity: complexity ?? this.complexity,
      instructions: instructions ?? this.instructions,
    );
  }

  // Exercises the user adds or edits are saved on the device, so the library
  // is no longer only the built-in list. Enums are stored by `.name`, as
  // everywhere else.

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'exerciseType': exerciseType.name,
    'movementPattern': movementPattern.name,
    'primaryMuscles': enumNames(primaryMuscles),
    'secondaryMuscles': enumNames(secondaryMuscles),
    'equipment': enumNames(equipment),
    if (extraEquipment.isNotEmpty) 'extraEquipment': extraEquipment,
    'experienceLevel': experienceLevel.name,
    'complexity': complexity.name,
    'instructions': instructions,
  };

  factory Exercise.fromJson(Map<String, dynamic> json) {
    final instructions = json['instructions'];
    final extra = json['extraEquipment'];
    return Exercise(
      id: parseString(json['id']),
      name: parseString(json['name']),
      exerciseType: enumByName(
        ExerciseType.values,
        json['exerciseType'],
        ExerciseType.machine,
      ),
      movementPattern: enumByName(
        MovementPattern.values,
        json['movementPattern'],
        MovementPattern.isolation,
      ),
      primaryMuscles: enumListByName(
        MuscleGroup.values,
        json['primaryMuscles'],
      ),
      secondaryMuscles: enumListByName(
        MuscleGroup.values,
        json['secondaryMuscles'],
      ),
      equipment: enumListByName(EquipmentItem.values, json['equipment']),
      extraEquipment: extra is List
          ? extra.whereType<String>().toList()
          : const [],
      experienceLevel: enumByName(
        ExperienceLevel.values,
        json['experienceLevel'],
        ExperienceLevel.beginner,
      ),
      complexity: enumByName(
        Complexity.values,
        json['complexity'],
        Complexity.low,
      ),
      instructions: instructions is List
          ? instructions.whereType<String>().toList()
          : const [],
    );
  }
}
