import '../models/models.dart';

// Sets, reps, rest and weekly frequency, from:
//
//   ACSM (2009). Position stand: Progression models in resistance training
//   for healthy adults. Med Sci Sports Exerc 41(3):687-708.
//   Evidence categories (A strongest to D) are noted beside each value.
//
// The position stand gives ranges; a program needs one number. Where the app
// picks inside a range it says so below. Those picks are APP CHOICES, not
// ACSM findings.

/// Which ACSM program type a goal is trained as.
///
/// APP CHOICE: ACSM has no "fat loss" or "body composition" program. Both are
/// trained as hypertrophy, so muscle is kept while body fat changes through
/// diet. Athletic performance is trained as ACSM's power program.
enum AcsmProgram { strength, hypertrophy, power }

AcsmProgram acsmProgramFor(TrainingGoal goal) => switch (goal) {
  TrainingGoal.getStronger => AcsmProgram.strength,
  TrainingGoal.buildMuscle ||
  TrainingGoal.improveBodyComposition ||
  TrainingGoal.loseFat => AcsmProgram.hypertrophy,
  TrainingGoal.improveAthleticPerformance => AcsmProgram.power,
};

/// ACSM's weekly training frequency for an experience level, days a week.
///   Beginner 2-3 (A), intermediate 3-4 (B), advanced 4-6 (C).
/// Shown as guidance next to the days the user chose; never overrides them.
(int, int) acsmDaysPerWeek(ExperienceLevel experience) => switch (experience) {
  ExperienceLevel.beginner => (2, 3),
  ExperienceLevel.intermediate => (3, 4),
  ExperienceLevel.advanced => (4, 6),
};

class PrescriptionRules {
  const PrescriptionRules({
    this.cardioDurationSeconds = const {
      TrainingGoal.getStronger: 600,
      TrainingGoal.buildMuscle: 600,
      TrainingGoal.improveBodyComposition: 900,
      TrainingGoal.loseFat: 1200,
      TrainingGoal.improveAthleticPerformance: 900,
    },
    this.cardioSets = 1,
    this.workSecondsPerSet = 60,
  });

  /// How long one cardio bout lasts, per goal, in seconds.
  /// NOT SOURCED: ACSM 2009 covers resistance training only. These remain
  /// app heuristics: longer for fat loss, shorter when cardio only supports
  /// a strength or muscle program.
  final Map<TrainingGoal, int> cardioDurationSeconds;

  /// Cardio is one continuous bout, not several sets.
  final int cardioSets;

  /// Time one set takes BEFORE its rest: the reps plus getting set up.
  /// NOT SOURCED: an app heuristic. Added to the prescribed rest to estimate
  /// how long a set costs, so a session's length follows its rest periods.
  final int workSecondsPerSet;

  static const PrescriptionRules standard = PrescriptionRules();

  /// Sets per exercise.
  ///
  /// ACSM: 1-3 sets for beginners (A); "multiple sets" for intermediate (B);
  /// 3-6 for advanced hypertrophy (C); 3-5 for power. APP CHOICE: 3, the one
  /// count inside every one of those ranges.
  int setsFor(TrainingGoal goal, ExperienceLevel experience) => 3;

  /// (min, max) target reps.
  ///
  ///   Strength     beginner, intermediate  8-12 (60-70% 1RM, A)
  ///                advanced                1-6 (heavy emphasis, summary)
  ///   Hypertrophy  beginner, intermediate  8-12 (70-85% 1RM, A)
  ///                advanced                6-12 (emphasis zone, summary)
  ///   Power        all levels              3-6 (A, stated for beginners;
  ///                                        APP CHOICE to use it for all)
  (int, int) repsFor(TrainingGoal goal, ExperienceLevel experience) {
    final advanced = experience == ExperienceLevel.advanced;
    return switch (acsmProgramFor(goal)) {
      AcsmProgram.strength => advanced ? (1, 6) : (8, 12),
      AcsmProgram.hypertrophy => advanced ? (6, 12) : (8, 12),
      AcsmProgram.power => (3, 6),
    };
  }

  /// Rest between sets, in seconds.
  ///
  ///   Strength, power  compound (core) lifts  at least 2-3 min (B; D power)
  ///                    isolation (assistance)  1-2 min (C)
  ///   Hypertrophy      all                     1-2 min (C)
  /// APP CHOICE: the top of each range (180 s, 120 s), so "at least" holds.
  /// ACSM adds that advanced hypertrophy MAY rest 2-3 min on heavy core lifts
  /// (C); the app keeps the main 1-2 min recommendation.
  int restFor(TrainingGoal goal, ExperienceLevel experience, Exercise exercise) {
    final isolation = exercise.movementPattern == MovementPattern.isolation;
    return switch (acsmProgramFor(goal)) {
      AcsmProgram.strength || AcsmProgram.power => isolation ? 120 : 180,
      AcsmProgram.hypertrophy => 120,
    };
  }

  /// How long a cardio bout should last for [goal].
  int cardioDurationFor(TrainingGoal goal) =>
      cardioDurationSeconds[goal] ?? 600;

  /// Estimated seconds one set costs: its work plus the compound rest for
  /// the goal. Compound rest is the longer one, so the estimate errs towards
  /// fitting the session rather than overrunning it.
  int secondsPerSet(TrainingGoal goal) {
    final compoundRest = switch (acsmProgramFor(goal)) {
      AcsmProgram.strength || AcsmProgram.power => 180,
      AcsmProgram.hypertrophy => 120,
    };
    return workSecondsPerSet + compoundRest;
  }

  /// How many exercises a session of [duration] can hold at [sets] each,
  /// for [goal]. At least one, so a short session still produces a workout.
  int exerciseCountFor(SessionDuration duration, int sets, TrainingGoal goal) {
    final capacity = (duration.minutes * 60) ~/ (secondsPerSet(goal) * sets);
    return capacity < 1 ? 1 : capacity;
  }

  /// Estimated minutes for one planned exercise, from its own sets and rest.
  /// Cardio is its bout length. Used to check a session fits its length.
  double estimatedMinutes(PlannedExercise planned) {
    var seconds = 0;
    for (final set in planned.plannedSets) {
      final duration = set.targetDurationSeconds;
      seconds += duration != null && duration > 0
          ? duration
          : workSecondsPerSet + set.restSeconds;
    }
    return seconds / 60;
  }
}
