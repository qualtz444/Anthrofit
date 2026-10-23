import '../data/exercise_library.dart';
import '../data/training_stats.dart';
import '../models/models.dart';

// Muscle Training: "am I training my muscles consistently and evenly?"
//
// This is TRAINING EXPOSURE, derived from which exercises were completed and
// what the catalogue says they train. It is not muscle activation: nothing
// here measures what a muscle did, only which muscles the work was aimed at.
//
// Counting rules, applied the same way everywhere:
//   - Only completed work sets count: warm-ups and skipped sets do not.
//   - Each set counts once for each PRIMARY muscle of its exercise, and once
//     for each SECONDARY muscle, kept in separate totals. Nothing is split
//     into fractions, which would suggest a precision the data lacks.
//   - Cardio is left out: a treadmill set is not a set of quad work.
//   - An exercise no longer in the catalogue is left out, since its muscles
//     are unknown. Its sets still count toward strength.

/// One completed work set, tied to the muscles its exercise trains.
///
/// The record everything else is computed from. Kept at this level, rather
/// than as weekly totals, so any window can be recalculated later without
/// losing anything, which is what an AI layer would need.
class MuscleSetRecord {
  const MuscleSetRecord({
    required this.sessionId,
    required this.date,
    required this.exerciseId,
    required this.primary,
    required this.secondary,
    required this.volumeKg,
  });

  final String sessionId;
  final DateTime date;
  final String exerciseId;
  final List<MuscleGroup> primary;
  final List<MuscleGroup> secondary;

  /// Weight × reps, or 0 when no weight was logged.
  final double volumeKg;
}

/// Every completed work set as a [MuscleSetRecord], oldest first.
List<MuscleSetRecord> muscleSetRecords(List<WorkoutSession> sessions) {
  final records = <MuscleSetRecord>[];
  for (final session in oldestFirst(sessions)) {
    if (!session.isCompleted) continue;
    final date = sessionDate(session);
    for (final log in session.exerciseLogs) {
      final exercise = ExerciseLibrary.byId(log.exerciseId);
      if (exercise == null || exercise.exerciseType == ExerciseType.cardio) {
        continue;
      }
      for (final set in workSetsOf(log)) {
        records.add(
          MuscleSetRecord(
            sessionId: session.id,
            date: date,
            exerciseId: log.exerciseId,
            primary: exercise.primaryMuscles,
            secondary: exercise.secondaryMuscles,
            volumeKg: isWeightedSet(set) ? set.weightKg! * (set.reps ?? 0) : 0,
          ),
        );
      }
    }
  }
  return records;
}

/// How much a muscle was trained in a window, relative to the user's OWN
/// training in that window.
///
/// IMPLEMENTATION HEURISTIC. There is no standard here: it compares each
/// muscle with the most-trained muscle, so "High" means "near the top of
/// what you trained", never "enough". A muscle trained at all is at least
/// Low; one not trained is not listed.
enum ExposureLevel {
  low('Low'),
  moderate('Moderate'),
  high('High');

  const ExposureLevel(this.label);
  final String label;
}

/// Exposure for one muscle in one window.
class MuscleExposure {
  const MuscleExposure({
    required this.muscle,
    required this.sessions,
    required this.primarySets,
    required this.secondarySets,
    required this.volumeKg,
    required this.lastTrained,
    required this.level,
  });

  final MuscleGroup muscle;

  /// Workouts where it was a primary OR secondary target.
  final int sessions;

  final int primarySets;
  final int secondarySets;

  /// Weight × reps over its primary sets, weighted sets only.
  final double volumeKg;

  final DateTime lastTrained;
  final ExposureLevel level;

  int get totalSets => primarySets + secondarySets;
}

/// The cut-offs for [ExposureLevel], as a share of the busiest muscle's
/// primary sets. In one place so they can be changed.
const double kHighExposureShare = 2 / 3;
const double kModerateExposureShare = 1 / 3;

ExposureLevel _levelFor(int primarySets, int busiest) {
  if (busiest <= 0) return ExposureLevel.low;
  final share = primarySets / busiest;
  if (share >= kHighExposureShare) return ExposureLevel.high;
  if (share >= kModerateExposureShare) return ExposureLevel.moderate;
  return ExposureLevel.low;
}

/// Exposure for every muscle trained in [range], most primary sets first,
/// ties broken by [MuscleGroup] order so the list never reshuffles.
///
/// Empty when nothing was trained. Untrained muscles are NOT listed as zero:
/// a row of zeroes would read like data.
List<MuscleExposure> muscleExposure(
  List<WorkoutSession> sessions,
  ProgressRange range,
  DateTime today,
) {
  final records = muscleSetRecords(
    sessions,
  ).where((r) => isInRange(r.date, range, today)).toList();
  if (records.isEmpty) return const [];

  final primarySets = <MuscleGroup, int>{};
  final secondarySets = <MuscleGroup, int>{};
  final volume = <MuscleGroup, double>{};
  final sessionIds = <MuscleGroup, Set<String>>{};
  final last = <MuscleGroup, DateTime>{};

  void touch(MuscleGroup m, MuscleSetRecord r) {
    (sessionIds[m] ??= {}).add(r.sessionId);
    final seen = last[m];
    if (seen == null || r.date.isAfter(seen)) last[m] = r.date;
  }

  for (final r in records) {
    for (final m in r.primary) {
      primarySets[m] = (primarySets[m] ?? 0) + 1;
      volume[m] = (volume[m] ?? 0) + r.volumeKg;
      touch(m, r);
    }
    for (final m in r.secondary) {
      secondarySets[m] = (secondarySets[m] ?? 0) + 1;
      touch(m, r);
    }
  }

  final busiest = primarySets.values.fold(0, (a, b) => a > b ? a : b);
  final trained = MuscleGroup.values.where(sessionIds.containsKey).toList();
  final result = [
    for (final m in trained)
      MuscleExposure(
        muscle: m,
        sessions: sessionIds[m]!.length,
        primarySets: primarySets[m] ?? 0,
        secondarySets: secondarySets[m] ?? 0,
        volumeKg: volume[m] ?? 0,
        lastTrained: last[m]!,
        level: _levelFor(primarySets[m] ?? 0, busiest),
      ),
  ];
  result.sort((a, b) {
    final bySets = b.primarySets.compareTo(a.primarySets);
    if (bySets != 0) return bySets;
    return a.muscle.index.compareTo(b.muscle.index);
  });
  return result;
}

/// How one muscle group was involved in the completed workouts of a window.
///
/// Counts WORKOUTS, not sets, weight or volume: those cannot fairly be
/// compared between muscles. Primary and secondary involvement are counted
/// apart and never added together: a workout can appear in both counts, when
/// one exercise targeted the muscle and another assisted it.
class MuscleInvolvement {
  const MuscleInvolvement({
    required this.muscle,
    required this.primaryWorkouts,
    required this.secondaryWorkouts,
  });

  final MuscleGroup muscle;

  /// Workouts with at least one exercise that targets it directly.
  final int primaryWorkouts;

  /// Workouts with at least one exercise that only assists it.
  final int secondaryWorkouts;
}

/// Which muscle groups the completed workouts in a window covered.
class MuscleDistribution {
  const MuscleDistribution({
    required this.workouts,
    required this.involved,
    required this.notRecorded,
  });

  /// Completed workouts in the window with at least one eligible set.
  final int workouts;

  /// Muscle groups with any involvement, most primary workouts first, ties by
  /// secondary workouts and then [MuscleGroup] order, so it never reshuffles.
  final List<MuscleInvolvement> involved;

  /// Muscle groups no logged exercise listed in the window.
  final List<MuscleGroup> notRecorded;

  bool get isEmpty => workouts == 0;
}

/// Muscle involvement across the completed workouts in [range]. Uses the same
/// eligible sets as everything else here (see [muscleSetRecords]).
MuscleDistribution muscleDistribution(
  List<WorkoutSession> sessions,
  ProgressRange range,
  DateTime today,
) {
  final primary = <MuscleGroup, Set<String>>{};
  final secondary = <MuscleGroup, Set<String>>{};
  final workouts = <String>{};
  for (final r in muscleSetRecords(sessions)) {
    if (!isInRange(r.date, range, today)) continue;
    workouts.add(r.sessionId);
    for (final m in r.primary) {
      (primary[m] ??= {}).add(r.sessionId);
    }
    for (final m in r.secondary) {
      (secondary[m] ??= {}).add(r.sessionId);
    }
  }

  final involved =
      [
        for (final m in MuscleGroup.values)
          if (primary.containsKey(m) || secondary.containsKey(m))
            MuscleInvolvement(
              muscle: m,
              primaryWorkouts: primary[m]?.length ?? 0,
              secondaryWorkouts: secondary[m]?.length ?? 0,
            ),
      ]..sort((a, b) {
        final byPrimary = b.primaryWorkouts.compareTo(a.primaryWorkouts);
        if (byPrimary != 0) return byPrimary;
        final bySecondary = b.secondaryWorkouts.compareTo(a.secondaryWorkouts);
        return bySecondary != 0
            ? bySecondary
            : a.muscle.index.compareTo(b.muscle.index);
      });

  final seen = {for (final i in involved) i.muscle};
  return MuscleDistribution(
    workouts: workouts.length,
    involved: involved,
    notRecorded: [
      for (final m in MuscleGroup.values)
        if (!seen.contains(m)) m,
    ],
  );
}

/// The days of one calendar week a muscle group was trained, counted once
/// per day however many exercises trained it that day.
class MuscleDays {
  const MuscleDays({
    required this.muscle,
    required this.primaryDays,
    required this.secondaryDays,
  });

  final MuscleGroup muscle;

  /// Days it was a primary target; 0 is Monday, 6 is Sunday.
  final Set<int> primaryDays;

  /// Days it was a secondary muscle, whether or not it was also primary.
  final Set<int> secondaryDays;
}

/// Per-muscle training days in the calendar week starting [weekStart] (a
/// Monday), for completed workouts inside [range]. Muscles not involved that
/// week are not listed.
List<MuscleDays> weeklyMuscleDays(
  List<WorkoutSession> sessions,
  DateTime weekStart,
  ProgressRange range,
  DateTime today,
) {
  final start = DateTime.utc(weekStart.year, weekStart.month, weekStart.day);
  final primary = <MuscleGroup, Set<int>>{};
  final secondary = <MuscleGroup, Set<int>>{};
  for (final r in muscleSetRecords(sessions)) {
    if (!isInRange(r.date, range, today)) continue;
    final day = DateTime.utc(
      r.date.year,
      r.date.month,
      r.date.day,
    ).difference(start).inDays;
    if (day < 0 || day > 6) continue;
    for (final m in r.primary) {
      (primary[m] ??= {}).add(day);
    }
    for (final m in r.secondary) {
      (secondary[m] ??= {}).add(day);
    }
  }
  return [
    for (final m in MuscleGroup.values)
      if (primary.containsKey(m) || secondary.containsKey(m))
        MuscleDays(
          muscle: m,
          primaryDays: primary[m] ?? const {},
          secondaryDays: secondary[m] ?? const {},
        ),
  ]..sort((a, b) {
    final byPrimary = b.primaryDays.length.compareTo(a.primaryDays.length);
    if (byPrimary != 0) return byPrimary;
    final bySecondary = b.secondaryDays.length.compareTo(
      a.secondaryDays.length,
    );
    return bySecondary != 0
        ? bySecondary
        : a.muscle.index.compareTo(b.muscle.index);
  });
}

/// The calendar weeks (Monday starts) the weekly view can show for [range],
/// oldest first, ending with the current week. Empty when no eligible workout
/// is inside the range. A fixed range never offers its leading part-week, so
/// a week shown is always a whole week of the window.
List<DateTime> selectableWeeks(
  List<WorkoutSession> sessions,
  ProgressRange range,
  DateTime today,
) {
  final dates = [
    for (final r in muscleSetRecords(sessions))
      if (isInRange(r.date, range, today)) r.date,
  ];
  if (dates.isEmpty) return const [];

  var from = startOfWeek(dates.first);
  final days = range.days;
  if (days != null) {
    final windowStart = addDays(dateOnly(today), -(days - 1));
    final firstWhole = startOfWeek(windowStart) == windowStart
        ? windowStart
        : addDays(startOfWeek(windowStart), 7);
    if (firstWhole.isAfter(from)) from = firstWhole;
  }
  final last = startOfWeek(dateOnly(today));
  return [
    for (var week = from; !week.isAfter(last); week = addDays(week, 7)) week,
  ];
}

// ---------------------------------------------------------------------------
// Insight
// ---------------------------------------------------------------------------

String _names(List<MuscleGroup> muscles, {int max = 4}) {
  final labels = [for (final m in muscles) m.label];
  if (labels.length <= max) {
    if (labels.length <= 1) return labels.join();
    return '${labels.sublist(0, labels.length - 1).join(', ')} and '
        '${labels.last}';
  }
  return '${labels.take(max).join(', ')} and ${labels.length - max} more';
}

/// One short, factual sentence about what the window covered. It reports
/// coverage only: it never says a muscle is under- or over-trained.
String distributionInsight(MuscleDistribution d) {
  final primary = [
    for (final i in d.involved)
      if (i.primaryWorkouts > 0) i.muscle,
  ];
  final secondaryOnly = [
    for (final i in d.involved)
      if (i.primaryWorkouts == 0) i.muscle,
  ];
  final total = MuscleGroup.values.length;
  final workouts = '${d.workouts} workout${d.workouts == 1 ? '' : 's'}';

  final parts = <String>[
    primary.isEmpty
        ? 'In $workouts, no muscle group had primary involvement.'
        : 'In $workouts, ${primary.length} of $total muscle groups had '
              'primary involvement: ${_names(primary)}.',
  ];
  if (secondaryOnly.isNotEmpty) {
    parts.add(
      '${secondaryOnly.length} more appeared only as secondary: '
      '${_names(secondaryOnly)}.',
    );
  }
  if (d.notRecorded.isNotEmpty) {
    parts.add('Not recorded: ${_names(d.notRecorded)}.');
  }
  return parts.join(' ');
}

/// Primary sets for one muscle in one calendar week.
class WeeklyMuscleSets {
  const WeeklyMuscleSets({required this.weekStart, required this.sets});

  final DateTime weekStart;
  final int sets;
}

/// [muscle]'s sets per week within [range], oldest first: primary sets, or
/// secondary sets when [secondary] is true.
///
/// Starts at the first week the user trained anything in the window, so a
/// zero means "trained that week, but not this muscle", which is real. Weeks
/// before any training are not shown as zero, because they are not data.
List<WeeklyMuscleSets> weeklyMuscleSets(
  List<WorkoutSession> sessions,
  MuscleGroup muscle,
  ProgressRange range,
  DateTime today, {
  bool secondary = false,
}) {
  final records = muscleSetRecords(
    sessions,
  ).where((r) => isInRange(r.date, range, today)).toList();
  if (records.isEmpty) return const [];

  final first = startOfWeek(records.first.date);
  final last = startOfWeek(dateOnly(today));
  final counts = <DateTime, int>{};
  for (final r in records) {
    if (!(secondary ? r.secondary : r.primary).contains(muscle)) continue;
    final week = startOfWeek(r.date);
    counts[week] = (counts[week] ?? 0) + 1;
  }

  return [
    for (var week = first; !week.isAfter(last); week = addDays(week, 7))
      WeeklyMuscleSets(weekStart: week, sets: counts[week] ?? 0),
  ];
}
