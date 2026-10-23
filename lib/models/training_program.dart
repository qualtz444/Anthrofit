import '../core/id.dart';
import '../core/json_utils.dart';
import 'enums.dart';
import 'planned_exercise.dart';
import 'program_setup.dart';
import 'workout.dart';

/// One schedule slot: "on [day], do workout [workoutId]".
class ScheduledWorkout {
  final Weekday day;
  final String workoutId;

  const ScheduledWorkout({required this.day, required this.workoutId});

  Map<String, dynamic> toJson() => {'day': day.name, 'workoutId': workoutId};

  factory ScheduledWorkout.fromJson(Map<String, dynamic> json) {
    return ScheduledWorkout(
      day: enumByName(Weekday.values, json['day'], Weekday.monday),
      workoutId: parseString(json['workoutId']),
    );
  }
}

/// The SAVED result of planning.
/// TrainingProgram → schedule → Workout → PlannedExercise
/// Rule: at most one workout per weekday.
class TrainingProgram {
  final String id;
  final String name;

  /// This program's own goal. It starts as the profile goal when the program is
  /// created, but is separate from it. Null for programs saved before goals existed.
  final TrainingGoal? goal;

  /// What the user asked for when this program was created: goal, session
  /// length, muscles and equipment. Input for the future program generator,
  /// not something the app acts on yet. Null for programs made before setup
  /// existed, or created without it.
  final ProgramSetup? setup;

  /// Archived programs are kept but can never be the active program.
  /// Which program is ACTIVE is stored once, by id, in ProgramController.
  final bool archived;
  final List<Workout> workouts;
  final List<ScheduledWorkout> schedule;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Whether a body proportion scan was used when the app built this
  /// program: true, false, or null when unknown (programs made by hand, or
  /// saved before this was recorded).
  final bool? usedScan;

  /// When that scan was taken, if one was used.
  final DateTime? scanTakenAt;

  /// Whether that scan changed anything (a setup tip or a different
  /// exercise). False means it was checked and changed nothing. Null when
  /// unknown, including programs saved before this was recorded.
  final bool? scanChanged;

  const TrainingProgram({
    required this.id,
    required this.name,
    this.goal,
    this.setup,
    this.archived = false,
    this.workouts = const [],
    this.schedule = const [],
    required this.createdAt,
    required this.updatedAt,
    this.usedScan,
    this.scanTakenAt,
    this.scanChanged,
  });

  /// Training days, sorted Monday → Sunday.
  List<Weekday> get trainingDays {
    final days = schedule.map((s) => s.day).toSet().toList();
    days.sort((a, b) => a.index.compareTo(b.index));
    return days;
  }

  Workout? workoutById(String workoutId) {
    for (final w in workouts) {
      if (w.id == workoutId) return w;
    }
    return null;
  }

  /// Every workout on [day], in the order they were scheduled.
  ///
  /// A day can hold more than one: two sessions in a day, or a lift and some
  /// cardio. Entries pointing at a workout that no longer exists are skipped.
  List<Workout> workoutsForDay(Weekday day) => [
    for (final s in schedule)
      if (s.day == day) ?workoutById(s.workoutId),
  ];

  /// The first workout on [day], or null.
  ///
  /// For the places that can only show one. Prefer [workoutsForDay].
  Workout? workoutForDay(Weekday day) {
    final onDay = workoutsForDay(day);
    return onDay.isEmpty ? null : onDay.first;
  }

  /// Days a given workout is scheduled on, sorted Monday → Sunday.
  List<Weekday> daysForWorkout(String workoutId) {
    final days = schedule
        .where((s) => s.workoutId == workoutId)
        .map((s) => s.day)
        .toList();
    days.sort((a, b) => a.index.compareTo(b.index));
    return days;
  }

  TrainingProgram copyWith({
    String? name,
    TrainingGoal? goal,
    ProgramSetup? setup,
    bool? archived,
    List<Workout>? workouts,
    List<ScheduledWorkout>? schedule,
    DateTime? updatedAt,
  }) {
    return TrainingProgram(
      id: id,
      name: name ?? this.name,
      goal: goal ?? this.goal,
      setup: setup ?? this.setup,
      archived: archived ?? this.archived,
      workouts: workouts ?? this.workouts,
      schedule: schedule ?? this.schedule,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      usedScan: usedScan,
      scanTakenAt: scanTakenAt,
      scanChanged: scanChanged,
    );
  }

  /// The same program, recording whether it was built from a scan.
  /// Separate from copyWith, which cannot clear [scanTakenAt].
  TrainingProgram withScanBasis({
    required bool used,
    DateTime? takenAt,
    bool? changed,
  }) =>
      TrainingProgram(
        id: id,
        name: name,
        goal: goal,
        setup: setup,
        archived: archived,
        workouts: workouts,
        schedule: schedule,
        createdAt: createdAt,
        updatedAt: updatedAt,
        usedScan: used,
        scanTakenAt: used ? takenAt : null,
        scanChanged: used ? changed : null,
      );

  /// An independent copy: new ids for the program, its workouts and its
  /// planned exercises, with the schedule pointing at the new workouts.
  /// The copy is not archived. (It is never active: activation is separate.)
  /// Exercises still reference the same library ids, and PlannedSets are
  /// plain values, so nothing is shared with the original that could be edited.
  TrainingProgram duplicate({String? name, DateTime? now}) {
    final created = now ?? DateTime.now();
    final newWorkoutIds = <String, String>{};
    final copiedWorkouts = <Workout>[];
    for (final workout in workouts) {
      final newId = generateId();
      newWorkoutIds[workout.id] = newId;
      copiedWorkouts.add(
        Workout(
          id: newId,
          name: workout.name,
          focus: workout.focus,
          exercises: [
            for (final e in workout.exercises)
              PlannedExercise(
                id: generateId(),
                exerciseId: e.exerciseId,
                plannedSets: List.of(e.plannedSets),
                note: e.note,
              ),
          ],
        ),
      );
    }
    return TrainingProgram(
      id: generateId(),
      name: name ?? '${this.name} Copy',
      goal: goal,
      setup: setup,
      workouts: copiedWorkouts,
      schedule: [
        for (final slot in schedule)
          if (newWorkoutIds.containsKey(slot.workoutId))
            ScheduledWorkout(
              day: slot.day,
              workoutId: newWorkoutIds[slot.workoutId]!,
            ),
      ],
      createdAt: created,
      updatedAt: created,
      usedScan: usedScan,
      scanTakenAt: scanTakenAt,
      scanChanged: scanChanged,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'goal': goal?.name,
    'setup': setup?.toJson(),
    'archived': archived,
    'workouts': workouts.map((w) => w.toJson()).toList(),
    'schedule': schedule.map((s) => s.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'usedScan': usedScan,
    'scanTakenAt': scanTakenAt?.toIso8601String(),
    'scanChanged': scanChanged,
  };

  factory TrainingProgram.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final rawGoal = json['goal'];
    return TrainingProgram(
      id: parseString(json['id']),
      name: parseString(json['name']),
      // Programs saved before goals existed have none.
      goal: rawGoal is String
          ? TrainingGoal.values.where((g) => g.name == rawGoal).firstOrNull
          : null,
      setup: json['setup'] is Map
          ? ProgramSetup.fromJson(
              Map<String, dynamic>.from(json['setup'] as Map),
            )
          : null,
      archived: json['archived'] == true,
      workouts: parseMapList(json['workouts']).map(Workout.fromJson).toList(),
      schedule: parseMapList(
        json['schedule'],
      ).map(ScheduledWorkout.fromJson).toList(),
      createdAt: parseDate(json['createdAt']) ?? now,
      updatedAt: parseDate(json['updatedAt']) ?? now,
      usedScan: json['usedScan'] is bool ? json['usedScan'] as bool : null,
      scanTakenAt: parseDate(json['scanTakenAt']),
      scanChanged: json['scanChanged'] is bool
          ? json['scanChanged'] as bool
          : null,
    );
  }
}
