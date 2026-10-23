import '../models/models.dart';
import '../recommendation/prescription_rules.dart';

/// Why the sets, reps and rest look the way they do, in plain words, from
/// the ACSM (2009) progression models the app prescribes with. General to
/// the program type: if the user edited the numbers, theirs are what count.
///
/// Nothing here describes the user's technique: the app cannot see it, and
/// the body-proportion scan is not a form checker.
String prescriptionRationale(TrainingGoal goal, Exercise exercise) {
  final isolation = exercise.movementPattern == MovementPattern.isolation;
  if (exercise.exerciseType == ExerciseType.cardio) {
    return 'Cardio is one steady bout. Its length is set by the app.';
  }
  final body = switch (acsmProgramFor(goal)) {
    AcsmProgram.strength =>
      'Your goal uses the strength model: 8–12 reps for beginners and '
          'intermediates (1–6 when advanced), resting '
          '${isolation ? '1–2 min on an isolation exercise like this' : '2–3 min on a main lift like this'} '
          'so each set can be repeated with the same load.',
    AcsmProgram.hypertrophy =>
      'Your goal uses the muscle-building model: 8–12 reps (6–12 when advanced) '
          'with 1–2 min rest.',
    AcsmProgram.power =>
      'Your goal uses the power model: 3–6 reps done fast with control, '
          'resting '
          '${isolation ? '1–2 min' : '2–3 min'} so every set stays explosive.',
  };
  return '$body Three sets is the app\'s choice. If you change these numbers, '
      'the app tracks yours.';
}

/// The note saved with a recommended exercise: why it was picked, and the
/// setup tip from your proportions when there is one.
String recommendationNote(String explanation, String? setupCue) =>
    setupCue == null || setupCue.isEmpty
    ? explanation
    : '$explanation\nSetup tip: $setupCue';
