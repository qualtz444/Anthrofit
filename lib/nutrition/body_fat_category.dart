import '../models/models.dart';

/// American Council on Exercise (ACE) body fat categories.
///
///                  Men      Women
///   Essential fat  2-5%     10-13%
///   Athletes       6-13%    14-20%
///   Fitness        14-17%   21-24%
///   Average        18-24%   25-31%
///   Obese          25%+     32%+
///
/// The published bands are whole numbers with gaps between them (13 and 14,
/// say). A value in a gap is read as the lower band: each band starts at its
/// published lower bound. ACE calls these generic estimates.
enum BodyFatCategory {
  essential('Essential fat'),
  athletes('Athletes'),
  fitness('Fitness'),
  average('Average'),
  obese('Obese');

  const BodyFatCategory(this.label);
  final String label;
}

BodyFatCategory bodyFatCategory(double bodyFatPct, {required bool isMale}) {
  // Lower bounds of Athletes, Fitness, Average and Obese.
  final bounds = isMale ? const [6.0, 14.0, 18.0, 25.0] : const [14.0, 21.0, 25.0, 32.0];
  if (bodyFatPct >= bounds[3]) return BodyFatCategory.obese;
  if (bodyFatPct >= bounds[2]) return BodyFatCategory.average;
  if (bodyFatPct >= bounds[1]) return BodyFatCategory.fitness;
  if (bodyFatPct >= bounds[0]) return BodyFatCategory.athletes;
  return BodyFatCategory.essential;
}

/// The goal suggested for a body fat category.
///
/// This mapping is the APP'S OWN rule, not part of the ACE chart:
///   Obese              -> Lose fat
///   Average            -> Improve body composition
///   Fitness, Athletes  -> Build muscle
///   Essential fat      -> Build muscle (losing more is not advised)
/// It is a suggestion; the user confirms before anything changes.
TrainingGoal suggestedGoalFor(BodyFatCategory category) => switch (category) {
  BodyFatCategory.obese => TrainingGoal.loseFat,
  BodyFatCategory.average => TrainingGoal.improveBodyComposition,
  BodyFatCategory.fitness ||
  BodyFatCategory.athletes ||
  BodyFatCategory.essential => TrainingGoal.buildMuscle,
};
