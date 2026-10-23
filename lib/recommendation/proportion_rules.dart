import '../content/app_content.dart';
import '../models/models.dart';

// Body proportions and what, if anything, they change about an exercise.
//
// READ THIS BEFORE USING IT.
//
// There is no published reference for what counts as a long or short femur,
// arm or torso, and none is invented here. The cut-offs in use,
// [ProportionThresholds.participants], come from this project's own measured
// participants: a median split or the quartiles of that sample. They are a
// rule for this app, relative to that sample, not a medical or scientific
// cut-off, and they are reported as such.
//
// Without a threshold a ratio is classified [ProportionClass.unknown] and
// nothing changes: no score modifier, no cue, no variation.

/// Where one ratio sits relative to the thresholds in use.
enum ProportionClass {
  /// Below the lower threshold.
  low,

  /// Between the thresholds, or exactly on one.
  typical,

  /// Above the upper threshold.
  high,

  /// No threshold is configured, or the scan did not measure this ratio.
  /// Nothing is inferred from this.
  unknown,
}

/// One ratio's lower and upper cut-off.
class RatioThreshold {
  const RatioThreshold({required this.low, required this.high});

  /// At or below this is [ProportionClass.low].
  final double low;

  /// At or above this is [ProportionClass.high].
  final double high;
}

/// The cut-offs in use, keyed by the measurement pipeline's own ratio ids.
///
/// Empty by default, on purpose: see the note at the top of this file.
class ProportionThresholds {
  const ProportionThresholds([this.byRatio = const {}]);

  final Map<String, RatioThreshold> byRatio;

  /// No thresholds: every ratio classifies as unknown.
  static const ProportionThresholds none = ProportionThresholds();

  /// Cut-offs from this project's measured participants.
  ///
  ///   Femur : torso          0.720            median
  ///   Arm : torso            0.963            median
  ///   Upper body : stature   0.481 / 0.524    Q1 / Q3
  ///   Shoulder : hip         1.610 / 1.714    Q1 / Q3
  ///
  /// A median split is one cut-off used as both bounds: below it is low,
  /// above it is high. A value exactly on the median reads as low (APP
  /// CHOICE; the split itself does not say). With quartiles, Q1 and below is
  /// low, Q3 and above is high, and the band between is typical.
  ///
  /// The ratios must be computed exactly as the scan computes them
  /// (Measurement.kt), or these cut-offs do not apply.
  static const ProportionThresholds participants = ProportionThresholds({
    RatioKeys.femurToTorso: RatioThreshold(low: 0.720, high: 0.720),
    RatioKeys.armToTorso: RatioThreshold(low: 0.963, high: 0.963),
    RatioKeys.upperBodyToStature: RatioThreshold(low: 0.481, high: 0.524),
    RatioKeys.shoulderToHip: RatioThreshold(low: 1.610, high: 1.714),
  });

  bool get isEmpty => byRatio.isEmpty;

  ProportionClass classify(String ratioKey, Measurement? measurement) {
    final threshold = byRatio[ratioKey];
    final value = measurement?.ratios[ratioKey];
    if (threshold == null || value == null) return ProportionClass.unknown;
    if (value <= threshold.low) return ProportionClass.low;
    if (value >= threshold.high) return ProportionClass.high;
    return ProportionClass.typical;
  }
}

/// Ratio ids this file reasons about. They match the measurement pipeline.
class RatioKeys {
  const RatioKeys._();

  static const String femurToTorso = 'femur_torso_ratio';
  static const String armToTorso = 'arm_torso_ratio';
  static const String shoulderToHip = 'lm_shoulder_hip_ratio';
  static const String upperBodyToStature = 'upperbody_stature_ratio';
}

/// What a proportion rule says about one exercise.
class ProportionAdvice {
  const ProportionAdvice({
    required this.scoreDelta,
    required this.cue,
    required this.reason,
  });

  /// -1 to 1, scaled by the proportion weight. 0 means no opinion.
  final double scoreDelta;

  /// A setup cue to show with the exercise, or null.
  final String? cue;

  /// Why, in one phrase, for the explanation.
  final String? reason;

  static const ProportionAdvice none = ProportionAdvice(
    scoreDelta: 0,
    cue: null,
    reason: null,
  );
}

/// One rule: for exercises matching [appliesTo], what a given class of
/// [ratioKey] means.
///
/// Rules are deliberately narrow. An exercise no rule matches gets
/// [ProportionAdvice.none], which is the normal case.
class ProportionRule {
  const ProportionRule({
    required this.name,
    required this.ratioKey,
    required this.appliesTo,
    required this.advice,
  });

  final String name;
  final String ratioKey;

  /// True when this rule has anything to say about [exercise].
  final bool Function(Exercise exercise) appliesTo;

  /// The advice for each class. A class left out means no opinion.
  final Map<ProportionClass, ProportionAdvice> advice;
}

/// The rules in use.
///
/// Each one is a practical setup observation, not a finding: a longer femur
/// relative to the trunk tends to make a deep upright barbell squat harder to
/// hold, so a more accommodating variation is ranked slightly higher and a
/// setup cue is offered. The direction is a coaching convention; the size of
/// the nudge is arbitrary and small by design.
final List<ProportionRule> kProportionRules = [
  ProportionRule(
    name: 'Long femur, barbell squat',
    ratioKey: RatioKeys.femurToTorso,
    appliesTo: (e) =>
        e.movementPattern == MovementPattern.kneeDominant &&
        e.equipment.contains(EquipmentItem.barbell),
    advice: const {
      ProportionClass.high: ProportionAdvice(
        scoreDelta: -0.5,
        cue:
            'With a longer thigh relative to your trunk, a barbell squat '
            'often needs more forward lean. A slightly wider stance, or '
            'heeled shoes, usually helps.',
        reason:
            'a barbell squat is harder to keep upright with your '
            'proportions',
      ),
    },
  ),
  ProportionRule(
    name: 'Long femur, supported knee-dominant work',
    ratioKey: RatioKeys.femurToTorso,
    appliesTo: (e) =>
        e.movementPattern == MovementPattern.kneeDominant &&
        (e.exerciseType == ExerciseType.machine ||
            e.equipment.contains(EquipmentItem.dumbbell)),
    advice: const {
      ProportionClass.high: ProportionAdvice(
        scoreDelta: 1,
        cue:
            'A supported or counterbalanced squat pattern suits a longer '
            'thigh: you can sit down between your knees without leaning far '
            'forward.',
        reason: 'it accommodates your longer thigh',
      ),
    },
  ),
  ProportionRule(
    name: 'Long arms, barbell bench press',
    ratioKey: RatioKeys.armToTorso,
    appliesTo: (e) =>
        e.movementPattern == MovementPattern.horizontalPush &&
        e.equipment.contains(EquipmentItem.barbell),
    advice: const {
      ProportionClass.high: ProportionAdvice(
        scoreDelta: -0.3,
        cue:
            'Longer arms mean a longer path on a barbell bench press. A '
            'slightly wider grip shortens it.',
        reason: 'a barbell press has a longer range for your arm length',
      ),
    },
  ),
  ProportionRule(
    name: 'Long arms, deadlift-style hinge',
    ratioKey: RatioKeys.armToTorso,
    appliesTo: (e) =>
        e.movementPattern == MovementPattern.hipDominant &&
        e.equipment.contains(EquipmentItem.barbell),
    advice: const {
      ProportionClass.high: ProportionAdvice(
        scoreDelta: 0.5,
        cue: 'Longer arms shorten how far the bar has to travel on a hinge.',
        reason: 'your arm length suits a barbell hinge',
      ),
    },
  ),
];

/// What every applicable rule says about [exercise], combined.
///
/// With no thresholds configured, or a scan that did not measure the ratio,
/// this is always [ProportionAdvice.none].
ProportionAdvice adviseFor(
  Exercise exercise, {
  required Measurement? measurement,
  required ProportionThresholds thresholds,
}) {
  if (thresholds.isEmpty || measurement == null) return ProportionAdvice.none;

  var delta = 0.0;
  final cues = <String>[];
  final reasons = <String>[];

  // The built-in rules, minus any the admin switched off, plus the admin's.
  for (final rule in AppContent.proportionRules) {
    if (!rule.appliesTo(exercise)) continue;
    final advice = rule.advice[thresholds.classify(rule.ratioKey, measurement)];
    if (advice == null) continue;
    delta += advice.scoreDelta;
    if (advice.cue != null) cues.add(advice.cue!);
    if (advice.reason != null) reasons.add(advice.reason!);
  }

  if (cues.isEmpty && delta == 0) return ProportionAdvice.none;
  return ProportionAdvice(
    scoreDelta: delta.clamp(-1.0, 1.0),
    cue: cues.isEmpty ? null : cues.join(' '),
    reason: reasons.isEmpty ? null : reasons.first,
  );
}
