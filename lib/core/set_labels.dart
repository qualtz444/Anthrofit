import '../models/models.dart';
import 'format.dart';
import 'units.dart';

// Text for planned sets. One place, so Workout Detail, Exercise Detail, the
// editor, the session and History all describe a set the same way.

/// "8–12 reps", "10 reps", "20:00" for a set prescribed as time, or
/// "To Failure" for a Failure set with no target.
String plannedRepsLabel(PlannedSet set) {
  if (set.hasDurationTarget) return formatClock(set.targetDurationSeconds!);
  final range = set.repRangeLabel;
  if (range != null) return '$range reps';
  return set.setType == SetType.failure ? 'To Failure' : 'No rep target';
}

/// "8–12 reps · 40 kg". The load is left out when there is no target load.
/// [units] only changes how the load reads; it is always stored in kilograms.
String plannedTargetLabel(PlannedSet set, [WeightUnit units = WeightUnit.kg]) {
  final load = set.targetLoadKg;
  return [
    plannedRepsLabel(set),
    if (load != null && load > 0) formatWeight(load, units),
  ].join(' · ');
}

/// "8–12 reps · 40 kg · Rest 90s"
String plannedSetDetails(PlannedSet set, [WeightUnit units = WeightUnit.kg]) =>
    '${plannedTargetLabel(set, units)} · Rest ${set.restSeconds}s';

/// "3 sets", or "4 sets · 1 warm-up, 2 working, 1 failure" when there is more
/// than one kind of set.
String plannedSetsSummary(List<PlannedSet> sets) {
  final total = pluralize(sets.length, 'set');
  int count(SetType type) => sets.where((s) => s.setType == type).length;
  final warmUp = count(SetType.warmUp);
  final working = count(SetType.working);
  final failure = count(SetType.failure);
  if (warmUp == 0 && failure == 0) return total;
  final parts = [
    if (warmUp > 0) '$warmUp warm-up',
    if (working > 0) '$working working',
    if (failure > 0) '$failure failure',
  ];
  return '$total · ${parts.join(', ')}';
}
