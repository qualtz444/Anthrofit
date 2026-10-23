import '../core/json_utils.dart';
import 'planned_exercise.dart';

/// A reusable workout TEMPLATE (e.g. "Upper A").
/// Which days it runs on lives in TrainingProgram.schedule, not here.
class Workout {
  final String id;
  final String name;
  final String focus;
  final List<PlannedExercise> exercises;

  const Workout({
    required this.id,
    required this.name,
    this.focus = '',
    this.exercises = const [],
  });

  int get exerciseCount => exercises.length;

  /// All planned sets, warm-up sets included.
  int get totalSets =>
      exercises.fold(0, (sum, e) => sum + e.plannedSets.length);

  Workout copyWith({
    String? name,
    String? focus,
    List<PlannedExercise>? exercises,
  }) {
    return Workout(
      id: id,
      name: name ?? this.name,
      focus: focus ?? this.focus,
      exercises: exercises ?? this.exercises,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'focus': focus,
    'exercises': exercises.map((e) => e.toJson()).toList(),
  };

  factory Workout.fromJson(Map<String, dynamic> json) {
    return Workout(
      id: parseString(json['id']),
      name: parseString(json['name']),
      focus: parseString(json['focus']),
      exercises: parseMapList(
        json['exercises'],
      ).map(PlannedExercise.fromJson).toList(),
    );
  }
}
