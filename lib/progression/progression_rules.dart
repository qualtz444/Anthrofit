/// How much to change a load, and when.
///
/// IMPLEMENTATION HEURISTICS. "Add about 2.5% when every set hits the top of
/// the range" is a common gym convention, not a validated rule. Every number
/// is here so it can be changed in one place and reported as an app rule.
class ProgressionRules {
  const ProgressionRules({
    this.increasePercent = 2.5,
    this.decreasePercent = 10,
    this.minIncrementKg = 2.5,
    this.roundToKg = 2.5,
    this.regressionTolerance = 2,
  });

  /// Added when every set reached the top of the rep range.
  final double increasePercent;

  /// Taken off after a clear drop in performance.
  final double decreasePercent;

  /// The smallest change worth making, so a light load still moves.
  final double minIncrementKg;

  /// Loads are rounded to this, matching the plates most gyms have.
  final double roundToKg;

  /// How many reps below the target minimum still counts as holding steady
  /// rather than regressing.
  final int regressionTolerance;

  static const ProgressionRules standard = ProgressionRules();

  /// Rounds [kg] to the nearest usable load, never below the increment.
  double round(double kg) {
    if (kg <= 0) return 0;
    final rounded = (kg / roundToKg).round() * roundToKg;
    return rounded < roundToKg ? roundToKg : rounded;
  }
}
