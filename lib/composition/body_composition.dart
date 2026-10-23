import 'dart:math' as math;

import '../core/input_limits.dart';
import 'composition_models.dart';
import 'silhouette_features.dart';

/// Who is being measured. Every field is required: the models were trained
/// with all of them, and none can be guessed.
class CompositionInput {
  const CompositionInput({
    required this.heightCm,
    required this.weightKg,
    required this.age,
    required this.isMale,
  });

  final double heightCm;
  final double weightKg;
  final int age;
  final bool isMale;

  /// The models' own encoding: male 1, female 0.
  int get sexCode => isMale ? 1 : 0;

  /// The ages the models were trained on (adults 18-59). Outside this range
  /// the numbers are an extrapolation, not an estimate.
  static const int minAge = 18;
  static const int maxAge = 59;

  bool get isInTrainingRange => age >= minAge && age <= maxAge;

  /// Why these inputs cannot be used, or null when they can.
  /// Height and weight limits are app-defined sanity checks
  /// (see input_limits.dart), not limits of the models.
  String? get problem {
    if (!heightCm.isFinite ||
        heightCm < kMinHeightCm ||
        heightCm > kMaxHeightCm) {
      return 'Height must be between ${kMinHeightCm.round()} and '
          '${kMaxHeightCm.round()} cm.';
    }
    if (!weightKg.isFinite ||
        weightKg < kMinWeightKg ||
        weightKg > kMaxWeightKg) {
      return 'Weight must be between ${kMinWeightKg.round()} and '
          '${kMaxWeightKg.round()} kg.';
    }
    if (age < minAge) return 'Body composition is estimated for adults only.';
    return null;
  }
}

/// A body-composition estimate with its 80% interval.
class CompositionEstimate {
  const CompositionEstimate({
    required this.value,
    required this.low,
    required this.high,
    required this.mae,
    required this.coverage80,
  });

  final double value;
  final double low;
  final double high;

  /// The model's mean absolute error on held-out DXA scans.
  final double mae;
  final double coverage80;
}

/// Circumferences read from the silhouette, in centimetres.
class SilhouetteMeasurements {
  const SilhouetteMeasurements({
    required this.waist,
    required this.bicep,
    required this.hip,
    required this.chest,
    required this.thigh,
  });

  final double waist;
  final double bicep;
  final double hip;
  final double chest;
  final double thigh;
}

class BodyCompositionResult {
  const BodyCompositionResult({
    required this.measurements,
    required this.bodyFatPct,
    required this.appendicularLeanKg,
    required this.fatMassKg,
    required this.fatFreeMassKg,
    required this.frameCount,
    required this.waistSpreadCm,
  });

  final SilhouetteMeasurements measurements;

  /// Body fat, percent of body weight.
  final CompositionEstimate bodyFatPct;

  /// Lean mass of the arms and legs (appendicular lean mass), kg.
  final CompositionEstimate appendicularLeanKg;

  /// Weight × body-fat share. Derived from the point estimate only.
  final double fatMassKg;
  final double fatFreeMassKg;

  /// How many front/side pairs were combined.
  final int frameCount;

  /// Largest minus smallest waist across frames. A wide spread means the
  /// frames disagreed, so the result is less trustworthy.
  final double waistSpreadCm;
}

/// Raised when no silhouette could be read.
class CompositionException implements Exception {
  const CompositionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One decimal place, rounding halves up like JavaScript's Math.round so the
/// numbers match the reference implementation to the digit.
double _r1(double x) => ((x * 10) + 0.5).floorToDouble() / 10;

double _median(List<double> xs) {
  final s = [...xs]..sort();
  final m = s.length >> 1;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// The two-stage pipeline.
///
///   Stage 1  silhouettes + height/weight/sex  ->  five circumferences
///   Stage 2  waist + upper arm + profile      ->  body fat % and lean mass
///
/// Pure and synchronous: it never touches a camera, a file or the network.
class BodyCompositionPipeline {
  const BodyCompositionPipeline(this.models);

  final CompositionModels models;

  Map<String, double>? _measurePair(
    SilhouetteMask front,
    SilhouetteMask side,
    CompositionInput input,
  ) {
    final feats = silhouetteFeatures(
      front,
      side,
      heightCm: input.heightCm,
      weightKg: input.weightKg,
      sex: input.sexCode,
      featureNames: models.stage1Features,
    );
    if (feats == null) return null;
    return {
      for (final e in models.stage1.entries)
        e.key: e.value.predict(feats.vector),
    };
  }

  /// One front/side pair.
  BodyCompositionResult analyse(
    SilhouetteMask front,
    SilhouetteMask side,
    CompositionInput input,
  ) => analyseMany([(front: front, side: side)], input);

  /// Several pairs, each measured on its own and combined by the median, so
  /// one bad segmentation cannot drag the answer the way a mean would. Only
  /// random error shrinks; the model's systematic bias is not averaged away.
  BodyCompositionResult analyseMany(
    List<({SilhouetteMask front, SilhouetteMask side})> pairs,
    CompositionInput input,
  ) {
    final problem = input.problem;
    if (problem != null) throw CompositionException(problem);

    final perPair = <Map<String, double>>[];
    for (final p in pairs) {
      final m = _measurePair(p.front, p.side, input);
      if (m != null) perPair.add(m);
    }
    if (perPair.isEmpty) {
      throw const CompositionException(
        'Could not read the silhouette. Is the whole body in frame?',
      );
    }

    final combined = <String, double>{};
    final spread = <String, double>{};
    for (final name in perPair.first.keys) {
      final vals = [for (final m in perPair) m[name]!];
      combined[name] = _median(vals);
      spread[name] = _r1(vals.reduce(math.max) - vals.reduce(math.min));
    }
    return _compose(combined, input, perPair.length, spread['waist'] ?? 0);
  }

  /// Stage 2 features, rebuilt from measurements exactly as training did.
  List<double> _stage2Vector(CompositionInput i, double waist, double arm) {
    final h = i.heightCm;
    final w = i.weightKg;
    final v = <String, double>{
      'sex': i.sexCode.toDouble(),
      'age': i.age.toDouble(),
      'height_cm': h,
      'weight_kg': w,
      'bmi': w / math.pow(h / 100, 2),
      'waist_cm': waist,
      'arm_circ_cm': arm,
      'waist_to_height': waist / h,
      'waist_to_weight': waist / w,
      'arm_to_height': arm / h,
      'waist_to_arm': waist / arm,
      'ponderal_index': w / math.pow(h / 100, 3),
    };
    return [
      for (final n in models.stage2Features)
        v[n] ?? (throw StateError('model expects an unknown feature: $n')),
    ];
  }

  BodyCompositionResult _compose(
    Map<String, double> raw,
    CompositionInput input,
    int frames,
    double waistSpread,
  ) {
    // Stage 2 reads the ROUNDED measurements, as the reference does.
    final m = {for (final e in raw.entries) e.key: _r1(e.value)};
    final x2 = _stage2Vector(input, m['waist']!, m['bicep']!);

    CompositionEstimate estimate(String target) {
      final t = models.stage2[target]!;
      return CompositionEstimate(
        value: _r1(t.point.predict(x2)),
        low: _r1(t.lo.predict(x2) - t.q),
        high: _r1(t.hi.predict(x2) + t.q),
        mae: t.mae,
        coverage80: t.coverage80,
      );
    }

    final bodyFat = estimate('bodyfat_pct');
    final lean = estimate('alm_kg');

    return BodyCompositionResult(
      measurements: SilhouetteMeasurements(
        waist: m['waist']!,
        bicep: m['bicep']!,
        hip: m['hip']!,
        chest: m['chest']!,
        thigh: m['thigh']!,
      ),
      bodyFatPct: bodyFat,
      appendicularLeanKg: lean,
      fatMassKg: _r1(input.weightKg * bodyFat.value / 100),
      fatFreeMassKg: _r1(input.weightKg * (1 - bodyFat.value / 100)),
      frameCount: frames,
      waistSpreadCm: waistSpread,
    );
  }
}
