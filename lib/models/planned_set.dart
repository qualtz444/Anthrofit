import '../core/json_utils.dart';
import 'enums.dart';

/// How ONE set of a planned exercise is prescribed.
/// Order = position in PlannedExercise.plannedSets (no stored set number).
///
/// Target reps are a range: [targetRepMin]..[targetRepMax]. One number means
/// min == max. Both null = no rep target, which is normal for a Failure set and
/// is shown as "To Failure". No numbers are invented for it.
/// [targetLoadKg] null = no target load. It is never filled in automatically.
class PlannedSet {
  const PlannedSet({
    required this.setType,
    this.targetRepMin,
    this.targetRepMax,
    this.targetLoadKg,
    this.targetDurationSeconds,
    required this.restSeconds,
  });

  /// The starting prescription for a new Working set. A default, not advice.
  static const int defaultRepMin = 8;
  static const int defaultRepMax = 12;
  static const int defaultRestSeconds = 90;

  /// How many sets a newly added exercise starts with.
  static const int defaultSetCount = 3;

  factory PlannedSet.defaultWorking() => const PlannedSet(
    setType: SetType.working,
    targetRepMin: defaultRepMin,
    targetRepMax: defaultRepMax,
    restSeconds: defaultRestSeconds,
  );

  final SetType setType;
  final int? targetRepMin;
  final int? targetRepMax;
  final double? targetLoadKg;

  /// How long the set should last, for cardio. A treadmill set is prescribed
  /// in time, not reps, so a set has one target or the other, never both.
  final int? targetDurationSeconds;

  final int restSeconds;

  /// A copy with some fields changed. Null means "leave alone", so a target
  /// cannot be cleared this way; build a new PlannedSet for that.
  PlannedSet copyWith({
    SetType? setType,
    int? targetRepMin,
    int? targetRepMax,
    double? targetLoadKg,
    int? targetDurationSeconds,
    int? restSeconds,
  }) {
    return PlannedSet(
      setType: setType ?? this.setType,
      targetRepMin: targetRepMin ?? this.targetRepMin,
      targetRepMax: targetRepMax ?? this.targetRepMax,
      targetLoadKg: targetLoadKg ?? this.targetLoadKg,
      targetDurationSeconds:
          targetDurationSeconds ?? this.targetDurationSeconds,
      restSeconds: restSeconds ?? this.restSeconds,
    );
  }

  /// True for a set prescribed as time rather than reps.
  bool get hasDurationTarget =>
      targetDurationSeconds != null && targetDurationSeconds! > 0;

  bool get hasRepTarget => targetRepMin != null;

  /// "8–12", "10", or null when there is no rep target.
  String? get repRangeLabel {
    final min = targetRepMin;
    if (min == null) return null;
    final max = targetRepMax ?? min;
    return min == max ? '$min' : '$min–$max';
  }

  Map<String, dynamic> toJson() => {
    'setType': setType.name,
    'targetRepMin': targetRepMin,
    'targetRepMax': targetRepMax,
    'targetLoadKg': targetLoadKg,
    'targetDurationSeconds': targetDurationSeconds,
    'restSeconds': restSeconds,
  };

  /// Missing or odd values fall back safely: unknown type -> Working,
  /// bad reps -> no rep target, bad load -> no target load, no rest -> default.
  factory PlannedSet.fromJson(Map<String, dynamic> json) {
    final rawMin = parseNullableInt(json['targetRepMin']);
    final int? min = (rawMin != null && rawMin >= 1) ? rawMin : null;
    final rawMax = parseNullableInt(json['targetRepMax']);
    final load = parseNullableDouble(json['targetLoadKg']);
    final rest = json['restSeconds'];

    return PlannedSet(
      setType: enumByName(SetType.values, json['setType'], SetType.working),
      targetRepMin: min,
      targetRepMax: min == null
          ? null
          : (rawMax != null && rawMax >= min ? rawMax : min),
      targetLoadKg: load != null && load.isFinite && load > 0 ? load : null,
      targetDurationSeconds: () {
        final seconds = parseNullableInt(json['targetDurationSeconds']);
        return seconds != null && seconds > 0 ? seconds : null;
      }(),
      restSeconds: rest is num && rest >= 0 ? rest.toInt() : defaultRestSeconds,
    );
  }
}
