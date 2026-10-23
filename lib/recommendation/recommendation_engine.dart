import '../coaching/exercise_tutorial.dart';
import '../coaching/limitation_check.dart';
import '../core/id.dart';
import '../data/exercise_library.dart';
import '../models/models.dart';
import 'exercise_scorer.dart';
import 'prescription_rules.dart';
import 'proportion_rules.dart';
import 'recommendation_tags.dart';
import 'recommendation_weights.dart';

/// One recommended exercise: what to do, and why it was chosen.
class RecommendedExercise {
  const RecommendedExercise({
    required this.exercise,
    required this.planned,
    required this.score,
    required this.explanation,
    this.setupCue,
    this.tags = const [],
    this.substitutions = const [],
  });

  final Exercise exercise;

  /// Ready to drop into a Workout: the existing PlannedExercise, with one
  /// PlannedSet per set.
  final PlannedExercise planned;

  final double score;

  /// One sentence, built from structured reasons. Never generated text.
  final String explanation;

  /// A proportion-based setup note, when a rule produced one.
  final String? setupCue;

  /// Short labels saying why this exercise was chosen.
  final List<RecommendationTag> tags;

  /// Other exercises the same setup allows that train the same main muscle,
  /// best first. Shown so the user knows what to swap to; never saved.
  final List<Exercise> substitutions;

  RecommendedExercise withSubstitutions(List<Exercise> substitutions) =>
      RecommendedExercise(
        exercise: exercise,
        planned: planned,
        score: score,
        explanation: explanation,
        setupCue: setupCue,
        tags: tags,
        substitutions: substitutions,
      );
}

/// How many substitutions each recommended exercise lists.
const int kSubstitutionsPerExercise = 2;

/// What the engine produced for one session.
class WorkoutRecommendation {
  const WorkoutRecommendation({required this.exercises, required this.note});

  final List<RecommendedExercise> exercises;

  /// Set when nothing, or not enough, could be recommended, so a screen can
  /// explain rather than show an empty list.
  final String? note;

  bool get isEmpty => exercises.isEmpty;

  /// The recommendation as a Workout, ready for the existing planner.
  Workout toWorkout({required String name, String focus = ''}) => Workout(
    id: generateId(),
    name: name,
    focus: focus,
    exercises: [for (final e in exercises) e.planned],
  );
}

/// Chooses exercises and writes their prescriptions.
///
/// Deterministic: the same profile, setup and scan always produce the same
/// list in the same order. Nothing here is random, and nothing is generated
/// by a model.
class RecommendationEngine {
  const RecommendationEngine({
    this.rules = PrescriptionRules.standard,
    this.weights = RecommendationWeights.standard,
    this.thresholds = ProportionThresholds.none,
  });

  final PrescriptionRules rules;
  final RecommendationWeights weights;

  /// Proportion cut-offs. Empty by default, which disables every proportion
  /// rule. See proportion_rules.dart.
  final ProportionThresholds thresholds;

  /// Recommends one session's exercises.
  ///
  /// [pool] defaults to the whole exercise library. [exerciseCount] overrides
  /// the count the session length implies.
  WorkoutRecommendation recommendWorkout({
    required UserProfile profile,
    required ProgramSetup setup,
    Measurement? measurement,
    List<Exercise>? pool,
    int? exerciseCount,
    List<MuscleGroup> priorityMuscles = const [],
    List<MuscleGroup> sessionMuscles = const [],
  }) {
    // Noted injuries swap out exercises that load the area, when another
    // exercise trains the same muscle without it.
    final library = avoidLimitations(
      pool ?? ExerciseLibrary.all,
      profile.limitations,
    );
    final scorer = ExerciseScorer(
      setup: setup,
      experience: profile.experience,
      priorityMuscles: priorityMuscles,
      sessionMuscles: sessionMuscles,
      measurement: measurement,
      thresholds: thresholds,
      weights: weights,
    );

    final sets = rules.setsFor(setup.goal, profile.experience);
    final wanted =
        exerciseCount ??
        rules.exerciseCountFor(setup.sessionDuration, sets, setup.goal);

    // Picked one at a time, re-ranking each round, so each choice accounts
    // for the patterns and muscles already covered.
    final chosen = <RecommendedExercise>[];
    final usedIds = <String>{};
    final coveredPatterns = <MovementPattern>{};

    // The muscles this session is for. A split session (Upper, Legs...) must
    // not chase a muscle that belongs to another day.
    final sessionWanted = sessionMuscles.isEmpty
        ? setup.muscles.toSet()
        : sessionMuscles.toSet();

    // Time budget, so a long cardio bout or long rests cannot push the
    // session past the length the user chose. Only when the count comes from
    // the session length; an explicit [exerciseCount] is taken as asked.
    final budgetMinutes = exerciseCount == null
        ? setup.sessionDuration.minutes.toDouble()
        : double.infinity;
    var spentMinutes = 0.0;
    var trimmedForTime = false;
    final setsSoFar = <MuscleGroup, int>{};

    while (chosen.length < wanted) {
      final remaining = library.where((e) => !usedIds.contains(e.id)).toList();
      final ranked = scorer.rank(remaining, coveredPatterns: coveredPatterns);
      if (ranked.isEmpty) break;

      // Spread the slots across the session's muscles: go for the muscle
      // with the fewest direct sets so far that some remaining exercise
      // trains as a primary mover, and take the best-ranked exercise for it.
      // Without this, once every muscle had one exercise the ranking's
      // per-muscle bonus kept choosing multi-muscle lifts, piling sets on the
      // same few muscles (shoulders, glutes) while others stayed at zero.
      final next =
          _forLeastTrained(ranked, sessionWanted, setsSoFar) ?? ranked.first;

      usedIds.add(next.exercise.id);
      // The reason it was picked is saved with it, so the workout screen
      // can show it later without re-running the recommendation.
      final planned = _prescribe(
        next.exercise,
        setup,
        sets,
        profile.experience,
      ).copyWith(note: recommendationNote(next.explanation, next.setupCue));
      final cost = rules.estimatedMinutes(planned);
      // Too long for what is left: try the next best instead. The first
      // exercise is always kept, so a short session still has one.
      if (chosen.isNotEmpty && spentMinutes + cost > budgetMinutes) {
        trimmedForTime = true;
        continue;
      }
      spentMinutes += cost;
      final wasNewPattern = !coveredPatterns.contains(
        next.exercise.movementPattern,
      );
      coveredPatterns.add(next.exercise.movementPattern);
      if (next.exercise.exerciseType != ExerciseType.cardio) {
        for (final m in next.exercise.primaryMuscles) {
          setsSoFar[m] = (setsSoFar[m] ?? 0) + sets;
        }
      }
      chosen.add(
        RecommendedExercise(
          exercise: next.exercise,
          planned: planned,
          score: next.score,
          explanation: next.explanation,
          setupCue: next.setupCue,
          tags: exerciseTags(
            exercise: next.exercise,
            priorityMuscles: priorityMuscles,
            coversNewPattern: wasNewPattern,
            experience: profile.experience,
            proportionReason: next.setupCue == null ? null : next.explanation,
          ),
        ),
      );
    }

    return WorkoutRecommendation(
      exercises: _withSubstitutions(chosen, library, scorer),
      // Fewer than the count because the time ran out is the session
      // length working, not a shortage to explain.
      note: trimmedForTime && chosen.isNotEmpty
          ? null
          : _noteFor(chosen.length, wanted, library, scorer),
    );
  }

  /// Adds swaps to each chosen exercise: the best-ranked exercises left over
  /// that share its type and a primary muscle, preferring the same movement
  /// pattern. They come from the same filtered library and scorer, so they
  /// fit the same equipment, experience and noted injuries. Nothing already
  /// in the session is offered.
  List<RecommendedExercise> _withSubstitutions(
    List<RecommendedExercise> chosen,
    List<Exercise> library,
    ExerciseScorer scorer,
  ) {
    final used = {for (final c in chosen) c.exercise.id};
    final ranked = scorer.rank([
      for (final e in library)
        if (!used.contains(e.id)) e,
    ]);
    return [
      for (final c in chosen)
        c.withSubstitutions(() {
          final matches = [
            for (final s in ranked)
              if (s.exercise.exerciseType == c.exercise.exerciseType &&
                  s.exercise.primaryMuscles.any(
                    c.exercise.primaryMuscles.contains,
                  ))
                s.exercise,
          ];
          // Stable: same pattern first, otherwise keep the ranking's order.
          final samePattern = [
            for (final e in matches)
              if (e.movementPattern == c.exercise.movementPattern) e,
          ];
          return [
            ...samePattern,
            ...matches.where((e) => !samePattern.contains(e)),
          ].take(kSubstitutionsPerExercise).toList();
        }()),
    ];
  }

  /// The best-ranked resistance exercise that trains, as a primary mover, one
  /// of the least-trained muscles in [wanted]. Null when none does.
  ///
  /// Ties between equally trained muscles are left to the ranking (goal,
  /// movement-pattern coverage, experience), not to the order muscles are
  /// listed in. Breaking ties by list order filled full-body sessions with
  /// upper-body muscles and left the legs out entirely.
  ///
  /// Cardio is never used to cover a muscle: it is prescribed as time, not
  /// sets, so it would mark a muscle as trained without any direct sets.
  ScoredExercise? _forLeastTrained(
    List<ScoredExercise> ranked,
    Set<MuscleGroup> wanted,
    Map<MuscleGroup, int> setsSoFar,
  ) {
    final resistance = [
      for (final s in ranked)
        if (s.exercise.exerciseType != ExerciseType.cardio) s,
    ];
    // Only muscles some remaining exercise can actually train count.
    final trainable = {
      for (final s in resistance)
        ...s.exercise.primaryMuscles.where(wanted.contains),
    };
    if (trainable.isEmpty) return null;
    final fewest = trainable
        .map((m) => setsSoFar[m] ?? 0)
        .reduce((a, b) => a < b ? a : b);
    for (final s in resistance) {
      if (s.exercise.primaryMuscles.any(
        (m) => trainable.contains(m) && (setsSoFar[m] ?? 0) == fewest,
      )) {
        return s;
      }
    }
    return null;
  }

  /// Turns an exercise into a prescription using the goal's and the
  /// experience level's rules (ACSM 2009, see prescription_rules.dart).
  /// No target load is set: nothing here knows what the user can lift, and
  /// guessing one would be inventing a number. Progression fills it in from
  /// real history, and the user can always type one.
  PlannedExercise _prescribe(
    Exercise exercise,
    ProgramSetup setup,
    int sets,
    ExperienceLevel experience,
  ) {
    // Cardio is prescribed as one bout of time, not sets of reps.
    if (exercise.exerciseType == ExerciseType.cardio) {
      return PlannedExercise(
        id: generateId(),
        exerciseId: exercise.id,
        plannedSets: List.generate(
          rules.cardioSets,
          (_) => PlannedSet(
            setType: SetType.working,
            targetDurationSeconds: rules.cardioDurationFor(setup.goal),
            restSeconds: 0,
          ),
        ),
      );
    }

    final (repMin, repMax) = rules.repsFor(setup.goal, experience);
    final rest = rules.restFor(setup.goal, experience, exercise);
    return PlannedExercise(
      id: generateId(),
      exerciseId: exercise.id,
      plannedSets: List.generate(
        sets,
        (_) => PlannedSet(
          setType: SetType.working,
          targetRepMin: repMin,
          targetRepMax: repMax,
          restSeconds: rest,
        ),
      ),
    );
  }

  /// Explains a short or empty result, so a screen never just shows nothing.
  String? _noteFor(
    int got,
    int wanted,
    List<Exercise> library,
    ExerciseScorer scorer,
  ) {
    if (got >= wanted) return null;
    if (library.isEmpty) return 'There are no exercises to choose from.';

    // Count why everything was turned down, to say something useful.
    final counts = <RejectionReason, int>{};
    for (final exercise in library) {
      final reason = scorer.reject(exercise);
      if (reason != null) counts[reason] = (counts[reason] ?? 0) + 1;
    }
    if (got == 0) {
      final worst = counts.entries.isEmpty
          ? null
          : counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      switch (worst) {
        case RejectionReason.equipment:
          return 'No exercise matches the equipment you chose. Adding more '
              'equipment, or bodyweight work, would give more options.';
        case RejectionReason.muscles:
          return 'No exercise trains the muscles you chose. Choosing more '
              'muscles would give more options.';
        case RejectionReason.experience:
        case RejectionReason.complexity:
          return 'No exercise matches your experience level yet.';
        case null:
          return 'No exercise matched your setup.';
      }
    }
    return 'Only $got of $wanted exercises matched your setup. '
        'More equipment or more muscles would give more options.';
  }
}
