import '../core/format.dart';
import '../core/units.dart';
import '../data/training_stats.dart';
import '../models/models.dart';

// Strength trends: what the Strength tab draws, and the one-line insight
// under each chart.
//
// Every number comes from completed sessions and their saved sets:
//   - Only completed WORKING and FAILURE sets count. Warm-ups and skipped
//     sets never do (see [workSetsOf]).
//   - A set needs at least one logged rep to count. A zero or missing rep
//     count is not a set that was done.
//   - A set has a load only when its weight is above zero. Sets without one
//     are bodyweight: they have reps and no volume, and are never given a
//     made-up weight.
//
// One session of one exercise is summarised the same way for every chart:
//   top set   the heaviest eligible set, then the one with most reps. Its
//             weight is the session's weight, and its reps the session's
//             reps, so the two charts describe the same set and are never a
//             mix of different sets.
//   volume    the sum of weight × reps over every eligible weighted set.
//
// Volume is workload: it rises with more sets or reps as well as with more
// weight, so nothing here says strength improved because volume did.

/// The three charts of the Per Exercise view.
enum ExerciseChart {
  weight('Weight Trend'),
  reps('Rep Trend'),
  volume('Session Volume');

  const ExerciseChart(this.label);
  final String label;
}

/// One exercise in one completed session, summarised.
class ExerciseSession {
  const ExerciseSession({
    required this.date,
    required this.topWeightKg,
    required this.topReps,
    required this.volumeKg,
    required this.sets,
  });

  final DateTime date;

  /// Weight of the top set; null when no set had a weight (bodyweight).
  final double? topWeightKg;

  /// Reps of the top set.
  final int topReps;

  /// Weight × reps over the weighted sets; 0 when none were weighted.
  final double volumeKg;

  /// Eligible sets in the session.
  final int sets;
}

/// One day's total volume, over every exercise of every workout completed
/// that day.
class WorkoutVolume {
  const WorkoutVolume({
    required this.date,
    required this.volumeKg,
    required this.sets,
    this.workouts = 1,
  });

  final DateTime date;
  final double volumeKg;
  final int sets;

  /// Completed workouts with weighted sets on [date].
  final int workouts;
}

bool _isEligible(SetLog set) => (set.reps ?? 0) > 0;

/// The heavier of two eligible sets: by weight, then by reps.
bool _beats(SetLog a, SetLog b) {
  final aw = isWeightedSet(a) ? a.weightKg! : 0.0;
  final bw = isWeightedSet(b) ? b.weightKg! : 0.0;
  if (aw != bw) return aw > bw;
  return (a.reps ?? 0) > (b.reps ?? 0);
}

/// [exerciseId] in each completed session inside [range], oldest first.
/// A session without an eligible set for it is left out, not shown as zero.
List<ExerciseSession> exerciseSessions(
  List<WorkoutSession> sessions,
  String exerciseId,
  ProgressRange range,
  DateTime today,
) {
  final result = <ExerciseSession>[];
  for (final session in oldestFirst(sessions)) {
    if (!session.isCompleted) continue;
    final date = sessionDate(session);
    if (!isInRange(date, range, today)) continue;

    final sets = [
      for (final log in session.exerciseLogs)
        if (log.exerciseId == exerciseId) ...workSetsOf(log).where(_isEligible),
    ];
    if (sets.isEmpty) continue;

    var top = sets.first;
    var volume = 0.0;
    for (final set in sets) {
      if (_beats(set, top)) top = set;
      if (isWeightedSet(set)) volume += set.weightKg! * set.reps!;
    }
    result.add(
      ExerciseSession(
        date: date,
        topWeightKg: isWeightedSet(top) ? top.weightKg : null,
        topReps: top.reps!,
        volumeKg: volume,
        sets: sets.length,
      ),
    );
  }
  return result;
}

/// Total volume of each day inside [range], oldest first. Workouts finished
/// on the same day are added together, so a quick workout and a program
/// workout on one day are one point, never compared with each other.
/// A session with no weighted set has nothing to total and is left out.
List<WorkoutVolume> workoutVolumes(
  List<WorkoutSession> sessions,
  ProgressRange range,
  DateTime today,
) {
  final result = <WorkoutVolume>[];
  for (final session in oldestFirst(sessions)) {
    if (!session.isCompleted) continue;
    final date = sessionDate(session);
    if (!isInRange(date, range, today)) continue;

    var volume = 0.0;
    var sets = 0;
    for (final log in session.exerciseLogs) {
      for (final set in workSetsOf(log).where(_isEligible)) {
        if (!isWeightedSet(set)) continue;
        volume += set.weightKg! * set.reps!;
        sets++;
      }
    }
    if (volume <= 0) continue;
    // Oldest first, so a same-day workout always follows the day's entry.
    if (result.isNotEmpty && result.last.date == date) {
      final day = result.removeLast();
      result.add(
        WorkoutVolume(
          date: date,
          volumeKg: day.volumeKg + volume,
          sets: day.sets + sets,
          workouts: day.workouts + 1,
        ),
      );
    } else {
      result.add(WorkoutVolume(date: date, volumeKg: volume, sets: sets));
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Insights
// ---------------------------------------------------------------------------

/// Shown whenever there is nothing fair to compare yet.
const String kNeedMoreSessions =
    'Log at least two comparable sessions in this period to see a '
    'comparison.';

/// A change smaller than this share of the starting value is "about the
/// same": session-to-session noise, not a trend.
const double kSteadyShare = 0.02;

/// Volume as the app writes it: weight × reps, so the unit says both.
String formatWorkVolume(double kg, WeightUnit units) =>
    '${formatThousands(enteredFromKg(kg, units).roundToDouble())} '
    '${units.short}·reps';

bool _sameLoad(double? a, double? b) {
  if (a == null || b == null) return a == b;
  return (a - b).abs() < 0.01;
}

String _loadText(double? kg, WeightUnit units) =>
    kg == null ? 'bodyweight' : formatWeight(kg, units);

String _plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

/// Top working weight, first session to latest in the period.
String weightInsight(List<ExerciseSession> sessions, WeightUnit units) {
  final weighted = [
    for (final s in sessions)
      if (s.topWeightKg != null) s,
  ];
  if (weighted.length < 2) return kNeedMoreSessions;
  final first = weighted.first;
  final last = weighted.last;
  final change = last.topWeightKg! - first.topWeightKg!;
  final count = _plural(weighted.length, 'session');
  if (change.abs() < 0.005) {
    return 'Top working weight stayed at '
        '${formatWeight(last.topWeightKg!, units)} across $count.';
  }
  final verb = change > 0 ? 'rose' : 'fell';
  final sign = change > 0 ? '+' : '−';
  return 'Top working weight $verb from '
      '${formatWeight(first.topWeightKg!, units)} '
      '(${formatShortDate(first.date)}) to '
      '${formatWeight(last.topWeightKg!, units)} '
      '(${formatShortDate(last.date)}): '
      '$sign${formatWeight(change.abs(), units)} over $count.';
}

/// Top-set reps at the latest session's load, against the first earlier
/// session at that same load. Reps at different loads are not compared.
String repInsight(List<ExerciseSession> sessions, WeightUnit units) {
  if (sessions.length < 2) return kNeedMoreSessions;
  final latest = sessions.last;
  ExerciseSession? earlier;
  for (final s in sessions.take(sessions.length - 1)) {
    if (_sameLoad(s.topWeightKg, latest.topWeightKg)) {
      earlier = s;
      break;
    }
  }
  final load = _loadText(latest.topWeightKg, units);
  if (earlier == null) {
    return 'The load changed between sessions (latest: $load), so reps '
        "can't be compared yet. Log another session at the same load.";
  }
  final change = latest.topReps - earlier.topReps;
  final span =
      '${earlier.topReps} (${formatShortDate(earlier.date)}) to '
      '${latest.topReps} (${formatShortDate(latest.date)})';
  if (change == 0) {
    return 'At $load, top-set reps stayed at ${latest.topReps} '
        '(${formatShortDate(earlier.date)} to '
        '${formatShortDate(latest.date)}).';
  }
  return 'At $load, top-set reps ${change > 0 ? 'rose' : 'fell'} from $span.';
}

/// Volume across the period. With a handful of sessions it is the first
/// against the latest; with four or more, the average of the earlier half
/// against the average of the latest half, so one odd session does not set
/// the message. [noun] names what is being totalled.
String volumeInsight(
  List<({DateTime date, double volumeKg})> points,
  WeightUnit units, {
  required String noun,
}) {
  if (points.length < 2) return kNeedMoreSessions;

  final String before;
  final String after;
  final double a;
  final double b;
  if (points.length < 4) {
    a = points.first.volumeKg;
    b = points.last.volumeKg;
    before = formatShortDate(points.first.date);
    after = formatShortDate(points.last.date);
  } else {
    final half = points.length ~/ 2;
    double mean(Iterable<({DateTime date, double volumeKg})> p) =>
        p.fold<double>(0, (sum, x) => sum + x.volumeKg) / p.length;
    a = mean(points.take(half));
    b = mean(points.skip(points.length - half));
    before = 'first ${_plural(half, 'session')}';
    after = 'latest ${_plural(half, 'session')}';
  }

  final prefix = points.length < 4
      ? '${noun[0].toUpperCase()}${noun.substring(1)}'
      : 'Average $noun';
  final change = b - a;
  if (a <= 0 || change.abs() / a < kSteadyShare) {
    return '$prefix stayed about the same: '
        '${formatWorkVolume(a, units)} ($before) and '
        '${formatWorkVolume(b, units)} ($after).';
  }
  final pct = (change.abs() / a * 100).round();
  return '$prefix ${change > 0 ? 'rose' : 'fell'} $pct% from '
      '${formatWorkVolume(a, units)} ($before) to '
      '${formatWorkVolume(b, units)} ($after).';
}
