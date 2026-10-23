import '../data/training_stats.dart';
import '../models/models.dart';
import 'body_progress.dart';
import 'muscle_exposure.dart';
import 'scan_comparison.dart';
import 'strength_progress.dart';
import 'strength_trends.dart';
import 'training_frequency.dart';

export 'body_progress.dart';
export 'muscle_exposure.dart';
export 'scan_comparison.dart';
export 'strength_progress.dart';
export 'strength_trends.dart';
export 'training_frequency.dart';

/// One place to ask progress questions from.
///
/// It holds no state of its own and stores nothing: every answer is worked
/// out from the completed sessions, the exercise catalogue, the profile's
/// weight log and the saved scans, all through their existing stores. So it
/// can never drift from the history, and any window can be recalculated.
///
/// The three areas are kept apart on purpose:
///   strength      am I getting stronger?
///   muscles       am I training my muscles consistently and evenly?
///   body          are my measurable attributes changing?
/// Scans are compared through [compareScanMeasurements], which belongs to
/// Body Analysis and is never folded into Body Progress.
class ProgressAnalytics {
  ProgressAnalytics({
    required List<WorkoutSession> sessions,
    this.weightLog = const [],
    DateTime? today,
  }) : sessions = [
         for (final s in sessions)
           if (s.isCompleted) s,
       ],
       today = today ?? DateTime.now();

  /// Completed sessions only. Anything else is dropped on the way in.
  final List<WorkoutSession> sessions;

  final List<BodyWeightEntry> weightLog;
  final DateTime today;

  bool get hasWorkouts => sessions.isNotEmpty;

  // ---- Strength --------------------------------------------------------

  List<ExerciseSummary> strengthExercisesIn(ProgressRange range) =>
      strengthExercises(sessions, range, today);

  StrengthProgress strength({
    required String exerciseId,
    required StrengthMetric metric,
    required ProgressRange range,
  }) => strengthProgress(
    sessions: sessions,
    exerciseId: exerciseId,
    metric: metric,
    range: range,
    today: today,
  );

  /// One exercise, summarised per completed session in [range].
  List<ExerciseSession> exerciseTrend(String exerciseId, ProgressRange range) =>
      exerciseSessions(sessions, exerciseId, range, today);

  /// Total volume of each completed session in [range], all exercises.
  List<WorkoutVolume> workoutVolume(ProgressRange range) =>
      workoutVolumes(sessions, range, today);

  // ---- Muscle Training -------------------------------------------------

  /// Every completed work set with its muscles: the raw material for any
  /// later analysis, at full detail.
  List<MuscleSetRecord> get setRecords => muscleSetRecords(sessions);

  List<MuscleExposure> exposure(ProgressRange range) =>
      muscleExposure(sessions, range, today);

  /// Which muscle groups the completed workouts in [range] covered.
  MuscleDistribution distribution(ProgressRange range) =>
      muscleDistribution(sessions, range, today);

  /// The weeks the weekly view can show for [range], ending this week.
  List<DateTime> weeksIn(ProgressRange range) =>
      selectableWeeks(sessions, range, today);

  /// Training days per muscle in the calendar week starting [weekStart].
  List<MuscleDays> muscleDaysIn(DateTime weekStart, ProgressRange range) =>
      weeklyMuscleDays(sessions, weekStart, range, today);

  List<WeeklyMuscleSets> muscleTrend(
    MuscleGroup muscle,
    ProgressRange range, {
    bool secondary = false,
  }) => weeklyMuscleSets(sessions, muscle, range, today, secondary: secondary);

  /// How often the user trained in [range]. Not adherence: nothing here
  /// compares training with a plan.
  WorkoutFrequency frequency(ProgressRange range) =>
      workoutFrequency(sessions, range, today);

  TrainingSummary summary(ProgressRange range) =>
      summarize(sessionsInRange(sessions, range, today));

  // ---- Body Progress ---------------------------------------------------

  BodyWeightProgress bodyWeight(ProgressRange range) =>
      bodyWeightProgress(weightLog, range, today);

  // ---- Body Analysis (not progress) -------------------------------------

  /// Two scans compared as measurements. Static because it has nothing to
  /// do with training history.
  static ScanComparison compareScanMeasurements(
    Measurement previous,
    Measurement latest,
  ) => compareScans(previous, latest);
}
