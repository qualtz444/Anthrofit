import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/content/app_content.dart';
import 'package:anthrofit/content/content_models.dart';
import 'package:anthrofit/data/exercise_library.dart';
import 'package:anthrofit/data/ready_made_programs.dart';
import 'package:anthrofit/data/workout_templates.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/recommendation/exercise_scorer.dart';
import 'package:anthrofit/recommendation/proportion_rules.dart';
import 'package:anthrofit/recommendation/recommendation_weights.dart';

// Test fixtures only, not reference values.
Exercise _exercise(
  String id, {
  List<EquipmentItem> equipment = const [EquipmentItem.dumbbell],
  List<String> extra = const [],
  MovementPattern pattern = MovementPattern.horizontalPush,
}) => Exercise(
  id: id,
  name: id,
  exerciseType: ExerciseType.freeWeight,
  movementPattern: pattern,
  primaryMuscles: const [MuscleGroup.chest],
  equipment: equipment,
  extraEquipment: extra,
  experienceLevel: ExperienceLevel.beginner,
  complexity: Complexity.low,
);

ProgramSetup _setup({List<String> extra = const []}) => ProgramSetup(
  goal: TrainingGoal.buildMuscle,
  sessionDuration: SessionDuration.min60,
  focus: TrainingFocus.fullBody,
  muscles: const [MuscleGroup.chest],
  equipmentCategories: const {EquipmentCategory.home},
  equipment: const [EquipmentItem.dumbbell],
  extraEquipment: extra,
);

ContentSnapshot _withConfig(ContentConfig config) =>
    ContentSnapshot(config: config);

void main() {
  tearDown(() {
    AppContent.reset();
    ExerciseLibrary.clear();
  });

  group('content JSON', () {
    test('a full snapshot survives saving and reading back', () {
      final snapshot = ContentSnapshot(
        config: ContentConfig(
          weights: const RecommendationWeights(goalRelevance: 5),
          thresholds: const {
            RatioKeys.femurToTorso: ThresholdOverride(
              low: 0.7,
              high: 0.8,
              source: 'test fixture',
            ),
          },
          templateExercises: const {
            'push': ['a', 'b'],
          },
          readyMade: const [
            ReadyMadeProgram(
              id: 'r1',
              name: 'R1',
              summary: 's',
              template: ProgramTemplate.upperLower,
              goal: TrainingGoal.getStronger,
              experience: ExperienceLevel.advanced,
              days: [Weekday.monday, Weekday.thursday],
            ),
          ],
          goalFit: const {
            'a': {'getStronger': 0.4},
          },
          proportionRules: const [
            AdminProportionRule(
              id: 'rule1',
              name: 'Rule',
              ratioKey: RatioKeys.armToTorso,
              whenClass: ProportionClass.low,
              scoreDelta: 0.5,
              exerciseIds: ['a'],
              rationale: 'test fixture',
            ),
          ],
          disabledRules: const {'Long femur, barbell squat'},
        ),
        equipment: const [
          EquipmentDef(
            id: 'sandbag',
            label: 'Sandbag',
            categories: {EquipmentCategory.home},
          ),
        ],
        exercises: [
          ExerciseOverride(_exercise('a', extra: ['sandbag']), hidden: true),
        ],
      );

      final back = ContentSnapshot.fromJson(
        jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>,
      );

      expect(back.config.weights!.goalRelevance, 5);
      expect(
        back.config.weights!.primaryMuscleMatch,
        RecommendationWeights.standard.primaryMuscleMatch,
      );
      expect(back.config.thresholds[RatioKeys.femurToTorso]!.high, 0.8);
      expect(back.config.templateExercises['push'], ['a', 'b']);
      expect(back.config.readyMade!.single.days, [
        Weekday.monday,
        Weekday.thursday,
      ]);
      expect(back.config.goalFit['a']!['getStronger'], 0.4);
      expect(back.config.proportionRules.single.whenClass, ProportionClass.low);
      expect(back.config.disabledRules, {'Long femur, barbell squat'});
      expect(back.equipment.single.categories, {EquipmentCategory.home});
      expect(back.exercises.single.hidden, isTrue);
      expect(back.exercises.single.exercise.extraEquipment, ['sandbag']);
    });

    test('a cut-off without a source is not accepted', () {
      expect(
        ThresholdOverride.fromJson({'low': 0.7, 'high': 0.8, 'source': ''}),
        isNull,
      );
      expect(
        ThresholdOverride.fromJson({'low': 0.9, 'high': 0.8, 'source': 'x'}),
        isNull,
      );
    });

    test('an empty config means every built-in value', () {
      AppContent.apply(ContentSnapshot.empty);
      expect(identical(AppContent.weights, RecommendationWeights.standard), isTrue);
      expect(
        identical(AppContent.thresholds, ProportionThresholds.participants),
        isTrue,
      );
      expect(identical(AppContent.proportionRules, kProportionRules), isTrue);
      expect(readyMadePrograms(), kReadyMadePrograms);
      expect(
        WorkoutTemplate.push.currentExerciseIds,
        WorkoutTemplate.push.exerciseIds,
      );
    });
  });

  group('the app uses admin content', () {
    test('a replaced cut-off keeps the other built-in ones', () {
      AppContent.apply(
        _withConfig(
          const ContentConfig(
            thresholds: {
              RatioKeys.femurToTorso: ThresholdOverride(
                low: 0.5,
                high: 0.6,
                source: 'test fixture',
              ),
            },
          ),
        ),
      );
      final t = AppContent.thresholds.byRatio;
      expect(t[RatioKeys.femurToTorso]!.low, 0.5);
      expect(
        t[RatioKeys.armToTorso]!.low,
        ProportionThresholds.participants.byRatio[RatioKeys.armToTorso]!.low,
      );
    });

    test('templates and ready-made programs follow the admin', () {
      AppContent.apply(
        _withConfig(
          const ContentConfig(
            templateExercises: {
              'push': ['x'],
            },
            readyMade: [],
          ),
        ),
      );
      expect(WorkoutTemplate.push.currentExerciseIds, ['x']);
      expect(
        WorkoutTemplate.pull.currentExerciseIds,
        WorkoutTemplate.pull.exerciseIds,
      );
      expect(readyMadePrograms(), isEmpty);
    });

    test('a built-in rule can be switched off and an admin rule added', () {
      AppContent.apply(
        _withConfig(
          const ContentConfig(
            disabledRules: {'Long femur, barbell squat'},
            proportionRules: [
              AdminProportionRule(
                id: 'r',
                name: 'Admin rule',
                ratioKey: RatioKeys.armToTorso,
                whenClass: ProportionClass.high,
                scoreDelta: 1,
                exerciseIds: ['a'],
                rationale: 'test fixture',
              ),
            ],
          ),
        ),
      );
      final names = AppContent.proportionRules.map((r) => r.name).toList();
      expect(names, isNot(contains('Long femur, barbell squat')));
      expect(names, contains('Admin rule'));
      final admin = AppContent.proportionRules.last;
      expect(admin.appliesTo(_exercise('a')), isTrue);
      expect(admin.appliesTo(_exercise('b')), isFalse);
    });

    test('admin equipment must be available for an exercise to be offered', () {
      final scorer = ExerciseScorer(
        setup: _setup(),
        experience: ExperienceLevel.beginner,
      );
      expect(
        scorer.reject(_exercise('needs_sandbag', extra: ['sandbag'])),
        RejectionReason.equipment,
      );
      final withSandbag = ExerciseScorer(
        setup: _setup(extra: ['sandbag']),
        experience: ExperienceLevel.beginner,
      );
      expect(
        withSandbag.reject(_exercise('needs_sandbag', extra: ['sandbag'])),
        isNull,
      );
    });

    test('admin weights and goal fit change the score', () {
      final e = _exercise('a');
      final scorer = ExerciseScorer(
        setup: _setup(),
        experience: ExperienceLevel.beginner,
      );
      final before = scorer.score(e).score;

      AppContent.apply(
        _withConfig(
          const ContentConfig(
            weights: RecommendationWeights(goalRelevance: 0),
          ),
        ),
      );
      final noGoal = scorer.score(e).score;
      expect(
        noGoal,
        closeTo(
          before -
              builtInGoalFit(e, TrainingGoal.buildMuscle) *
                  RecommendationWeights.standard.goalRelevance,
          1e-9,
        ),
      );

      AppContent.apply(
        _withConfig(
          const ContentConfig(
            goalFit: {
              'a': {'buildMuscle': 0},
            },
          ),
        ),
      );
      expect(
        scorer.score(e).score,
        closeTo(noGoal, 1e-9),
        reason: 'a goal fit of 0 removes the goal points',
      );
    });

    test('weights passed in explicitly are used as given', () {
      AppContent.apply(
        _withConfig(
          const ContentConfig(
            weights: RecommendationWeights(goalRelevance: 0),
          ),
        ),
      );
      // Not equal to the built-in weights: a const with the same values
      // would be the very same object, which stands for "the admin's".
      const own = RecommendationWeights(goalRelevance: 25);
      final e = _exercise('a');
      final withOwn = ExerciseScorer(
        setup: _setup(),
        experience: ExperienceLevel.beginner,
        weights: own,
      ).score(e).score;
      final withAdmin = ExerciseScorer(
        setup: _setup(),
        experience: ExperienceLevel.beginner,
      ).score(e).score;
      expect(withOwn, greaterThan(withAdmin));
    });
  });

  group('catalogue merge', () {
    test('replaces, adds and hides', () {
      final builtIn = [_exercise('a'), _exercise('b')];
      final merged = mergeCatalog(builtIn, [
        ExerciseOverride(_exercise('a').copyWith(name: 'A edited')),
        ExerciseOverride(_exercise('c')),
        ExerciseOverride(_exercise('b'), hidden: true),
      ]);
      expect(merged.exercises.map((e) => e.id), ['a', 'b', 'c']);
      expect(merged.exercises.first.name, 'A edited');
      expect(merged.hidden, {'b'});

      ExerciseLibrary.applyBuiltIn(merged.exercises, hidden: merged.hidden);
      expect(ExerciseLibrary.all.map((e) => e.id), ['a', 'c']);
      expect(
        ExerciseLibrary.byId('b'),
        isNotNull,
        reason: 'old programs still find a hidden exercise',
      );
    });
  });
}
