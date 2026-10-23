import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/coaching/limitation_check.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/nutrition/meal_plan.dart';

import 'test_helpers.dart';

const _squat = Exercise(
  id: 'sq',
  name: 'Squat',
  exerciseType: ExerciseType.freeWeight,
  movementPattern: MovementPattern.kneeDominant,
  primaryMuscles: [MuscleGroup.quads, MuscleGroup.glutes],
  equipment: [EquipmentItem.barbell],
  experienceLevel: ExperienceLevel.beginner,
  complexity: Complexity.moderate,
);

const _curl = Exercise(
  id: 'curl',
  name: 'Curl',
  exerciseType: ExerciseType.freeWeight,
  movementPattern: MovementPattern.isolation,
  primaryMuscles: [MuscleGroup.biceps],
  equipment: [EquipmentItem.dumbbell],
  experienceLevel: ExperienceLevel.beginner,
  complexity: Complexity.low,
);

void main() {
  test('every time answer maps to a session length', () {
    expect(TimeBudget.min20to30.duration, SessionDuration.min30);
    expect(TimeBudget.notSure.duration, SessionDuration.min30);
    expect(TimeBudget.fromDuration(SessionDuration.min60), TimeBudget.min45to60);
  });

  test('every typical day maps to a FAO activity level', () {
    expect(DailyRoutine.mostlySitting.activityLevel,
        ActivityLevel.sedentaryOrLight);
    expect(DailyRoutine.demanding.activityLevel, ActivityLevel.vigorous);
  });

  test('the PAR-Q+ has seven questions and any YES is flagged', () {
    expect(kParqQuestions, hasLength(7));
    final none = sampleProfile.copyWith(
      parqAnswers: List.filled(7, false),
    );
    expect(none.parqAnyYes, isFalse);
    expect(none.copyWith(parqAnswers: [true, ...List.filled(6, false)])
        .parqAnyYes, isTrue);
    expect(sampleProfile.parqAnyYes, isFalse); // never answered
  });

  test('screening answers survive a save and load', () {
    final p = sampleProfile.copyWith(
      parqAnswers: [false, false, true, false, false, false, false],
      limitations: [LimitationArea.knee],
      limitationNote: 'Old ACL',
      dailyRoutine: DailyRoutine.onFeet,
      timeBudget: TimeBudget.notSure,
      dietPattern: DietPattern.noPork,
      foodAllergies: 'shrimp',
    );
    final back = UserProfile.fromJson(p.toJson());
    expect(back.parqAnswers, p.parqAnswers);
    expect(back.limitations, [LimitationArea.knee]);
    expect(back.limitationNote, 'Old ACL');
    expect(back.dailyRoutine, DailyRoutine.onFeet);
    expect(back.timeBudget, TimeBudget.notSure);
    expect(back.dietPattern, DietPattern.noPork);
    expect(back.foodAllergies, 'shrimp');
  });

  test('PAR-Q+ answers sort into follow-up and clearance-first', () {
    List<bool> yesAt(int i) => [for (var j = 0; j < 7; j++) j == i];
    expect(parqConcern(null), ParqConcern.none);
    expect(parqConcern(List.filled(7, false)), ParqConcern.none);
    expect(parqConcern(yesAt(0)), ParqConcern.followUp); // heart / BP
    expect(parqConcern(yesAt(5)), ParqConcern.followUp); // bone or joint
    expect(parqConcern(yesAt(1)), ParqConcern.clearanceFirst); // chest pain
    expect(parqConcern(yesAt(2)), ParqConcern.clearanceFirst); // dizziness
    expect(parqConcern(yesAt(6)), ParqConcern.clearanceFirst); // supervised
    final p = sampleProfile.copyWith(parqAnswers: yesAt(1));
    expect(p.needsClearance, isTrue);
    expect(p.copyWith(medicallyCleared: true).needsClearance, isFalse);
    expect(
      UserProfile.fromJson(p.copyWith(medicallyCleared: true).toJson())
          .medicallyCleared,
      isTrue,
    );
  });

  test('a noted knee flags squats for review but not curls', () {
    expect(limitationCaution(_squat, [LimitationArea.knee]), contains('Flagged for review'));
    expect(limitationCaution(_curl, [LimitationArea.knee]), isNull);
    expect(limitationCaution(_curl, [LimitationArea.wristElbow]), isNotNull);
    expect(limitationCaution(_squat, const []), isNull);
  });

  test('a knee note keeps squats when no quad exercise avoids the knee',
      () {
    const legExtension = Exercise(
      id: 'le',
      name: 'Leg extension',
      exerciseType: ExerciseType.machine,
      movementPattern: MovementPattern.isolation,
      primaryMuscles: [MuscleGroup.quads],
      equipment: [EquipmentItem.machine],
      experienceLevel: ExperienceLevel.beginner,
      complexity: Complexity.low,
    );
    // Leg extension trains quads, so it also counts as loading the knee:
    // nothing safe for quads, so the squat stays.
    expect(
      avoidLimitations([_squat, legExtension, _curl], [LimitationArea.knee]),
      contains(_squat),
    );
    // Wrist note: the curl is the only biceps exercise, so it stays too.
    expect(avoidLimitations([_curl], [LimitationArea.wristElbow]), [_curl]);
    expect(avoidLimitations([_squat, _curl], const []), hasLength(2));
    expect(limitationProgramNote(const []), isNull);
    expect(limitationProgramNote([LimitationArea.knee]),
        contains('not a clinical judgment'));
  });

  test('a lower back note leaves out the deadlift when a leg curl is available',
      () {
    const rdl = Exercise(
      id: 'rdl',
      name: 'Romanian deadlift',
      exerciseType: ExerciseType.freeWeight,
      movementPattern: MovementPattern.hipDominant,
      primaryMuscles: [MuscleGroup.hamstrings],
      equipment: [EquipmentItem.barbell],
      experienceLevel: ExperienceLevel.beginner,
      complexity: Complexity.moderate,
    );
    const legCurl = Exercise(
      id: 'lc',
      name: 'Leg curl',
      exerciseType: ExerciseType.machine,
      movementPattern: MovementPattern.isolation,
      primaryMuscles: [MuscleGroup.hamstrings],
      equipment: [EquipmentItem.machine],
      experienceLevel: ExperienceLevel.beginner,
      complexity: Complexity.low,
    );
    expect(
      avoidLimitations([rdl, legCurl], [LimitationArea.lowerBack]),
      [legCurl],
    );
  });

  group('sample day of meals', () {
    List<Food> allFoods(UserProfile p) => [
      for (var d = 0; d < 10; d++)
        for (final m in sampleDay(p, d)) ...m.foods.values,
    ];

    test('three meals, each with every part of the plate', () {
      final day = sampleDay(sampleProfile, 0);
      expect(day.map((m) => m.name), ['Breakfast', 'Lunch', 'Dinner']);
      for (final m in day) {
        expect(m.foods.keys, PlateGroup.values);
      }
    });

    test('no pork means no pork', () {
      final p = sampleProfile.copyWith(dietPattern: DietPattern.noPork);
      expect(allFoods(p).any((f) => f.tags.contains(FoodTag.pork)), isFalse);
    });

    test('vegetarian: no meat or fish, eggs allowed', () {
      final p = sampleProfile.copyWith(dietPattern: DietPattern.vegetarian);
      final foods = allFoods(p);
      expect(
        foods.any((f) => f.tags.any({
              FoodTag.pork,
              FoodTag.beef,
              FoodTag.chicken,
              FoodTag.fish,
              FoodTag.shellfish,
            }.contains)),
        isFalse,
      );
      expect(foods.any((f) => f.tags.contains(FoodTag.egg)), isTrue);
    });

    test('a shrimp allergy removes shellfish, a named food is removed', () {
      final p = sampleProfile.copyWith(foodAllergies: 'shrimp, mango');
      final names = allFoods(p).map((f) => f.name).toSet();
      expect(names, isNot(contains('Sinigang na hipon')));
      expect(names, isNot(contains('Mango')));
      expect(names, contains('Banana'));
    });
  });
}
