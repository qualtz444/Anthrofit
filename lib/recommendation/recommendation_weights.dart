/// How much each factor counts when ranking exercises.
///
/// These are IMPLEMENTATION HEURISTICS, not validated findings. No published
/// source sets them. They are gathered here so they can be tuned in one place
/// and so a reader can see exactly what the ranking rewards.
class RecommendationWeights {
  const RecommendationWeights({
    this.goalRelevance = 20,
    this.primaryMuscleMatch = 30,
    this.secondaryMuscleMatch = 8,
    this.patternCoverage = 25,
    this.equipmentFit = 10,
    this.experienceFit = 15,
    this.complexityFit = 15,
    this.proportionFit = 10,
    this.priorityMuscleMatch = 20,
  });

  /// The exercise suits what the program is for (strength, muscle, and so on).
  final double goalRelevance;

  /// Per selected muscle the exercise trains as a primary mover.
  final double primaryMuscleMatch;

  /// Per selected muscle it trains as a secondary mover.
  final double secondaryMuscleMatch;

  /// It covers a movement pattern the workout does not have yet.
  final double patternCoverage;

  /// It needs nothing beyond the equipment the user has.
  final double equipmentFit;

  /// Its stated experience level suits the user's.
  final double experienceFit;

  /// How technically demanding it is, against the user's experience.
  final double complexityFit;

  /// The most a proportion rule can move a score, up or down. Deliberately
  /// the smallest weight: proportions nudge the order, they never decide it.
  final double proportionFit;

  /// Per muscle the user singled out that the exercise trains as a primary.
  /// Large enough to pull priority work toward the front of a session,
  /// small enough that pattern coverage still breaks up a run of them.
  final double priorityMuscleMatch;

  static const RecommendationWeights standard = RecommendationWeights();

  /// Every weight by name, in the order the admin panel lists them.
  Map<String, double> toJson() => {
    'goalRelevance': goalRelevance,
    'primaryMuscleMatch': primaryMuscleMatch,
    'secondaryMuscleMatch': secondaryMuscleMatch,
    'patternCoverage': patternCoverage,
    'equipmentFit': equipmentFit,
    'experienceFit': experienceFit,
    'complexityFit': complexityFit,
    'proportionFit': proportionFit,
    'priorityMuscleMatch': priorityMuscleMatch,
  };

  /// Reads weights saved by the admin panel. A missing or negative value
  /// keeps the built-in one.
  factory RecommendationWeights.fromJson(Map<String, dynamic> json) {
    const d = standard;
    double read(String key, double fallback) {
      final raw = json[key];
      return raw is num && raw >= 0 ? raw.toDouble() : fallback;
    }

    return RecommendationWeights(
      goalRelevance: read('goalRelevance', d.goalRelevance),
      primaryMuscleMatch: read('primaryMuscleMatch', d.primaryMuscleMatch),
      secondaryMuscleMatch: read(
        'secondaryMuscleMatch',
        d.secondaryMuscleMatch,
      ),
      patternCoverage: read('patternCoverage', d.patternCoverage),
      equipmentFit: read('equipmentFit', d.equipmentFit),
      experienceFit: read('experienceFit', d.experienceFit),
      complexityFit: read('complexityFit', d.complexityFit),
      proportionFit: read('proportionFit', d.proportionFit),
      priorityMuscleMatch: read('priorityMuscleMatch', d.priorityMuscleMatch),
    );
  }
}
