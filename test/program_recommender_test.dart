import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/data/exercise_library.dart';
import 'package:anthrofit/data/setup_options.dart';
import 'package:anthrofit/data/workout_templates.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/recommendation/program_recommender.dart';
import 'package:anthrofit/recommendation/proportion_rules.dart';

import 'test_helpers.dart';

ProgramSetup _setup({
  TrainingGoal goal = TrainingGoal.buildMuscle,
  SessionDuration duration = SessionDuration.min60,
  TrainingFocus focus = TrainingFocus.fullBody,
  List<MuscleGroup>? muscles,
  List<EquipmentItem>? equipment,
}) => ProgramSetup(
  goal: goal,
  sessionDuration: duration,
  focus: focus,
  muscles: muscles ?? musclesForFocus(focus),
  equipmentCategories: const {EquipmentCategory.commercialGym},
  equipment: equipment ?? EquipmentItem.values,
);

UserProfile _profile({
  ExperienceLevel experience = ExperienceLevel.intermediate,
  TrainingFrequency days = TrainingFrequency.four,
}) => sampleProfile.copyWith(experience: experience, trainingFrequency: days);

const _recommender = ProgramRecommender();

void main() {
  useExerciseLibrary();

  // ---------------------------------------------------------------------
  group('program shape', () {
    test('the split follows how many days a week the user trains', () {
      expect(
        splitFor(days: 2, focus: TrainingFocus.fullBody),
        ProgramTemplate.fullBody,
      );
      expect(
        splitFor(days: 3, focus: TrainingFocus.fullBody),
        ProgramTemplate.fullBody,
      );
      expect(
        splitFor(days: 4, focus: TrainingFocus.fullBody),
        ProgramTemplate.upperLower,
      );
      expect(
        splitFor(days: 6, focus: TrainingFocus.fullBody),
        ProgramTemplate.pushPullLegs,
      );
      // A narrowed focus overrides it: a lower-body program is not a split.
      expect(
        splitFor(days: 6, focus: TrainingFocus.lowerBody),
        ProgramTemplate.fullBody,
      );
    });

    test('four days gives an upper/lower program on four weekdays', () {
      final result = _recommender.recommend(
        profile: _profile(days: TrainingFrequency.four),
        setup: _setup(),
      );
      expect(result.workouts.map((w) => w.workout.name).toList(), [
        'Upper',
        'Lower',
      ]);
      expect(result.program.schedule.length, 4);
      expect(result.program.trainingDays.length, 4);
      // Each scheduled day points at one of its own workouts.
      for (final slot in result.program.schedule) {
        expect(result.program.workoutById(slot.workoutId), isNotNull);
      }
    });

    test('six days gives push, pull and legs, each twice', () {
      final result = _recommender.recommend(
        profile: _profile(days: TrainingFrequency.sixPlus),
        setup: _setup(),
      );
      expect(result.workouts.map((w) => w.workout.name).toList(), [
        'Push',
        'Pull',
        'Legs',
      ]);
      expect(result.program.schedule.length, 6);
      expect(result.program.schedule.map((s) => s.workoutId).toSet().length, 3);
    });

    test('it is a normal program, savable like any other', () {
      final result = _recommender.recommend(
        profile: _profile(),
        setup: _setup(),
      );
      final program = result.program;
      expect(program.id, isNotEmpty);
      expect(program.archived, isFalse);
      expect(program.setup, isNotNull); // the answers are kept on it
      expect(program.goal, TrainingGoal.buildMuscle);
      for (final workout in program.workouts) {
        expect(workout.exercises, isNotEmpty, reason: workout.name);
      }
    });

    test('the same inputs always give the same program', () {
      List<String> idsFor() => _recommender
          .recommend(profile: _profile(), setup: _setup())
          .workouts
          .expand((w) => w.exercises.map((e) => e.exercise.id))
          .toList();
      expect(idsFor(), idsFor());
    });
  });

  // ---------------------------------------------------------------------
  group('what the user asked for', () {
    test('the goal changes the prescription', () {
      PlannedSet firstSet(TrainingGoal goal) => _recommender
          .recommend(
            profile: _profile(experience: ExperienceLevel.advanced),
            setup: _setup(goal: goal),
          )
          .workouts
          .first
          .exercises
          .first
          .planned
          .plannedSets
          .first;

      final strength = firstSet(TrainingGoal.getStronger);
      final muscle = firstSet(TrainingGoal.buildMuscle);
      expect(strength.targetRepMax, lessThan(muscle.targetRepMax!));
      expect(strength.restSeconds, greaterThan(muscle.restSeconds));
    });

    test('a narrowed focus shapes the whole program', () {
      final result = _recommender.recommend(
        profile: _profile(days: TrainingFrequency.four),
        setup: _setup(focus: TrainingFocus.lowerBody),
      );
      // One kind of session, and nothing in it trains the upper body.
      expect(result.workouts.length, 1);
      for (final session in result.workouts) {
        for (final e in session.exercises) {
          for (final muscle in e.exercise.primaryMuscles) {
            expect(
              muscle.region,
              isNot(MuscleRegion.upper),
              reason: e.exercise.name,
            );
          }
        }
      }
    });

    test(
      'singling out muscles makes them the priority, and pulls them early',
      () {
        final setup = _setup(
          focus: TrainingFocus.pull,
          muscles: const [MuscleGroup.lats],
        );
        expect(priorityMusclesFor(setup), [MuscleGroup.lats]);

        final result = _recommender.recommend(
          profile: _profile(),
          setup: setup,
        );
        final first = result.workouts.first.exercises.first;
        expect(first.exercise.primaryMuscles, contains(MuscleGroup.lats));
        expect(result.priorityMuscles, [MuscleGroup.lats]);
      },
    );

    test('a whole focus left alone means no particular priority', () {
      expect(
        priorityMusclesFor(_setup(focus: TrainingFocus.upperBody)),
        isEmpty,
      );
      expect(priorityMusclesFor(_setup()), isEmpty);
    });

    test('equipment the user lacks is never recommended', () {
      final result = _recommender.recommend(
        profile: _profile(),
        setup: _setup(equipment: const [EquipmentItem.dumbbell]),
      );
      for (final session in result.workouts) {
        for (final e in session.exercises) {
          for (final item in e.exercise.equipment) {
            expect(
              item == EquipmentItem.none || item == EquipmentItem.dumbbell,
              isTrue,
              reason: '${e.exercise.name} needs ${item.label}',
            );
          }
        }
      }
    });

    test('a beginner is never given advanced or complex work', () {
      final result = _recommender.recommend(
        profile: _profile(experience: ExperienceLevel.beginner),
        setup: _setup(),
      );
      expect(result.isEmpty, isFalse);
      for (final session in result.workouts) {
        for (final e in session.exercises) {
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
      }
    });

    test('a shorter session gets fewer exercises', () {
      int count(SessionDuration duration) => _recommender
          .recommend(
            profile: _profile(),
            setup: _setup(duration: duration),
          )
          .workouts
          .first
          .exercises
          .length;
      expect(
        count(SessionDuration.min15),
        lessThan(count(SessionDuration.min90Plus)),
      );
      expect(count(SessionDuration.min15), greaterThanOrEqualTo(1));
    });

    test('it only ever uses exercises that exist in the catalogue', () {
      final result = _recommender.recommend(
        profile: _profile(),
        setup: _setup(),
      );
      for (final session in result.workouts) {
        for (final planned in session.workout.exercises) {
          expect(ExerciseLibrary.byId(planned.exerciseId), isNotNull);
        }
      }
    });
  });

  // ---------------------------------------------------------------------
  group('proportions', () {
    Measurement scan(Map<String, double> ratios) =>
        Measurement.fromNative({'ratios': ratios});

    test(
      'with no thresholds, nothing uses proportions, and that is reported',
      () {
        final withScan = _recommender.recommend(
          profile: _profile(),
          setup: _setup(),
          measurement: scan({RatioKeys.femurToTorso: 1.30}),
        );
        final without = _recommender.recommend(
          profile: _profile(),
          setup: _setup(),
        );

        expect(withScan.usedProportions, isFalse);
        expect(without.usedProportions, isFalse);
        // And the two programs are identical, because nothing was applied.
        expect(
          withScan.workouts.expand(
            (w) => w.exercises.map((e) => e.exercise.id),
          ),
          without.workouts.expand((w) => w.exercises.map((e) => e.exercise.id)),
        );
      },
    );

    test('no scan at all works exactly the same', () {
      final result = _recommender.recommend(
        profile: _profile(),
        setup: _setup(),
      );
      expect(result.isEmpty, isFalse);
      expect(result.usedProportions, isFalse);
      for (final session in result.workouts) {
        for (final e in session.exercises) {
          expect(e.setupCue, isNull);
        }
      }
    });

    test('with thresholds supplied, a scan does change the ranking', () {
      // Stand-ins for cut-offs someone would supply. Not reference values.
      const thresholds = ProportionThresholds({
        RatioKeys.femurToTorso: RatioThreshold(low: 0.95, high: 1.05),
      });
      const recommender = ProgramRecommender(thresholds: thresholds);

      final result = recommender.recommend(
        profile: _profile(experience: ExperienceLevel.advanced),
        setup: _setup(focus: TrainingFocus.lowerBody),
        measurement: scan({RatioKeys.femurToTorso: 1.30}),
      );
      expect(result.usedProportions, isTrue);
      // At least one exercise carries a setup cue it would not have had.
      final cues = result.workouts
          .expand((w) => w.exercises)
          .where((e) => e.setupCue != null);
      expect(cues, isNotEmpty);
    });
  });

  // ---------------------------------------------------------------------
  group('tags explain the result', () {
    test('a program is tagged with its goal, days and priorities', () {
      final result = _recommender.recommend(
        profile: _profile(days: TrainingFrequency.four),
        setup: _setup(
          focus: TrainingFocus.pull,
          muscles: const [MuscleGroup.lats],
        ),
      );
      final labels = result.tags.map((t) => t.label).toList();
      expect(labels, contains('Hypertrophy'));
      expect(labels, contains('4 days/week'));
      expect(labels, contains('Lats priority'));
      // Every tag says why, for a tooltip.
      expect(result.tags.every((t) => t.why.isNotEmpty), isTrue);
    });

    test('a session is tagged with what it trains', () {
      final result = _recommender.recommend(
        profile: _profile(days: TrainingFrequency.four),
        setup: _setup(),
      );
      final upper = result.workouts.first;
      final labels = upper.tags.map((t) => t.label).toList();
      expect(labels, contains('Upper body'));
      expect(labels, contains('60 min'));
    });

    test('an exercise is tagged with the reasons it was chosen', () {
      final result = _recommender.recommend(
        profile: _profile(experience: ExperienceLevel.beginner),
        setup: _setup(
          focus: TrainingFocus.pull,
          muscles: const [MuscleGroup.lats],
        ),
      );
      final first = result.workouts.first.exercises.first;
      final labels = first.tags.map((t) => t.label).toList();
      expect(labels, contains('Priority muscle'));
      expect(labels, contains('Lats emphasis'));
      expect(labels, contains('Equipment match'));
      expect(labels, contains('Beginner friendly'));
    });

    test('the same tags come out every time', () {
      List<String> tagsFor() => _recommender
          .recommend(profile: _profile(), setup: _setup())
          .tags
          .map((t) => t.label)
          .toList();
      expect(tagsFor(), tagsFor());
    });
  });

  // ---------------------------------------------------------------------
  group('when there is not enough to work with', () {
    test('impossible equipment gives an empty result that explains itself', () {
      final result = _recommender.recommend(
        profile: _profile(),
        setup: _setup(
          focus: TrainingFocus.chooseMuscles,
          muscles: const [MuscleGroup.traps],
          equipment: const [EquipmentItem.smithMachine],
        ),
      );
      expect(result.isEmpty, isTrue);
      expect(result.note, isNotNull);
    });

    test('a guest with no history and no scan still gets a program', () {
      final result = _recommender.recommend(
        profile: _profile(experience: ExperienceLevel.beginner),
        setup: _setup(),
      );
      expect(result.isEmpty, isFalse);
      expect(result.program.workouts.first.exercises, isNotEmpty);
    });
  });
}
