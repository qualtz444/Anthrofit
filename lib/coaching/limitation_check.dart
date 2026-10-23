import '../models/models.dart';

/// Which noted limitations an exercise loads, by its muscles and movement.
///
/// App design rule, not clinically validated: an area counts when the
/// exercise's primary or secondary muscles cross that joint, or its
/// movement pattern loads it. Whether an exercise actually suits an injured
/// area depends on the injury and the person, which the app cannot judge.
/// So an exercise that does NOT match is not thereby safe; it only loads
/// the area less directly by this rule.
List<LimitationArea> limitationsHit(
  Exercise exercise,
  List<LimitationArea> areas,
) {
  final muscles = {...exercise.primaryMuscles, ...exercise.secondaryMuscles};
  final pattern = exercise.movementPattern;
  bool any(Set<MuscleGroup> set) => muscles.any(set.contains);

  bool hits(LimitationArea area) => switch (area) {
    LimitationArea.shoulder =>
      any({
        MuscleGroup.frontDelts,
        MuscleGroup.sideDelts,
        MuscleGroup.rearDelts,
      }) ||
          pattern == MovementPattern.verticalPush,
    LimitationArea.lowerBack =>
      any({MuscleGroup.lowerBack}) || pattern == MovementPattern.hipDominant,
    LimitationArea.knee =>
      any({MuscleGroup.quads}) || pattern == MovementPattern.kneeDominant,
    LimitationArea.hip =>
      any({MuscleGroup.glutes}) ||
          pattern == MovementPattern.hipDominant ||
          pattern == MovementPattern.kneeDominant,
    LimitationArea.wristElbow => any({
      MuscleGroup.biceps,
      MuscleGroup.triceps,
      MuscleGroup.forearms,
    }),
  };

  return [for (final a in areas) if (hits(a)) a];
}

String _areaNames(List<LimitationArea> areas) =>
    areas.map((a) => a.label.toLowerCase()).join(', ');

/// Shown on an exercise that loads a noted area. It is flagged for review,
/// not presented as safe with care.
String? limitationCaution(Exercise exercise, List<LimitationArea> areas) {
  final hit = limitationsHit(exercise, areas);
  if (hit.isEmpty) return null;
  return 'Flagged for review: this exercise loads your ${_areaNames(hit)}, '
      'which you noted as injured or painful. Skip it until a doctor or '
      'physical therapist says it is OK.';
}

/// Shown with a program generated for someone with noted limitations.
String? limitationProgramNote(List<LimitationArea> areas) {
  if (areas.isEmpty) return null;
  return 'You noted: ${_areaNames(areas)}. Exercises that load these areas were '
      'left out where possible, and the rest are flagged for review. This is an '
      'app rule, not a clinical judgment, so check this program with a doctor '
      'or physical therapist.';
}

/// The exercise pool with exercises that load a noted area left out, when
/// another exercise in the pool trains the same primary muscle without
/// matching any noted area. Otherwise they stay and are flagged for review
/// (see [limitationCaution]). A conservative, transparent app rule.
List<Exercise> avoidLimitations(
  List<Exercise> pool,
  List<LimitationArea> areas,
) {
  if (areas.isEmpty) return pool;
  bool clear(Exercise e) => limitationsHit(e, areas).isEmpty;
  final clearMuscles = {
    for (final e in pool)
      if (clear(e)) ...e.primaryMuscles,
  };
  return [
    for (final e in pool)
      if (clear(e) || e.primaryMuscles.any((m) => !clearMuscles.contains(m)))
        e,
  ];
}
