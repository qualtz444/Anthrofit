import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/data/exercise_library.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/recommendation/exercise_scorer.dart';
import 'package:anthrofit/recommendation/prescription_rules.dart';
import 'package:anthrofit/recommendation/proportion_rules.dart';
import 'package:anthrofit/recommendation/recommendation_engine.dart';

import 'test_helpers.dart';

ProgramSetup _setup({
  TrainingGoal goal = TrainingGoal.buildMuscle,
  SessionDuration duration = SessionDuration.min60,
  TrainingFocus focus = TrainingFocus.fullBody,
  List<MuscleGroup>? muscles,
  Set<EquipmentCategory> categories = const {EquipmentCategory.commercialGym},
  List<EquipmentItem>? equipment,
}) {
  return ProgramSetup(
    goal: goal,
    sessionDuration: duration,
    focus: focus,
    muscles: muscles ?? MuscleGroup.values,
    equipmentCategories: categories,
    equipment: equipment ?? EquipmentItem.values,
  );
}

UserProfile _profile(ExperienceLevel experience) =>
    sampleProfile.copyWith(experience: experience);

ExerciseScorer _scorer({
  ExperienceLevel experience = ExperienceLevel.intermediate,
  ProgramSetup? setup,
  Measurement? measurement,
  ProportionThresholds thresholds = ProportionThresholds.none,
}) => ExerciseScorer(
  setup: setup ?? _setup(),
  experience: experience,
  measurement: measurement,
  thresholds: thresholds,
);

Exercise _ex(String id) => ExerciseLibrary.byId(id)!;

void main() {
  // The exercise catalogue is an asset now, so it has to be loaded.
  useExerciseLibrary();

  // ---------------------------------------------------------------------
  group('eligibility', () {
    test('equipment the user does not have is rejected', () {
      final bodyweightOnly = _scorer(
        setup: _setup(equipment: const [EquipmentItem.none]),
      );
      expect(bodyweightOnly.reject(_ex('push_up')), isNull);
      expect(
        bodyweightOnly.reject(_ex('barbell_bench_press')),
        RejectionReason.equipment,
      );
      expect(
        bodyweightOnly.reject(_ex('lat_pulldown')),
        RejectionReason.equipment,
      );
    });

    test('an exercise that trains none of the chosen muscles is rejected', () {
      final chestOnly = _scorer(setup: _setup(muscles: [MuscleGroup.chest]));
      expect(chestOnly.reject(_ex('machine_chest_press')), isNull);
      expect(chestOnly.reject(_ex('leg_press')), RejectionReason.muscles);
    });

    test('a secondary muscle is enough to be eligible', () {
      // Push-Up trains triceps as a secondary, not a primary.
      final tricepsOnly = _scorer(
        setup: _setup(muscles: [MuscleGroup.triceps]),
      );
      expect(tricepsOnly.reject(_ex('push_up')), isNull);
    });

    test('an exercise above the user\'s experience is rejected', () {
      final beginner = _scorer(experience: ExperienceLevel.beginner);
      // Barbell Back Squat is intermediate.
      expect(
        beginner.reject(_ex('barbell_back_squat')),
        RejectionReason.experience,
      );
      expect(beginner.reject(_ex('leg_press')), isNull);

      // The same exercise is fine for someone more experienced.
      final advanced = _scorer(experience: ExperienceLevel.advanced);
      expect(advanced.reject(_ex('barbell_back_squat')), isNull);
    });

    test('a beginner is not given the most technically demanding work', () {
      final beginner = _scorer(experience: ExperienceLevel.beginner);
      for (final exercise in ExerciseLibrary.all) {
        if (beginner.reject(exercise) == null) {
          expect(
            exercise.complexity,
            isNot(Complexity.high),
            reason: exercise.name,
          );
          expect(
            exercise.experienceLevel,
            ExperienceLevel.beginner,
            reason: exercise.name,
          );
        }
      }
    });

    test('a beginner still has plenty to choose from', () {
      final beginner = _scorer(experience: ExperienceLevel.beginner);
      final eligible = ExerciseLibrary.all.where(
        (e) => beginner.reject(e) == null,
      );
      expect(eligible.length, greaterThan(10));
      expect(eligible.map((e) => e.id), contains('machine_chest_press'));
    });
  });

  // ---------------------------------------------------------------------
  group('scoring', () {
    test('more of the chosen muscles scores higher', () {
      final scorer = _scorer(
        setup: _setup(muscles: [MuscleGroup.chest, MuscleGroup.triceps]),
      );
      // Close-grip bench has both as primaries; machine chest press has one.
      final both = scorer.score(_ex('close_grip_bench_press')).score;
      final one = scorer.score(_ex('machine_chest_press')).score;
      expect(both, greaterThan(one));
    });

    test('a pattern the workout lacks is worth more than one it has', () {
      final scorer = _scorer();
      final fresh = scorer.score(_ex('lat_pulldown')).score;
      final covered = scorer
          .score(
            _ex('lat_pulldown'),
            coveredPatterns: {MovementPattern.verticalPull},
          )
          .score;
      expect(fresh, greaterThan(covered));
    });

    test('complexity changes the order without changing eligibility', () {
      final intermediate = _scorer(experience: ExperienceLevel.intermediate);
      // Both are eligible for an intermediate lifter.
      expect(intermediate.reject(_ex('machine_chest_press')), isNull);
      expect(intermediate.reject(_ex('barbell_bench_press')), isNull);

      // A beginner, by contrast, ranks the simpler one higher.
      final beginner = _scorer(experience: ExperienceLevel.beginner);
      final simple = beginner.score(_ex('machine_chest_press')).score;
      final harder = beginner.score(_ex('cable_chest_press')).score;
      expect(simple, greaterThan(harder));
    });

    test('the goal changes which exercises rank highest', () {
      final strength = _scorer(setup: _setup(goal: TrainingGoal.getStronger));
      final fatLoss = _scorer(setup: _setup(goal: TrainingGoal.loseFat));

      // A free-weight compound suits strength; cardio does not.
      expect(
        strength.score(_ex('barbell_back_squat')).score,
        greaterThan(strength.score(_ex('treadmill_run')).score),
      );
      // Cardio does better under a fat-loss goal than under strength.
      final cardioForFatLoss = fatLoss.score(_ex('treadmill_run')).score;
      final cardioForStrength = strength.score(_ex('treadmill_run')).score;
      expect(cardioForFatLoss, greaterThan(cardioForStrength));
    });

    test('ranking is deterministic, whatever order the pool arrives in', () {
      final scorer = _scorer();
      final forwards = scorer.rank(ExerciseLibrary.all);
      final backwards = scorer.rank(ExerciseLibrary.all.reversed.toList());
      expect(
        forwards.map((s) => s.exercise.id).toList(),
        backwards.map((s) => s.exercise.id).toList(),
      );
      // And rejected exercises never appear.
      expect(forwards.every((s) => scorer.reject(s.exercise) == null), isTrue);
    });

    test('an explanation is built from the reasons, not generated', () {
      final scored = _scorer(
        setup: _setup(muscles: [MuscleGroup.chest]),
      ).score(_ex('machine_chest_press'));
      expect(scored.explanation, startsWith('Recommended because it '));
      expect(scored.explanation, contains('Chest'));
      expect(scored.explanation, endsWith('.'));
      // The same input gives the same sentence.
      expect(
        _scorer(
          setup: _setup(muscles: [MuscleGroup.chest]),
        ).score(_ex('machine_chest_press')).explanation,
        scored.explanation,
      );
    });
  });

  // ---------------------------------------------------------------------
  group('proportions', () {
    // A scan is only ever used alongside thresholds. These stand in for
    // thresholds someone would supply; they are not reference values.
    const testThresholds = ProportionThresholds({
      RatioKeys.femurToTorso: RatioThreshold(low: 0.95, high: 1.05),
      RatioKeys.armToTorso: RatioThreshold(low: 1.20, high: 1.35),
    });

    Measurement scan(Map<String, double> ratios) =>
        Measurement.fromNative({'ratios': ratios});

    test('with no thresholds, nothing changes at all', () {
      final withScan = _scorer(
        measurement: scan({RatioKeys.femurToTorso: 1.30}),
      );
      final without = _scorer();
      final a = withScan.score(_ex('barbell_back_squat'));
      final b = without.score(_ex('barbell_back_squat'));
      expect(a.score, b.score);
      expect(a.setupCue, isNull);
    });

    test('with no scan, nothing changes either', () {
      final scorer = _scorer(thresholds: testThresholds);
      expect(scorer.score(_ex('barbell_back_squat')).setupCue, isNull);
      expect(
        scorer.score(_ex('barbell_back_squat')).score,
        _scorer().score(_ex('barbell_back_squat')).score,
      );
    });

    test('a longer femur nudges the squat variation and adds a cue', () {
      final longFemur = _scorer(
        experience: ExperienceLevel.advanced,
        measurement: scan({RatioKeys.femurToTorso: 1.30}),
        thresholds: testThresholds,
      );
      final neutral = _scorer(experience: ExperienceLevel.advanced);

      final barbell = longFemur.score(_ex('barbell_back_squat'));
      final supported = longFemur.score(_ex('leg_press'));

      // The barbell squat is penalised, the supported pattern rewarded.
      expect(
        barbell.score,
        lessThan(neutral.score(_ex('barbell_back_squat')).score),
      );
      expect(
        supported.score,
        greaterThan(neutral.score(_ex('leg_press')).score),
      );

      // Both carry a setup cue, and the reason appears in the explanation.
      expect(barbell.setupCue, contains('forward lean'));
      expect(supported.setupCue, isNotNull);
      expect(supported.explanation, contains('longer thigh'));
    });

    test('a typical proportion is left alone', () {
      final typical = _scorer(
        experience: ExperienceLevel.advanced,
        measurement: scan({RatioKeys.femurToTorso: 1.00}),
        thresholds: testThresholds,
      );
      final neutral = _scorer(experience: ExperienceLevel.advanced);
      expect(
        typical.score(_ex('barbell_back_squat')).score,
        neutral.score(_ex('barbell_back_squat')).score,
      );
      expect(typical.score(_ex('barbell_back_squat')).setupCue, isNull);
    });

    test('an exercise no rule covers gets no proportion change', () {
      final longFemur = _scorer(
        measurement: scan({RatioKeys.femurToTorso: 1.30}),
        thresholds: testThresholds,
      );
      final neutral = _scorer();
      // A curl has nothing to do with femur length.
      expect(
        longFemur.score(_ex('dumbbell_biceps_curl')).score,
        neutral.score(_ex('dumbbell_biceps_curl')).score,
      );
      expect(longFemur.score(_ex('dumbbell_biceps_curl')).setupCue, isNull);
    });

    test('classification needs both a threshold and a measured ratio', () {
      const thresholds = testThresholds;
      final withRatio = scan({RatioKeys.femurToTorso: 1.30});
      expect(
        thresholds.classify(RatioKeys.femurToTorso, withRatio),
        ProportionClass.high,
      );
      expect(
        thresholds.classify(RatioKeys.femurToTorso, scan({})),
        ProportionClass.unknown,
      );
      expect(
        thresholds.classify(RatioKeys.shoulderToHip, withRatio),
        ProportionClass.unknown,
      ); // no threshold for it
      expect(
        ProportionThresholds.none.classify(RatioKeys.femurToTorso, withRatio),
        ProportionClass.unknown,
      );
    });
  });

  // ---------------------------------------------------------------------
  group('the engine', () {
    const engine = RecommendationEngine();

    test('it fills a session and covers several muscles', () {
      final result = engine.recommendWorkout(
        profile: _profile(ExperienceLevel.intermediate),
        setup: _setup(),
      );
      expect(result.isEmpty, isFalse);
      expect(result.note, isNull);

      // No exercise appears twice.
      final ids = result.exercises.map((e) => e.exercise.id).toList();
      expect(ids.toSet().length, ids.length);

      // It spreads across muscles rather than stacking one.
      final muscles = {
        for (final e in result.exercises) ...e.exercise.primaryMuscles,
      };
      expect(muscles.length, greaterThan(3));
    });

    test('each exercise lists swaps that train the same muscle', () {
      final setup = _setup();
      final result = engine.recommendWorkout(
        profile: _profile(ExperienceLevel.intermediate),
        setup: setup,
      );
      final inSession = {for (final e in result.exercises) e.exercise.id};
      final withSwaps = result.exercises.where(
        (e) => e.substitutions.isNotEmpty,
      );
      expect(withSwaps, isNotEmpty);
      for (final e in result.exercises) {
        expect(
          e.substitutions.length,
          lessThanOrEqualTo(kSubstitutionsPerExercise),
        );
        for (final swap in e.substitutions) {
          final why = '${swap.name} for ${e.exercise.name}';
          expect(inSession.contains(swap.id), isFalse, reason: why);
          expect(swap.exerciseType, e.exercise.exerciseType, reason: why);
          expect(
            swap.primaryMuscles.any(e.exercise.primaryMuscles.contains),
            isTrue,
            reason: why,
          );
          // Only equipment the setup allows.
          expect(
            swap.equipment
                .where((item) => item != EquipmentItem.none)
                .every(setup.equipment.contains),
            isTrue,
            reason: why,
          );
        }
      }
    });

    test('it is deterministic', () {
      final a = engine.recommendWorkout(
        profile: _profile(ExperienceLevel.beginner),
        setup: _setup(),
      );
      final b = engine.recommendWorkout(
        profile: _profile(ExperienceLevel.beginner),
        setup: _setup(),
      );
      expect(
        a.exercises.map((e) => e.exercise.id).toList(),
        b.exercises.map((e) => e.exercise.id).toList(),
      );
    });

    test('a longer session gets more exercises', () {
      int count(SessionDuration duration) => engine
          .recommendWorkout(
            profile: _profile(ExperienceLevel.intermediate),
            setup: _setup(duration: duration),
          )
          .exercises
          .length;
      expect(
        count(SessionDuration.min15),
        lessThan(count(SessionDuration.min90Plus)),
      );
      expect(count(SessionDuration.min15), greaterThanOrEqualTo(1));
    });

    test('ACSM 2009: reps follow the goal and the experience level', () {
      const rules = PrescriptionRules.standard;
      const beginner = ExperienceLevel.beginner;
      const advanced = ExperienceLevel.advanced;
      expect(rules.repsFor(TrainingGoal.getStronger, beginner), (8, 12));
      expect(rules.repsFor(TrainingGoal.getStronger, advanced), (1, 6));
      expect(rules.repsFor(TrainingGoal.buildMuscle, beginner), (8, 12));
      expect(rules.repsFor(TrainingGoal.buildMuscle, advanced), (6, 12));
      expect(rules.repsFor(TrainingGoal.loseFat, advanced), (6, 12));
      expect(
        rules.repsFor(TrainingGoal.improveAthleticPerformance, beginner),
        (3, 6),
      );
      for (final goal in TrainingGoal.values) {
        for (final level in ExperienceLevel.values) {
          expect(rules.setsFor(goal, level), 3);
        }
      }
      expect(acsmDaysPerWeek(beginner), (2, 3));
      expect(acsmDaysPerWeek(ExperienceLevel.intermediate), (3, 4));
      expect(acsmDaysPerWeek(advanced), (4, 6));
    });

    test('the prescription follows the goal', () {
      const rules = PrescriptionRules.standard;
      for (final goal in [TrainingGoal.getStronger, TrainingGoal.buildMuscle]) {
        final result = engine.recommendWorkout(
          profile: _profile(ExperienceLevel.advanced),
          setup: _setup(goal: goal),
          exerciseCount: 1,
        );
        final planned = result.exercises.single.planned;
        final (repMin, repMax) = rules.repsFor(goal, ExperienceLevel.advanced);
        expect(
          planned.plannedSets.length,
          rules.setsFor(goal, ExperienceLevel.advanced),
        );
        expect(planned.plannedSets.first.targetRepMin, repMin);
        expect(planned.plannedSets.first.targetRepMax, repMax);
        // No load is guessed: nothing knows what the user can lift.
        expect(planned.plannedSets.first.targetLoadKg, isNull);
      }
    });

    test('isolation work is rested less than a compound', () {
      final result = engine.recommendWorkout(
        profile: _profile(ExperienceLevel.intermediate),
        setup: _setup(goal: TrainingGoal.getStronger),
        exerciseCount: 12,
      );
      for (final e in result.exercises) {
        final rest = e.planned.plannedSets.first.restSeconds;
        if (e.exercise.exerciseType == ExerciseType.cardio) {
          expect(rest, 0, reason: e.exercise.name); // nothing to rest between
        } else if (e.exercise.movementPattern == MovementPattern.isolation) {
          expect(rest, 120, reason: e.exercise.name); // ACSM 1-2 min
        } else {
          expect(rest, 180, reason: e.exercise.name); // ACSM 2-3 min
        }
      }
    });

    test('the result converts straight into a Workout', () {
      final result = engine.recommendWorkout(
        profile: _profile(ExperienceLevel.intermediate),
        setup: _setup(),
      );
      final workout = result.toWorkout(name: 'Recommended');
      expect(workout.name, 'Recommended');
      expect(workout.exercises.length, result.exercises.length);
      expect(workout.totalSets, greaterThan(0));
      // Planned exercises point at the library, as everywhere else.
      for (final planned in workout.exercises) {
        expect(ExerciseLibrary.byId(planned.exerciseId), isNotNull);
      }
    });

    test('an empty pool says so instead of returning nothing silently', () {
      final result = engine.recommendWorkout(
        profile: _profile(ExperienceLevel.intermediate),
        setup: _setup(),
        pool: const [],
      );
      expect(result.isEmpty, isTrue);
      expect(result.note, 'There are no exercises to choose from.');
    });

    test('impossible equipment is explained', () {
      final result = engine.recommendWorkout(
        profile: _profile(ExperienceLevel.intermediate),
        setup: _setup(
          equipment: const [EquipmentItem.smithMachine],
          // Traps are only trained by shrugs, so nothing survives a
          // smith-machine-only setup. Chest would: a push-up needs nothing.
          muscles: [MuscleGroup.traps],
        ),
      );
      expect(result.isEmpty, isTrue);
      expect(result.note, contains('equipment'));
    });

    test('too few muscles is explained', () {
      final result = engine.recommendWorkout(
        profile: _profile(ExperienceLevel.beginner),
        setup: _setup(muscles: [MuscleGroup.chest]),
      );
      // A few chest exercises exist, but not a whole session's worth.
      expect(result.note, isNotNull);
      expect(result.exercises, isNotEmpty);
    });

    test('a beginner never receives an advanced or complex exercise', () {
      final result = engine.recommendWorkout(
        profile: _profile(ExperienceLevel.beginner),
        setup: _setup(duration: SessionDuration.min90Plus),
      );
      expect(result.exercises, isNotEmpty);
      for (final e in result.exercises) {
        expect(
          e.exercise.experienceLevel,
          ExperienceLevel.beginner,
          reason: e.exercise.name,
        );
        expect(
          e.exercise.complexity,
          isNot(Complexity.high),
          reason: e.exercise.name,
        );
      }
    });

    test('every recommendation can explain itself', () {
      final result = engine.recommendWorkout(
        profile: _profile(ExperienceLevel.intermediate),
        setup: _setup(),
      );
      for (final e in result.exercises) {
        expect(e.explanation, isNotEmpty);
        expect(e.explanation, startsWith('Recommended'));
      }
    });
  });
}
