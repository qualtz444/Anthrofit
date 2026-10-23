import '../core/format.dart';
import '../models/models.dart';

// Everything on the History and Progress screens is calculated here, from the
// saved WorkoutSession records. Nothing in this file is stored anywhere.
//
// Rules used throughout:
//  - Only COMPLETED sets count (SetLog.isCompleted).
//  - Warm-up sets are shown in History but are left out of training totals,
//    volume, and records. Working and Failure sets count.
//  - A "weighted" set has an actual logged weight above 0. Blank or 0 weight is
//    treated as "no external load". No bodyweight value is ever estimated.
//  - Targets (the plan) are never used in any calculation.
//  - Names come from the session's own saved copy, never from the exercise
//    library, so old sessions stay readable if the library changes.
//  - A session's date is the local date it was completed.
//  - Weeks run Monday to Sunday, matching the Weekday order used in programs.

// ---------------------------------------------------------------------------
// Dates and ranges
// ---------------------------------------------------------------------------

/// The windows progress is looked at through: the last week, 1, 3 and 6
/// months (30, 90 and 180 days back from today), or everything.
enum ProgressRange {
  week1('1W', 7),
  month1('1M', 30),
  month3('3M', 90),
  month6('6M', 180),
  allTime('All', null);

  const ProgressRange(this.label, this.days);
  final String label;

  /// Null means no limit.
  final int? days;
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// DST-safe: the DateTime constructor rolls extra days over correctly.
DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

/// Monday of the week containing [d].
DateTime startOfWeek(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

DateTime sessionDate(WorkoutSession s) =>
    dateOnly(s.completedAt ?? s.startedAt);

/// "Last 7 days" means today and the 6 days before it.
bool isInRange(DateTime date, ProgressRange range, DateTime today) {
  final day = dateOnly(date);
  final end = dateOnly(today);
  if (day.isAfter(end)) return false;
  final days = range.days;
  if (days == null) return true;
  return !day.isBefore(addDays(end, -(days - 1)));
}

List<WorkoutSession> sessionsInRange(
  List<WorkoutSession> sessions,
  ProgressRange range,
  DateTime today,
) => sessions.where((s) => isInRange(sessionDate(s), range, today)).toList();

List<WorkoutSession> newestFirst(List<WorkoutSession> sessions) {
  final copy = [...sessions];
  copy.sort(
    (a, b) =>
        (b.completedAt ?? b.startedAt).compareTo(a.completedAt ?? a.startedAt),
  );
  return copy;
}

List<WorkoutSession> oldestFirst(List<WorkoutSession> sessions) {
  final copy = [...sessions];
  copy.sort(
    (a, b) =>
        (a.completedAt ?? a.startedAt).compareTo(b.completedAt ?? b.startedAt),
  );
  return copy;
}

/// Groups sessions by the day they were completed (for the calendar).
Map<DateTime, List<WorkoutSession>> sessionsByDate(
  List<WorkoutSession> sessions,
) {
  final map = <DateTime, List<WorkoutSession>>{};
  for (final s in newestFirst(sessions)) {
    map.putIfAbsent(sessionDate(s), () => []).add(s);
  }
  return map;
}

// ---------------------------------------------------------------------------
// Sets, volume, totals
// ---------------------------------------------------------------------------

/// Working and Failure sets count toward training. Warm-up sets do not.
bool isWorkSet(SetLog set) => set.setType != SetType.warmUp;

/// The completed Working and Failure sets of one exercise.
List<SetLog> workSetsOf(ExerciseLog log) =>
    log.completedSets.where(isWorkSet).toList();

/// True for a completed set with an actual logged weight above 0.
bool isWeightedSet(SetLog set) {
  final w = set.weightKg;
  return set.isCompleted && w != null && w.isFinite && w > 0;
}

/// "40 kg × 10", "12 reps", or "12:30" for a set recorded as time.
String formatSetLog(SetLog set) {
  final duration = set.durationSeconds;
  if (duration != null && duration > 0) return formatClock(duration);
  final reps = set.reps ?? 0;
  final w = set.weightKg;
  if (w == null || w == 0) return '$reps reps';
  return '${formatNumber(w)} kg × $reps';
}

/// Exercises in the session that have at least one completed set.
int exerciseCountOf(WorkoutSession s) =>
    s.exerciseLogs.where((l) => l.completedSets.isNotEmpty).length;

class TrainingSummary {
  const TrainingSummary({
    required this.workouts,
    required this.sets,
    required this.reps,
    required this.volumeKg,
    required this.weightedSets,
    required this.bodyweightSets,
    required this.bodyweightReps,
  });

  final int workouts;

  /// All completed sets, weighted or not.
  final int sets;
  final int reps;

  /// Sum of weight × reps over weighted sets only.
  final double volumeKg;
  final int weightedSets;

  /// Completed sets with no logged weight (blank or 0).
  final int bodyweightSets;
  final int bodyweightReps;
}

TrainingSummary summarize(Iterable<WorkoutSession> sessions) {
  var workouts = 0;
  var sets = 0;
  var reps = 0;
  var volume = 0.0;
  var weightedSets = 0;
  var bodyweightSets = 0;
  var bodyweightReps = 0;

  for (final session in sessions) {
    workouts++;
    for (final log in session.exerciseLogs) {
      for (final set in log.sets) {
        final r = set.reps ?? 0;
        if (!set.isCompleted || r <= 0 || !isWorkSet(set)) continue;
        sets++;
        reps += r;
        if (isWeightedSet(set)) {
          weightedSets++;
          volume += set.weightKg! * r;
        } else {
          bodyweightSets++;
          bodyweightReps += r;
        }
      }
    }
  }

  return TrainingSummary(
    workouts: workouts,
    sets: sets,
    reps: reps,
    volumeKg: volume,
    weightedSets: weightedSets,
    bodyweightSets: bodyweightSets,
    bodyweightReps: bodyweightReps,
  );
}

// ---------------------------------------------------------------------------
// Weekly buckets (charts)
// ---------------------------------------------------------------------------

class WeekBucket {
  const WeekBucket({
    required this.weekStart,
    required this.workouts,
    required this.volumeKg,
  });

  final DateTime weekStart;
  final int workouts;
  final double volumeKg;
}

/// One bucket per Monday-to-Sunday week, oldest first, ending with the
/// current (possibly unfinished) week.
/// [weeks] null = from the week of the first session until now.
List<WeekBucket> weeklyBuckets(
  List<WorkoutSession> sessions,
  DateTime today, {
  int? weeks,
}) {
  final thisWeek = startOfWeek(today);

  int count;
  if (weeks != null) {
    count = weeks;
  } else {
    if (sessions.isEmpty) return const [];
    final earliest = sessions
        .map(sessionDate)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    var cursor = startOfWeek(earliest);
    count = 1;
    while (cursor.isBefore(thisWeek)) {
      cursor = addDays(cursor, 7);
      count++;
    }
  }

  final buckets = <WeekBucket>[];
  for (var i = 0; i < count; i++) {
    final start = addDays(thisWeek, -7 * (count - 1 - i));
    final end = addDays(start, 7);
    final inWeek = sessions.where((s) {
      final d = sessionDate(s);
      return !d.isBefore(start) && d.isBefore(end);
    }).toList();
    buckets.add(
      WeekBucket(
        weekStart: start,
        workouts: inWeek.length,
        volumeKg: summarize(inWeek).volumeKg,
      ),
    );
  }
  return buckets;
}

// ---------------------------------------------------------------------------
// Consistency
// ---------------------------------------------------------------------------

int workoutsInWeekOf(List<WorkoutSession> sessions, DateTime day) {
  final start = startOfWeek(day);
  final end = addDays(start, 7);
  return sessions.where((s) {
    final d = sessionDate(s);
    return !d.isBefore(start) && d.isBefore(end);
  }).length;
}

int workoutsInMonthOf(List<WorkoutSession> sessions, DateTime day) =>
    sessions.where((s) {
      final d = sessionDate(s);
      return d.year == day.year && d.month == day.month;
    }).length;

class StreakInfo {
  const StreakInfo({required this.current, required this.longest});

  final int current;
  final int longest;
}

/// A streak is a run of consecutive weeks that each contain at least one
/// completed workout. It is based only on completed sessions.
/// The current streak is not broken by a week that has not finished yet:
/// if this week has no workout so far, it counts back from last week.
StreakInfo weekStreaks(List<WorkoutSession> sessions, DateTime today) {
  final weeks = <DateTime>{
    for (final s in sessions) startOfWeek(sessionDate(s)),
  };
  if (weeks.isEmpty) return const StreakInfo(current: 0, longest: 0);

  final sorted = weeks.toList()..sort();
  var longest = 1;
  var run = 1;
  for (var i = 1; i < sorted.length; i++) {
    run = sorted[i] == addDays(sorted[i - 1], 7) ? run + 1 : 1;
    if (run > longest) longest = run;
  }

  final thisWeek = startOfWeek(today);
  var cursor = weeks.contains(thisWeek) ? thisWeek : addDays(thisWeek, -7);
  var current = 0;
  while (weeks.contains(cursor)) {
    current++;
    cursor = addDays(cursor, -7);
  }
  return StreakInfo(current: current, longest: longest);
}

class ScheduledProgress {
  const ScheduledProgress({required this.done, required this.opportunities});

  /// Scheduled days (so far this week) on which a workout was completed.
  final int done;

  /// Scheduled days this week that are today or earlier.
  final int opportunities;

  int get percent =>
      opportunities == 0 ? 0 : (done * 100 / opportunities).round();
}

/// Current week only. A program's schedule is not saved with each session, so
/// older weeks cannot be scored without guessing, and they are not scored.
/// Returns null when there is no schedule.
ScheduledProgress? scheduledThisWeek(
  List<WorkoutSession> sessions,
  Set<Weekday> scheduledDays,
  DateTime today,
) {
  if (scheduledDays.isEmpty) return null;
  final weekStart = startOfWeek(today);
  final end = dateOnly(today);
  final trainedDates = sessions.map(sessionDate).toSet();

  var opportunities = 0;
  var done = 0;
  for (final day in scheduledDays) {
    final date = addDays(weekStart, day.index);
    if (date.isAfter(end)) continue;
    opportunities++;
    if (trainedDates.contains(date)) done++;
  }
  return ScheduledProgress(done: done, opportunities: opportunities);
}

// ---------------------------------------------------------------------------
// Per-exercise history
// ---------------------------------------------------------------------------

class ExerciseSummary {
  const ExerciseSummary({
    required this.exerciseId,
    required this.name,
    required this.sessionCount,
    required this.lastPerformed,
  });

  final String exerciseId;

  /// The name saved in the most recent session.
  final String name;
  final int sessionCount;
  final DateTime lastPerformed;
}

class _ExerciseAccumulator {
  String name = '';
  int sessions = 0;
  DateTime last = DateTime(0);
}

/// Every exercise that appears in [sessions], most recently performed first.
List<ExerciseSummary> exercisesPerformed(List<WorkoutSession> sessions) {
  final byId = <String, _ExerciseAccumulator>{};
  for (final session in oldestFirst(sessions)) {
    final date = sessionDate(session);
    final seen = <String>{};
    for (final log in session.exerciseLogs) {
      if (workSetsOf(log).isEmpty) continue;
      final acc = byId.putIfAbsent(log.exerciseId, _ExerciseAccumulator.new);
      acc.name = log.exerciseName;
      acc.last = date;
      if (seen.add(log.exerciseId)) acc.sessions++;
    }
  }
  final result = [
    for (final entry in byId.entries)
      ExerciseSummary(
        exerciseId: entry.key,
        name: entry.value.name,
        sessionCount: entry.value.sessions,
        lastPerformed: entry.value.last,
      ),
  ];
  result.sort((a, b) {
    final byDate = b.lastPerformed.compareTo(a.lastPerformed);
    return byDate != 0 ? byDate : a.name.compareTo(b.name);
  });
  return result;
}

/// One exercise as it was performed in one session. Actual sets only.
class ExerciseEntry {
  const ExerciseEntry({
    required this.date,
    required this.exerciseName,
    required this.sets,
  });

  final DateTime date;
  final String exerciseName;
  final List<SetLog> sets;

  /// Highest logged weight in this session, or null if no set had a weight.
  double? get heaviestKg {
    double? best;
    for (final set in sets) {
      if (isWeightedSet(set) && (best == null || set.weightKg! > best)) {
        best = set.weightKg;
      }
    }
    return best;
  }

  int get mostReps =>
      sets.fold(0, (m, s) => (s.reps ?? 0) > m ? (s.reps ?? 0) : m);

  /// The set that best stands for this session: the heaviest weight (more reps
  /// breaks a tie), or the most reps if no set had a weight.
  SetLog? get bestSet {
    SetLog? best;
    for (final set in sets) {
      if ((set.reps ?? 0) <= 0) continue;
      if (best == null) {
        best = set;
        continue;
      }
      final bestWeight = isWeightedSet(best) ? best.weightKg! : 0.0;
      final weight = isWeightedSet(set) ? set.weightKg! : 0.0;
      if (weight > bestWeight ||
          (weight == bestWeight && (set.reps ?? 0) > (best.reps ?? 0))) {
        best = set;
      }
    }
    return best;
  }
}

/// Every session that included [exerciseId], oldest first.
List<ExerciseEntry> exerciseHistory(
  List<WorkoutSession> sessions,
  String exerciseId,
) {
  final entries = <ExerciseEntry>[];
  for (final session in oldestFirst(sessions)) {
    for (final log in session.exerciseLogs) {
      if (log.exerciseId != exerciseId || workSetsOf(log).isEmpty) continue;
      entries.add(
        ExerciseEntry(
          date: sessionDate(session),
          exerciseName: log.exerciseName,
          sets: workSetsOf(log),
        ),
      );
    }
  }
  return entries;
}

class PersonalRecords {
  const PersonalRecords({
    this.heaviestKg,
    this.repsAtHeaviest,
    this.mostRepsNoWeight,
  });

  /// Highest weight in any completed set.
  final double? heaviestKg;

  /// Most reps in one set at exactly that weight.
  final int? repsAtHeaviest;

  /// Most reps in one set with no logged weight.
  final int? mostRepsNoWeight;
}

/// Records come only from logged sets. There is no one-rep-max estimate.
PersonalRecords personalRecords(List<ExerciseEntry> entries) {
  double? heaviest;
  for (final entry in entries) {
    final h = entry.heaviestKg;
    if (h != null && (heaviest == null || h > heaviest)) heaviest = h;
  }

  int? repsAtHeaviest;
  int? mostRepsNoWeight;
  for (final entry in entries) {
    for (final set in entry.sets) {
      final reps = set.reps ?? 0;
      if (reps <= 0) continue;
      if (isWeightedSet(set)) {
        if (set.weightKg == heaviest &&
            (repsAtHeaviest == null || reps > repsAtHeaviest)) {
          repsAtHeaviest = reps;
        }
      } else if (mostRepsNoWeight == null || reps > mostRepsNoWeight) {
        mostRepsNoWeight = reps;
      }
    }
  }

  return PersonalRecords(
    heaviestKg: heaviest,
    repsAtHeaviest: repsAtHeaviest,
    mostRepsNoWeight: mostRepsNoWeight,
  );
}
