import '../core/json_utils.dart';

/// One saved body composition estimate.
///
/// Kept with the profile (in [UserProfile.compositionLog]) so the numbers
/// sync the same way. It feeds the goal suggestion, the nutrition targets and
/// the body composition trends in Progress. Its outlines and photos are NOT
/// here: they stay on the phone (composition_visuals.dart).
class CompositionRecord {
  const CompositionRecord({
    required this.id,
    required this.takenAt,
    required this.weightKg,
    required this.bodyFatPct,
    required this.bodyFatLow,
    required this.bodyFatHigh,
    required this.leanLimbKg,
    required this.fatFreeMassKg,
    required this.fatMassKg,
    required this.waistCm,
    required this.chestCm,
    required this.hipCm,
    required this.thighCm,
    required this.upperArmCm,
    required this.frameCount,
  });

  /// Links the record to its outlines and photos, which are kept on this
  /// phone only (see composition_visuals.dart).
  final String id;

  final DateTime takenAt;

  /// The weight the estimate was worked out with.
  final double weightKg;

  /// Point estimate and its 80% range, percent of body weight.
  final double bodyFatPct;
  final double bodyFatLow;
  final double bodyFatHigh;

  /// Appendicular (arm and leg) lean mass.
  final double leanLimbKg;
  final double fatFreeMassKg;
  final double fatMassKg;

  final double waistCm;
  final double chestCm;
  final double hipCm;
  final double thighCm;
  final double upperArmCm;

  final int frameCount;

  Map<String, dynamic> toJson() => {
    'id': id,
    'takenAt': takenAt.toIso8601String(),
    'weightKg': weightKg,
    'bodyFatPct': bodyFatPct,
    'bodyFatLow': bodyFatLow,
    'bodyFatHigh': bodyFatHigh,
    'leanLimbKg': leanLimbKg,
    'fatFreeMassKg': fatFreeMassKg,
    'fatMassKg': fatMassKg,
    'waistCm': waistCm,
    'chestCm': chestCm,
    'hipCm': hipCm,
    'thighCm': thighCm,
    'upperArmCm': upperArmCm,
    'frameCount': frameCount,
  };

  factory CompositionRecord.fromJson(Map<String, dynamic> json) {
    final takenAt = parseDate(json['takenAt']) ?? DateTime(1970);
    return CompositionRecord(
        // Records from before ids existed are named by their time.
        id: parseString(json['id'], takenAt.toIso8601String()),
        takenAt: takenAt,
        weightKg: parseDouble(json['weightKg']),
        bodyFatPct: parseDouble(json['bodyFatPct']),
        bodyFatLow: parseDouble(json['bodyFatLow']),
        bodyFatHigh: parseDouble(json['bodyFatHigh']),
        leanLimbKg: parseDouble(json['leanLimbKg']),
        fatFreeMassKg: parseDouble(json['fatFreeMassKg']),
        fatMassKg: parseDouble(json['fatMassKg']),
        waistCm: parseDouble(json['waistCm']),
        chestCm: parseDouble(json['chestCm']),
        hipCm: parseDouble(json['hipCm']),
        thighCm: parseDouble(json['thighCm']),
        upperArmCm: parseDouble(json['upperArmCm']),
        frameCount: parseInt(json['frameCount']),
      );
  }
}
