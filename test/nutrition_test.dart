import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/data/profile_repository.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/nutrition/body_fat_category.dart';
import 'package:anthrofit/nutrition/nutrition_targets.dart';
import 'package:anthrofit/screens/nutrition/nutrition_targets_summary.dart';
import 'package:anthrofit/screens/nutrition/sample_day_screen.dart';
import 'package:anthrofit/screens/nutrition/nutrition_targets_screen.dart';
import 'package:anthrofit/state/profile_controller.dart';
import 'package:anthrofit/state/profile_scope.dart';

import 'test_helpers.dart';

CompositionRecord _estimate(double bodyFatPct) => CompositionRecord(
  id: 'estimate-$bodyFatPct',
  takenAt: DateTime(2026, 10, 1),
  weightKg: 70,
  bodyFatPct: bodyFatPct,
  bodyFatLow: bodyFatPct - 3,
  bodyFatHigh: bodyFatPct + 3,
  leanLimbKg: 24,
  fatFreeMassKg: 70 * (1 - bodyFatPct / 100),
  fatMassKg: 70 * bodyFatPct / 100,
  waistCm: 80,
  chestCm: 95,
  hipCm: 95,
  thighCm: 55,
  upperArmCm: 30,
  frameCount: 3,
);

UserProfile _profile({
  Sex sex = Sex.male,
  int age = 25,
  double weightKg = 70,
  TrainingGoal goal = TrainingGoal.buildMuscle,
  ExperienceLevel experience = ExperienceLevel.beginner,
  ActivityLevel? activity = ActivityLevel.sedentaryOrLight,
  List<CompositionRecord> compositions = const [],
}) => sampleProfile.copyWith(
  sex: sex,
  age: age,
  weightKg: weightKg,
  goal: goal,
  experience: experience,
  activityLevel: activity,
  compositionLog: compositions,
);

// sampleProfile is 170 cm.
const double _mifflinMale25 = 10 * 70 + 6.25 * 170 - 5 * 25 + 5;

void main() {
  group('equations', () {
    test('Mifflin-St Jeor', () {
      expect(
        mifflinStJeorKcal(isMale: true, age: 25, heightCm: 170, weightKg: 70),
        closeTo(_mifflinMale25, 1e-9),
      );
      expect(
        mifflinStJeorKcal(isMale: false, age: 25, heightCm: 170, weightKg: 70),
        closeTo(_mifflinMale25 - 166, 1e-9),
      );
    });

    test('Katch-McArdle', () {
      expect(katchMcArdleKcal(60), closeTo(370 + 21.6 * 60, 1e-9));
    });
  });

  group('ACE body fat categories', () {
    test('each band starts at its published lower bound', () {
      expect(bodyFatCategory(5.9, isMale: true), BodyFatCategory.essential);
      expect(bodyFatCategory(13.5, isMale: true), BodyFatCategory.athletes);
      expect(bodyFatCategory(14, isMale: true), BodyFatCategory.fitness);
      expect(bodyFatCategory(24.9, isMale: true), BodyFatCategory.average);
      expect(bodyFatCategory(25, isMale: true), BodyFatCategory.obese);
      expect(bodyFatCategory(31.9, isMale: false), BodyFatCategory.average);
      expect(bodyFatCategory(32, isMale: false), BodyFatCategory.obese);
    });

    test('suggested goals', () {
      expect(suggestedGoalFor(BodyFatCategory.obese), TrainingGoal.loseFat);
      expect(
        suggestedGoalFor(BodyFatCategory.average),
        TrainingGoal.improveBodyComposition,
      );
      expect(
        suggestedGoalFor(BodyFatCategory.fitness),
        TrainingGoal.buildMuscle,
      );
    });
  });

  group('targets without a body composition estimate', () {
    test('Mifflin-St Jeor times the PAL range', () {
      final t = nutritionTargetsFor(_profile())!;
      expect(t.bmrMethod, BmrMethod.mifflinStJeor);
      expect(t.maintenanceKcalLow, closeTo(_mifflinMale25 * 1.40, 1e-9));
      expect(t.maintenanceKcalHigh, closeTo(_mifflinMale25 * 1.69, 1e-9));
    });

    test('building muscle: 10-20% above maintenance, 1.4-2.0 g/kg', () {
      final t = nutritionTargetsFor(_profile())!;
      expect(t.advice, EnergyAdvice.surplus);
      expect(t.targetKcalLow, closeTo(t.maintenanceKcalLow * 1.10, 1e-9));
      expect(t.targetKcalHigh, closeTo(t.maintenanceKcalHigh * 1.20, 1e-9));
      expect(t.proteinGLow, closeTo(98, 1e-9));
      expect(t.proteinGHigh, closeTo(140, 1e-9));
    });

    test('advanced lifters stay at the lower end of the surplus', () {
      final t = nutritionTargetsFor(
        _profile(experience: ExperienceLevel.advanced),
      )!;
      expect(t.targetKcalHigh, closeTo(t.maintenanceKcalHigh * 1.10, 1e-9));
    });

    test('losing fat: a 500-750 kcal deficit', () {
      final t = nutritionTargetsFor(_profile(goal: TrainingGoal.loseFat))!;
      expect(t.advice, EnergyAdvice.deficit);
      expect(t.deficitBasis, DeficitBasis.fixed);
      expect(t.targetKcalLow, closeTo(t.maintenanceKcalLow - 750, 1e-9));
      expect(t.targetKcalHigh, closeTo(t.maintenanceKcalHigh - 500, 1e-9));
      expect(t.proteinGLow, closeTo(112, 1e-9));
      expect(t.proteinGHigh, closeTo(168, 1e-9));
    });

    test('macros add back up to the middle of the calorie range', () {
      final t = nutritionTargetsFor(_profile())!;
      final kcal = (t.targetKcalLow + t.targetKcalHigh) / 2;
      final protein = (t.proteinGLow + t.proteinGHigh) / 2;
      final fat = (t.fatGLow + t.fatGHigh) / 2;
      expect(t.fatGLow, closeTo(0.20 * kcal / 9, 1e-9));
      expect(t.fatGHigh, closeTo(0.35 * kcal / 9, 1e-9));
      expect(protein * 4 + fat * 9 + t.carbsG * 4, closeTo(kcal, 1e-6));
    });
  });

  group('targets with a body composition estimate', () {
    test('Katch-McArdle from lean mass, using the newest estimate', () {
      final t = nutritionTargetsFor(
        _profile(compositions: [_estimate(30), _estimate(20)]),
      )!;
      expect(t.bmrMethod, BmrMethod.katchMcArdle);
      expect(t.bmrKcal, closeTo(370 + 21.6 * 56, 1e-9));
      // ACE, men: Average is 18-24%, so 20% is Average (Fitness is 14-17%).
      expect(t.category, BodyFatCategory.average);
    });

    test('leaner and losing fat: the slower, rate-based deficit', () {
      final t = nutritionTargetsFor(
        _profile(goal: TrainingGoal.loseFat, compositions: [_estimate(12)]),
      )!;
      expect(t.deficitBasis, DeficitBasis.rate);
      final small = 70 * 0.005 * kKcalPerKgLost / 7;
      final large = 70 * 0.01 * kKcalPerKgLost / 7;
      expect(t.targetKcalLow, closeTo(t.maintenanceKcalLow - large, 1e-9));
      expect(t.targetKcalHigh, closeTo(t.maintenanceKcalHigh - small, 1e-9));
      // 2.3-3.1 g per kg of fat-free mass (70 kg x 88%).
      expect(t.proteinFromLeanMass, isTrue);
      expect(t.proteinGLow, closeTo(2.3 * 61.6, 1e-9));
      expect(t.proteinGHigh, closeTo(3.1 * 61.6, 1e-9));
    });

    test('higher body fat and losing fat: the 500-750 kcal deficit', () {
      final t = nutritionTargetsFor(
        _profile(goal: TrainingGoal.loseFat, compositions: [_estimate(28)]),
      )!;
      expect(t.category, BodyFatCategory.obese);
      expect(t.deficitBasis, DeficitBasis.fixed);
    });

    test('works without a sex once there is an estimate', () {
      final none = _profile(sex: Sex.preferNotToSay);
      expect(nutritionTargetsFor(none), isNull);
      final withEstimate = _profile(
        sex: Sex.preferNotToSay,
        compositions: [_estimate(20)],
      );
      final t = nutritionTargetsFor(withEstimate)!;
      expect(t.bmrMethod, BmrMethod.katchMcArdle);
      expect(t.category, isNull);
    });
  });

  group('blockers', () {
    test('adults only, and the activity question first', () {
      expect(nutritionTargetsFor(_profile(age: 17)), isNull);
      final unanswered = sampleProfile.copyWith(sex: Sex.male);
      expect(nutritionTargetsFor(unanswered), isNull);
      expect(nutritionBlocker(unanswered), 'Choose your daily activity.');
    });
  });

  group('nutrition presentation', () {
    testWidgets('daily energy and macros are shown as a visual summary', (
      tester,
    ) async {
      final targets = nutritionTargetsFor(_profile())!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: NutritionTargetsSummary(targets: targets),
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('daily-energy-target')), findsOneWidget);
      expect(find.text('DAILY MACROS'), findsOneWidget);
      expect(find.text('Protein'), findsWidgets);
      expect(find.text('Carbs'), findsOneWidget);
      expect(find.text('Fat'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('example meals use compact plate-group cards on a phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SampleDayView(profile: _profile(), dayIndex: 1),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('example-label')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('sample-meal-breakfast')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('sample-meal-lunch')), findsOneWidget);
      expect(find.byKey(const ValueKey('sample-meal-dinner')), findsOneWidget);
      expect(find.text('½ plants'), findsWidgets);
      expect(find.text('⅓ staples'), findsWidgets);
      expect(find.text('⅙ protein'), findsWidgets);
      expect(find.text('Keep in mind'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('profile', () {
    test('activity level and estimates survive a save and load', () {
      final json = _profile(
        activity: ActivityLevel.vigorous,
        compositions: [_estimate(20)],
      ).toJson();
      final back = UserProfile.fromJson(json);
      expect(back.activityLevel, ActivityLevel.vigorous);
      expect(back.compositionLog.single.bodyFatPct, 20);
      expect(back.latestComposition!.frameCount, 3);
    });

    test('profiles saved before these existed read as empty', () {
      final json = sampleProfile.toJson()
        ..remove('activityLevel')
        ..remove('compositionLog');
      final back = UserProfile.fromJson(json);
      expect(back.activityLevel, isNull);
      expect(back.compositionLog, isEmpty);
    });
  });

  testWidgets('choosing an activity saves it and shows the targets', (
    tester,
  ) async {
    seedNoProfile();
    final controller = ProfileController(ProfileRepository());
    await controller.save(sampleProfile.copyWith(sex: Sex.female));

    await tester.pumpWidget(
      ProfileScope(
        controller: controller,
        child: const MaterialApp(home: NutritionTargetsScreen()),
      ),
    );

    expect(find.byKey(const ValueKey('nutrition-blocker')), findsOneWidget);
    expect(find.text('Choose your daily activity.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('activity-active')));
    await tester.pumpAndSettle();

    expect(controller.profile!.activityLevel, ActivityLevel.active);
    expect(find.byKey(const ValueKey('nutrition-blocker')), findsNothing);
    expect(find.text('DAILY MACROS'), findsOneWidget);
    expect(find.text('About these estimates'), findsNothing);
    expect(find.byKey(const ValueKey('simple-plate-guide')), findsOneWidget);
    final plantsSize = tester.getSize(
      find.byKey(const ValueKey('plate-part-½')),
    );
    final proteinSize = tester.getSize(
      find.byKey(const ValueKey('plate-part-⅙')),
    );
    expect(proteinSize.width, closeTo(plantsSize.width, 0.1));
    expect(find.text('Plants'), findsOneWidget);
    expect(find.text('Staples'), findsOneWidget);
    expect(find.text('Protein'), findsWidgets);
    final details = find.text('Goal & calculation');
    await tester.ensureVisible(details);
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.text('Maintenance estimate'), findsOneWidget);
    expect(find.text('Goal adjustment'), findsOneWidget);
    expect(find.text('Macro basis'), findsOneWidget);
  });
}
