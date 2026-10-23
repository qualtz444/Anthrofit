import '../content/app_content.dart';
import '../core/id.dart';
import '../core/json_utils.dart';
import '../models/models.dart';
import 'exercise_library.dart';
import 'workout_templates.dart';

/// A ready-made program offered in the Library.
///
/// It is a RECIPE, not a program: a template plus a goal and a suggested
/// week. Choosing one builds a normal TrainingProgram from the same
/// templates and the same exercise library the rest of the app uses, so
/// nothing here is a second source of workouts or exercises.
class ReadyMadeProgram {
  const ReadyMadeProgram({
    required this.id,
    required this.name,
    required this.summary,
    required this.template,
    required this.goal,
    required this.experience,
    required this.days,
  });

  /// Stable id for the recipe itself. Programs built from it get their own.
  final String id;

  final String name;

  /// One line on who it suits.
  final String summary;

  /// Which workouts it creates, from the existing template system.
  final ProgramTemplate template;

  final TrainingGoal goal;

  /// Who it is aimed at. Shown to the user; nothing filters on it.
  final ExperienceLevel experience;

  /// The suggested training days, in order. Workouts are dealt onto them in
  /// turn, so three workouts over three days gives one each.
  final List<Weekday> days;

  List<WorkoutTemplate> get workoutTemplates => template.workouts;

  // Stored by the admin panel in content/config. Enums by `.name`.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'summary': summary,
    'template': template.name,
    'goal': goal.name,
    'experience': experience.name,
    'days': enumNames(days),
  };

  factory ReadyMadeProgram.fromJson(Map<String, dynamic> json) =>
      ReadyMadeProgram(
        id: parseString(json['id']),
        name: parseString(json['name']),
        summary: parseString(json['summary']),
        template: enumByName(
          ProgramTemplate.values,
          json['template'],
          ProgramTemplate.fullBody,
        ),
        goal: enumByName(
          TrainingGoal.values,
          json['goal'],
          TrainingGoal.buildMuscle,
        ),
        experience: enumByName(
          ExperienceLevel.values,
          json['experience'],
          ExperienceLevel.beginner,
        ),
        days: enumListByName(Weekday.values, json['days']),
      );
}

/// The Library's ready-made programs.
///
/// IMPLEMENTATION HEURISTICS. Which days a split runs on, and how many, are
/// common gym conventions rather than findings. They are gathered here so
/// they can be changed in one place.
const List<ReadyMadeProgram> kReadyMadePrograms = [
  ReadyMadeProgram(
    id: 'ready_full_body_beginner',
    name: 'Full Body Beginner',
    summary: 'One full-body session, three times a week. A simple start.',
    template: ProgramTemplate.fullBody,
    goal: TrainingGoal.buildMuscle,
    experience: ExperienceLevel.beginner,
    days: [Weekday.monday, Weekday.wednesday, Weekday.friday],
  ),
  ReadyMadeProgram(
    id: 'ready_upper_lower',
    name: 'Upper / Lower',
    summary: 'Upper and lower body alternating, four days a week.',
    template: ProgramTemplate.upperLower,
    goal: TrainingGoal.buildMuscle,
    experience: ExperienceLevel.intermediate,
    days: [Weekday.monday, Weekday.tuesday, Weekday.thursday, Weekday.friday],
  ),
  ReadyMadeProgram(
    id: 'ready_push_pull_legs',
    name: 'Push / Pull / Legs',
    summary: 'The classic three-way split, once through each week.',
    template: ProgramTemplate.pushPullLegs,
    goal: TrainingGoal.buildMuscle,
    experience: ExperienceLevel.intermediate,
    days: [Weekday.monday, Weekday.wednesday, Weekday.friday],
  ),
  ReadyMadeProgram(
    id: 'ready_strength',
    name: 'Strength',
    summary: 'Upper and lower days aimed at lifting heavier, four a week.',
    template: ProgramTemplate.upperLower,
    goal: TrainingGoal.getStronger,
    experience: ExperienceLevel.intermediate,
    days: [Weekday.monday, Weekday.tuesday, Weekday.thursday, Weekday.friday],
  ),
  ReadyMadeProgram(
    id: 'ready_hypertrophy',
    name: 'Hypertrophy',
    summary: 'Push, pull and legs twice over, six days a week.',
    template: ProgramTemplate.pushPullLegs,
    goal: TrainingGoal.buildMuscle,
    experience: ExperienceLevel.advanced,
    days: [
      Weekday.monday,
      Weekday.tuesday,
      Weekday.wednesday,
      Weekday.thursday,
      Weekday.friday,
      Weekday.saturday,
    ],
  ),
  ReadyMadeProgram(
    id: 'ready_general_fitness',
    name: 'General Fitness',
    summary: 'Two full-body sessions a week, to keep ticking over.',
    template: ProgramTemplate.fullBody,
    goal: TrainingGoal.improveAthleticPerformance,
    experience: ExperienceLevel.beginner,
    days: [Weekday.tuesday, Weekday.saturday],
  ),
];

/// The ready-made programs on offer: the admin's list when there is one,
/// otherwise [kReadyMadePrograms].
List<ReadyMadeProgram> readyMadePrograms() => AppContent.readyMade;

ReadyMadeProgram? readyMadeById(String id) {
  for (final program in readyMadePrograms()) {
    if (program.id == id) return program;
  }
  return null;
}

/// The workouts [recipe] would create, for a preview and for building.
List<Workout> workoutsFor(ReadyMadeProgram recipe) =>
    buildWorkoutsForProgram(recipe.template);

/// Builds a normal, user-owned program from [recipe].
///
/// Everything gets fresh ids, so the program belongs to the user and editing
/// it can never change the recipe, which is const anyway. From here it is an
/// ordinary program: editable, schedulable, deletable, and saved by the same
/// repository as any other.
TrainingProgram programFromReadyMade(ReadyMadeProgram recipe, {DateTime? now}) {
  final created = now ?? DateTime.now();
  final workouts = workoutsFor(recipe);

  // Deal the workouts onto the suggested days in turn, so a three-workout
  // split over six days runs each one twice.
  final schedule = <ScheduledWorkout>[
    if (workouts.isNotEmpty)
      for (var i = 0; i < recipe.days.length; i++)
        ScheduledWorkout(
          day: recipe.days[i],
          workoutId: workouts[i % workouts.length].id,
        ),
  ];

  return TrainingProgram(
    id: generateId(),
    name: recipe.name,
    goal: recipe.goal,
    workouts: workouts,
    schedule: schedule,
    createdAt: created,
    updatedAt: created,
  );
}

/// Every muscle the recipe's workouts train, for the preview.
List<MuscleGroup> musclesOf(ReadyMadeProgram recipe) {
  final seen = <MuscleGroup>{};
  for (final workout in workoutsFor(recipe)) {
    for (final planned in workout.exercises) {
      seen.addAll(
        ExerciseLibrary.byId(planned.exerciseId)?.primaryMuscles ?? const [],
      );
    }
  }
  return MuscleGroup.values.where(seen.contains).toList();
}
