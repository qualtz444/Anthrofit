import '../content/app_content.dart';
import '../models/models.dart';
import 'proportion_rules.dart';
import 'recommendation_weights.dart';

/// Why an exercise was left out. Eligibility is separate from ranking: a
/// rejected exercise is never shown, a low-scoring one is simply further down.
enum RejectionReason {
  /// Needs equipment the user does not have.
  equipment,

  /// Trains none of the selected muscles.
  muscles,

  /// Asks for more experience than the user has.
  experience,

  /// Too technically demanding for the user's experience.
  complexity,
}

/// One exercise, scored, with the reasons behind it.
class ScoredExercise {
  const ScoredExercise({
    required this.exercise,
    required this.score,
    required this.reasons,
    this.setupCue,
  });

  final Exercise exercise;
  final double score;

  /// Short phrases, in the order they were earned, used for the explanation.
  final List<String> reasons;

  /// A proportion-based setup note, when a rule produced one.
  final String? setupCue;

  /// One sentence a person can read.
  ///
  /// Built from the structured reasons above: no generated text, and the same
  /// inputs always produce the same sentence.
  String get explanation {
    if (reasons.isEmpty) return 'Recommended as a general fit.';
    if (reasons.length == 1) return 'Recommended because it ${reasons.first}.';
    final last = reasons.last;
    final rest = reasons.sublist(0, reasons.length - 1);
    return 'Recommended because it ${rest.join(', ')} and $last.';
  }
}

/// Which goals each exercise type suits, as a rough fit from 0 to 1.
///
/// IMPLEMENTATION HEURISTIC. These say "a free-weight compound suits a
/// strength goal more than a machine isolation does", which is a common
/// coaching convention, not a measured finding.
double _goalFit(Exercise exercise, TrainingGoal goal) =>
    // An admin's value for this exercise replaces the heuristic.
    AppContent.goalFit(exercise.id, goal) ?? builtInGoalFit(exercise, goal);

/// The built-in goal heuristic above, without any admin value. Public so
/// the admin panel can show what an override replaces.
double builtInGoalFit(Exercise exercise, TrainingGoal goal) {
  final isCompound =
      exercise.movementPattern != MovementPattern.isolation &&
      exercise.movementPattern != MovementPattern.cardio;
  final isCardio = exercise.exerciseType == ExerciseType.cardio;

  switch (goal) {
    case TrainingGoal.getStronger:
      if (isCardio) return 0;
      if (isCompound && exercise.exerciseType == ExerciseType.freeWeight) {
        return 1;
      }
      return isCompound ? 0.7 : 0.3;
    case TrainingGoal.buildMuscle:
    case TrainingGoal.improveBodyComposition:
      if (isCardio) return 0.3;
      return isCompound ? 0.9 : 0.7;
    case TrainingGoal.loseFat:
      if (isCardio) return 1;
      return isCompound ? 0.8 : 0.5;
    case TrainingGoal.improveAthleticPerformance:
      if (isCardio) return 0.7;
      return isCompound ? 1 : 0.4;
  }
}

/// How well an exercise's own experience level matches the user's.
/// Exactly matched scores highest; easier than the user is still fine.
double _experienceFit(ExperienceLevel exercise, ExperienceLevel user) {
  final gap = user.index - exercise.index;
  if (gap == 0) return 1;
  if (gap > 0) return 0.7; // easier than they need: still usable
  return 0; // harder: rejected before this point, kept for clarity
}

/// How suitable the technical demand is. A beginner is pushed toward simpler
/// work without it being forbidden; an advanced lifter is not pushed toward
/// trivial work.
///
/// IMPLEMENTATION HEURISTIC.
double _complexityFit(Complexity complexity, ExperienceLevel user) {
  switch (user) {
    case ExperienceLevel.beginner:
      return switch (complexity) {
        Complexity.low => 1,
        Complexity.moderate => 0.5,
        Complexity.high => 0.1,
      };
    case ExperienceLevel.intermediate:
      return switch (complexity) {
        Complexity.low => 0.8,
        Complexity.moderate => 1,
        Complexity.high => 0.6,
      };
    case ExperienceLevel.advanced:
      return switch (complexity) {
        Complexity.low => 0.6,
        Complexity.moderate => 0.9,
        Complexity.high => 1,
      };
  }
}

/// Scores exercises against one person's setup. Pure and deterministic: the
/// same inputs always produce the same numbers and the same order.
class ExerciseScorer {
  const ExerciseScorer({
    required this.setup,
    required this.experience,
    this.priorityMuscles = const [],
    this.sessionMuscles = const [],
    this.measurement,
    this.thresholds = ProportionThresholds.none,
    this.weights = RecommendationWeights.standard,
  });

  final ProgramSetup setup;
  final ExperienceLevel experience;

  /// Muscles the user singled out. They score higher, which pulls them
  /// toward the front of a session, but they never override eligibility and
  /// never crowd out pattern coverage entirely.
  final List<MuscleGroup> priorityMuscles;

  /// The muscles this particular session is for. Empty means the whole
  /// setup, which is how a full-body session is scored.
  final List<MuscleGroup> sessionMuscles;

  /// The most recent body scan, if there is one.
  final Measurement? measurement;

  final ProportionThresholds thresholds;
  final RecommendationWeights weights;

  /// The app's own defaults stand for "whatever the admin set": the
  /// standard weights become the admin's weights, and the participant
  /// cut-offs become those cut-offs with any the admin replaced. Anything
  /// else passed in (a test's own values) is used exactly as given.
  RecommendationWeights get _weights =>
      identical(weights, RecommendationWeights.standard)
      ? AppContent.weights
      : weights;
  ProportionThresholds get _thresholds =>
      identical(thresholds, ProportionThresholds.participants)
      ? AppContent.thresholds
      : thresholds;

  /// The muscles that count here: the session's own, or the whole setup
  /// when a session has not narrowed it.
  Set<MuscleGroup> get _wanted =>
      sessionMuscles.isEmpty ? setup.muscles.toSet() : sessionMuscles.toSet();
  Set<EquipmentItem> get _available => setup.equipment.toSet();

  /// Why [exercise] cannot be recommended, or null if it can.
  ///
  /// Eligibility only. How good a fit it is comes later, from the score.
  RejectionReason? reject(Exercise exercise) {
    // Needs only equipment the user has. "None" is available everywhere.
    final needs = exercise.equipment
        .where((item) => item != EquipmentItem.none)
        .toList();
    if (needs.any((item) => !_available.contains(item))) {
      return RejectionReason.equipment;
    }
    // Admin-added equipment, the same way.
    if (exercise.extraEquipment.any(
      (id) => !setup.extraEquipment.contains(id),
    )) {
      return RejectionReason.equipment;
    }

    // Trains at least one muscle the user asked for, primary or secondary.
    final trains = {...exercise.primaryMuscles, ...exercise.secondaryMuscles};
    if (!trains.any(_wanted.contains)) return RejectionReason.muscles;

    // Never ask for more experience than the user has.
    if (exercise.experienceLevel.index > experience.index) {
      return RejectionReason.experience;
    }

    // A beginner is not given the most technically demanding work, even when
    // the exercise's own level allows it. IMPLEMENTATION HEURISTIC.
    if (experience == ExperienceLevel.beginner &&
        exercise.complexity == Complexity.high) {
      return RejectionReason.complexity;
    }

    return null;
  }

  /// Scores one eligible exercise.
  ///
  /// [coveredPatterns] are the movement patterns the workout already has, so
  /// a pattern that is still missing is worth more.
  ScoredExercise score(
    Exercise exercise, {
    Set<MovementPattern> coveredPatterns = const {},
  }) {
    final reasons = <String>[];
    var total = 0.0;

    // Goal.
    final goal = _goalFit(exercise, setup.goal);
    total += goal * _weights.goalRelevance;
    if (goal >= 0.8) {
      reasons.add('matches your goal to ${setup.goal.label.toLowerCase()}');
    }

    // Muscles. Primary counts for much more than secondary.
    final primaryHits = exercise.primaryMuscles
        .where(_wanted.contains)
        .toList();
    final secondaryHits = exercise.secondaryMuscles
        .where(_wanted.contains)
        .toList();
    total += primaryHits.length * _weights.primaryMuscleMatch;
    total += secondaryHits.length * _weights.secondaryMuscleMatch;
    if (primaryHits.isNotEmpty) {
      reasons.add('trains ${primaryHits.map((m) => m.label).join(' and ')}');
    }

    // Movement-pattern coverage.
    final pattern = exercise.movementPattern;
    final isNewPattern =
        pattern != MovementPattern.isolation &&
        pattern != MovementPattern.cardio &&
        !coveredPatterns.contains(pattern);
    if (isNewPattern) {
      total += _weights.patternCoverage;
      reasons.add('adds ${pattern.label.toLowerCase()} work');
    }

    // Equipment: eligible means it fits, so this is a flat reward.
    total += _weights.equipmentFit;

    // Experience and complexity.
    final experienceFit = _experienceFit(exercise.experienceLevel, experience);
    final complexityFit = _complexityFit(exercise.complexity, experience);
    total += experienceFit * _weights.experienceFit;
    total += complexityFit * _weights.complexityFit;
    if (experienceFit >= 1 && complexityFit >= 0.8) {
      reasons.add('suits your experience');
    }

    // Muscles the user singled out.
    final priorityHits = exercise.primaryMuscles
        .where(priorityMuscles.contains)
        .toList();
    total += priorityHits.length * _weights.priorityMuscleMatch;
    if (priorityHits.isNotEmpty) {
      reasons.add('is one of the muscles you singled out');
    }

    // Proportions, last and smallest. Nothing happens without thresholds.
    final advice = adviseFor(
      exercise,
      measurement: measurement,
      thresholds: _thresholds,
    );
    total += advice.scoreDelta * _weights.proportionFit;
    if (advice.reason != null) reasons.add(advice.reason!);

    return ScoredExercise(
      exercise: exercise,
      score: total,
      reasons: reasons,
      setupCue: advice.cue,
    );
  }

  /// Every eligible exercise from [pool], best first.
  ///
  /// Ties break on the exercise id, so the order never depends on how the
  /// pool happened to be sorted.
  List<ScoredExercise> rank(
    List<Exercise> pool, {
    Set<MovementPattern> coveredPatterns = const {},
  }) {
    final scored = [
      for (final exercise in pool)
        if (reject(exercise) == null)
          score(exercise, coveredPatterns: coveredPatterns),
    ];
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.exercise.id.compareTo(b.exercise.id);
    });
    return scored;
  }
}
