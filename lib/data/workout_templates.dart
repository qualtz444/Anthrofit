import '../content/app_content.dart';
import '../core/id.dart';
import '../models/models.dart';
import 'exercise_library.dart';

// Starting points for new programs and workouts.
//
// A template is only a list of exercise IDs from the global Exercise Library.
// It never defines an exercise. Building a workout from a template creates
// ordinary PlannedExercises that reference those IDs, so the user owns and can
// change everything afterward. Templates are fixed lists: the same template
// always gives the same result (no randomness, no recommendations).
//
// Every slot is now filled by a real library exercise. If a template ever
// names an id the library does not have, buildWorkoutFromTemplate skips it
// rather than creating a PlannedExercise that points at nothing.

enum WorkoutTemplate {
  push('Push', 'Push', [
    'barbell_bench_press', // main horizontal push
    'machine_chest_press', // secondary push
    'dumbbell_shoulder_press', // vertical push
    'dumbbell_lateral_raise', // side delts
    'cable_triceps_pushdown', // triceps
  ]),
  pull('Pull', 'Pull', [
    'lat_pulldown', // main vertical pull
    'seated_cable_row', // main horizontal pull
    'chest_supported_dumbbell_row', // secondary pull
    'face_pull', // rear delts / upper back
    'dumbbell_biceps_curl', // biceps
  ]),
  legs('Legs', 'Legs', [
    'leg_press', // main knee-dominant
    'romanian_deadlift', // main hip-dominant
    'seated_leg_curl',
    'leg_extension',
    'standing_calf_raise', // calves
  ]),
  upper('Upper', 'Upper', [
    'machine_chest_press', // horizontal push
    'lat_pulldown', // vertical pull
    'dumbbell_shoulder_press', // vertical push
    'seated_cable_row', // horizontal pull
    'cable_triceps_pushdown', // triceps
    'dumbbell_biceps_curl', // biceps
  ]),
  lower('Lower', 'Lower', [
    'leg_press', // knee-dominant
    'barbell_hip_thrust', // hip-dominant
    'leg_extension', // quads
    'seated_leg_curl', // hamstrings
    'standing_calf_raise', // calves
  ]),
  fullBody('Full Body', 'Full Body', [
    'leg_press', // knee-dominant
    'machine_chest_press', // horizontal push
    'seated_cable_row', // horizontal pull
    'romanian_deadlift', // hip-dominant
    'dumbbell_shoulder_press', // vertical push
    'lat_pulldown', // vertical pull
  ]),
  cardio('Cardio', 'Cardio', [
    'rowing_machine',
    'stationary_bike',
    'treadmill_run',
  ]),
  // The user names it and adds exercises.
  custom('Custom', '', []);

  const WorkoutTemplate(this.label, this.defaultName, this.exerciseIds);

  /// Shown in the picker.
  final String label;

  /// The workout's starting name. Blank for Custom.
  final String defaultName;

  /// Exercise Library IDs, in the order they appear in the workout, as
  /// shipped with the app.
  final List<String> exerciseIds;

  /// The ids a new workout starts with: the admin's list for this template
  /// when there is one, otherwise [exerciseIds].
  List<String> get currentExerciseIds =>
      AppContent.templateExercises(name) ?? exerciseIds;
}

/// Which workouts a new program starts with.
enum ProgramTemplate {
  pushPullLegs('Push Pull Legs', 'Push Pull Legs Program', [
    WorkoutTemplate.push,
    WorkoutTemplate.pull,
    WorkoutTemplate.legs,
  ]),
  upperLower('Upper Lower', 'Upper Lower Program', [
    WorkoutTemplate.upper,
    WorkoutTemplate.lower,
  ]),
  fullBody('Full Body', 'Full Body Program', [WorkoutTemplate.fullBody]),
  custom('Custom', 'My Program', []);

  const ProgramTemplate(this.label, this.defaultName, this.workouts);

  final String label;

  /// The program's starting name.
  final String defaultName;

  /// Workouts created automatically, in order. No weekdays are assigned.
  final List<WorkoutTemplate> workouts;
}

/// A new workout from a template. IDs missing from the library are skipped, so
/// a template can never create a PlannedExercise that points at nothing.
Workout buildWorkoutFromTemplate(WorkoutTemplate template) {
  return Workout(
    id: generateId(),
    name: template.defaultName,
    exercises: [
      for (final exerciseId in template.currentExerciseIds)
        if (ExerciseLibrary.byId(exerciseId) != null)
          PlannedExercise.withDefaults(
            exerciseId,
            isCardio:
                ExerciseLibrary.byId(exerciseId)?.exerciseType ==
                ExerciseType.cardio,
          ),
    ],
  );
}

/// The workouts a new program starts with. Each program gets its own copies
/// (new IDs), so programs never share workouts.
List<Workout> buildWorkoutsForProgram(ProgramTemplate template) => [
  for (final w in template.workouts) buildWorkoutFromTemplate(w),
];
