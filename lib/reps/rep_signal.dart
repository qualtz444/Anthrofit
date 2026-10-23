import '../models/models.dart';
import 'pose_frame.dart';

/// The joint whose angle the camera follows to count an exercise's reps.
///
/// APP DESIGN RULE, NOT FROM A SOURCE: which joint moves most in each kind of
/// exercise is the app's own reading of the movement, and has not been
/// validated. Rep counts must be checked against manual counts before any
/// accuracy is claimed.
enum RepSignal {
  elbow(
    'elbow',
    'Turn sideways, so the phone sees your side, not your front',
    'your shoulder, elbow and hand',
    (PoseIndex.leftShoulder, PoseIndex.leftElbow, PoseIndex.leftWrist),
    (PoseIndex.rightShoulder, PoseIndex.rightElbow, PoseIndex.rightWrist),
    30,
    110,
    145,
  ),
  knee(
    'knee',
    'Turn sideways, so the phone sees your side, not your front',
    'your whole body, head to feet',
    (PoseIndex.leftHip, PoseIndex.leftKnee, PoseIndex.leftAnkle),
    (PoseIndex.rightHip, PoseIndex.rightKnee, PoseIndex.rightAnkle),
    30,
    135,
    150,
  ),
  hip(
    'hip',
    'Turn sideways, so the phone sees your side, not your front',
    'your whole body, head to feet',
    (PoseIndex.leftShoulder, PoseIndex.leftHip, PoseIndex.leftKnee),
    (PoseIndex.rightShoulder, PoseIndex.rightHip, PoseIndex.rightKnee),
    25,
    135,
    150,
  ),
  shoulder(
    'shoulder',
    'Face the phone, so it sees your front',
    'your hips, shoulders and both arms',
    (PoseIndex.leftHip, PoseIndex.leftShoulder, PoseIndex.leftElbow),
    (PoseIndex.rightHip, PoseIndex.rightShoulder, PoseIndex.rightElbow),
    30,
    55,
    90,
  ),
  ankle(
    'ankle',
    'Turn sideways, so the phone sees your side, not your front',
    'your knees, ankles and feet',
    (PoseIndex.leftKnee, PoseIndex.leftAnkle, PoseIndex.leftFootIndex),
    (PoseIndex.rightKnee, PoseIndex.rightAnkle, PoseIndex.rightFootIndex),
    15,
    75,
    100,
  );

  const RepSignal(
    this.joint,
    this.facing,
    this.inFrame,
    this.left,
    this.right,
    this.minRangeDegrees,
    this.maxFlexedAngle,
    this.minExtendedAngle,
  );

  final String joint;

  /// Which way to stand relative to the phone. App guidance, to be checked
  /// in testing.
  final String facing;

  /// What must be on screen: the three points the angle is measured from,
  /// in plain words.
  final String inFrame;

  /// One line for the camera screen.
  String get placement => '$facing. Keep $inFrame on screen.';

  /// Landmark indices (end, joint, end) for each side.
  final (int, int, int) left;
  final (int, int, int) right;

  /// The joint has to move at least this much before anything is counted,
  /// so jittery landmarks and small fidgets are not reps. Set well below a
  /// real rep's travel for each joint (a calf raise moves the ankle far less
  /// than a squat moves the knee). APP PARAMETERS, NOT FROM A SOURCE: to be
  /// tuned against hand-counted sets.
  final double minRangeDegrees;

  /// An endpoint pair beyond the minimum range is required before arming.
  /// These broad joint-specific limits reject short, self-calibrated fidgets;
  /// they are app starting values, not clinically or empirically validated.
  final double maxFlexedAngle;
  final double minExtendedAngle;

  /// The joint angle on one side, or null when the pose is missing or any of
  /// the three points is less visible than [minVisibility].
  double? angle(
    PoseFrame frame, {
    required bool leftSide,
    double minVisibility = 0.7,
  }) {
    if (!frame.hasPose) return null;
    final (a, b, c) = leftSide ? left : right;
    final p = frame.landmarks;
    if (!p[a].isValid ||
        !p[b].isValid ||
        !p[c].isValid ||
        p[a].visibility < minVisibility ||
        p[b].visibility < minVisibility ||
        p[c].visibility < minVisibility) {
      return null;
    }
    return jointAngle(p[a], p[b], p[c]);
  }
}

/// Which joint to follow for [exercise], or null when the camera cannot
/// count it (cardio, timed work, and exercises with no joint that clearly
/// bends, such as shrugs).
///
/// APP DESIGN RULE, NOT FROM A SOURCE (see [RepSignal]):
///   squat-type (knee dominant)                knee
///   hinge-type (hip dominant)                 hip
///   pushes and pulls                          elbow
///   isolation, by the first primary muscle:
///     biceps, triceps, forearms, upper back   elbow
///     quads, hamstrings                       knee
///     glutes, core, lower back                hip
///     delts, chest, lats                      shoulder
///     calves                                  ankle
///     traps                                   not counted
RepSignal? repSignalFor(Exercise exercise) {
  if (exercise.exerciseType == ExerciseType.cardio) return null;
  switch (exercise.movementPattern) {
    case MovementPattern.cardio:
      return null;
    case MovementPattern.kneeDominant:
      return RepSignal.knee;
    case MovementPattern.hipDominant:
      return RepSignal.hip;
    case MovementPattern.horizontalPush:
    case MovementPattern.verticalPush:
    case MovementPattern.horizontalPull:
    case MovementPattern.verticalPull:
      return RepSignal.elbow;
    case MovementPattern.isolation:
      if (exercise.primaryMuscles.isEmpty) return null;
      return switch (exercise.primaryMuscles.first) {
        MuscleGroup.biceps ||
        MuscleGroup.triceps ||
        MuscleGroup.forearms ||
        MuscleGroup.upperBack => RepSignal.elbow,
        MuscleGroup.quads || MuscleGroup.hamstrings => RepSignal.knee,
        MuscleGroup.glutes ||
        MuscleGroup.core ||
        MuscleGroup.lowerBack => RepSignal.hip,
        MuscleGroup.frontDelts ||
        MuscleGroup.sideDelts ||
        MuscleGroup.rearDelts ||
        MuscleGroup.chest ||
        MuscleGroup.lats => RepSignal.shoulder,
        MuscleGroup.calves => RepSignal.ankle,
        MuscleGroup.traps => null,
      };
  }
}
