import '../models/models.dart';
import 'body_fat_category.dart';

// Every number in this file comes from a cited source. Where the app makes
// its own choice (which source applies when), it says so.
//
//   BMR, no scan     Mifflin-St Jeor (1990), Am J Clin Nutr 51:241-247:
//                    10 x kg + 6.25 x cm - 5 x age, +5 men, -161 women.
//   BMR, with scan   Katch-McArdle: 370 + 21.6 x fat-free mass (kg).
//   Activity         FAO/WHO/UNU (2004) PAL ranges (see ActivityLevel).
//                    The PAL ranges were defined against FAO's own BMR
//                    equations; multiplying another BMR by them is common
//                    practice, not part of the FAO method.
//   Surplus          Iraki et al. (2019): ~10-20% above maintenance; advanced
//                    lifters at the lower end.
//   Deficit, higher  AHA/ACC/TOS (2013) obesity guideline: a 500 or 750
//   body fat         kcal/day energy deficit.
//   Deficit, leaner  Helms et al. (2014): lose 0.5-1% of body weight a week,
//                    turned into kcal with the conventional ~7,700 kcal per
//                    kg of body weight lost (Wishnofsky, 1958). That figure
//                    is an approximation.
//   Protein          ISSN (Jager et al., 2017): 1.4-2.0 g/kg/day; 2-3x the
//                    0.8 g/kg RDA in an energy deficit. With a body
//                    composition estimate and a fat-loss goal: 2.3-3.1 g/kg
//                    of fat-free mass (ISSN, Aragon et al., 2017).
//   Fat              IOM (2005) AMDR: 20-35% of energy. Carbohydrate is the
//                    remainder.
//
// App choices, not from the sources:
//   - "Higher body fat" means the ACE Average or Obese category; leaner
//     categories get the slower, rate-based deficit (ISSN 2017 says only
//     that a higher body fat allows a more aggressive deficit).
//   - Without a body composition estimate, fat loss uses the AHA deficit.
//   - Fat and carbohydrate grams are worked out at the middle of the calorie
//     and protein ranges, so there is one set of numbers to follow.

/// Approximate energy in a kilogram of body weight lost (3,500 kcal/lb).
const double kKcalPerKgLost = 7700;

enum BmrMethod {
  mifflinStJeor('Estimated from your height, weight, age and sex'),
  katchMcArdle('Estimated from your estimated lean mass');

  const BmrMethod(this.label);
  final String label;
}

enum EnergyAdvice { maintain, surplus, deficit }

enum DeficitBasis {
  /// AHA/ACC/TOS: 500-750 kcal a day.
  fixed,

  /// Helms et al.: 0.5-1% of body weight a week.
  rate,
}

class NutritionTargets {
  const NutritionTargets({
    required this.bmrKcal,
    required this.bmrMethod,
    required this.maintenanceKcalLow,
    required this.maintenanceKcalHigh,
    required this.advice,
    required this.targetKcalLow,
    required this.targetKcalHigh,
    required this.proteinGLow,
    required this.proteinGHigh,
    required this.proteinFromLeanMass,
    required this.fatGLow,
    required this.fatGHigh,
    required this.carbsG,
    this.deficitBasis,
    this.composition,
    this.category,
  });

  final double bmrKcal;
  final BmrMethod bmrMethod;

  /// BMR x the activity level's PAL range.
  final double maintenanceKcalLow;
  final double maintenanceKcalHigh;

  final EnergyAdvice advice;
  final DeficitBasis? deficitBasis;

  /// What to eat for the goal. Equal to maintenance when maintaining.
  final double targetKcalLow;
  final double targetKcalHigh;

  final double proteinGLow;
  final double proteinGHigh;

  /// True when protein is per kg of fat-free mass rather than body weight.
  final bool proteinFromLeanMass;

  final double fatGLow;
  final double fatGHigh;

  /// The calories left after protein and fat, at the middle of the ranges.
  final double carbsG;

  /// The estimate used, if any.
  final CompositionRecord? composition;
  final BodyFatCategory? category;
}

/// Mifflin-St Jeor resting energy, kcal/day.
double mifflinStJeorKcal({
  required bool isMale,
  required int age,
  required double heightCm,
  required double weightKg,
}) => 10 * weightKg + 6.25 * heightCm - 5 * age + (isMale ? 5 : -161);

/// Katch-McArdle resting energy, kcal/day.
double katchMcArdleKcal(double fatFreeMassKg) => 370 + 21.6 * fatFreeMassKg;

/// Why no targets can be worked out, or null when they can.
String? nutritionBlocker(UserProfile profile) {
  if (profile.age < 18) return 'These targets are for adults only.';
  if (profile.weightKg <= 0) return 'Add your weight to your profile.';
  if (profile.sex == Sex.preferNotToSay && profile.latestComposition == null) {
    return 'The energy equation differs for men and women, so it needs your '
        'sex set to Male or Female in your profile.';
  }
  if (profile.activityLevel == null) return 'Choose your daily activity.';
  return null;
}

/// Targets for [profile], or null when [nutritionBlocker] says why not.
NutritionTargets? nutritionTargetsFor(UserProfile profile) {
  if (nutritionBlocker(profile) != null) return null;
  final activity = profile.activityLevel!;
  final weight = profile.weightKg;
  final composition = profile.latestComposition;

  // The estimate's body fat share, applied to the current weight.
  final fatFreeMass = composition == null
      ? null
      : weight * (1 - composition.bodyFatPct / 100);
  final category = composition == null || profile.sex == Sex.preferNotToSay
      ? null
      : bodyFatCategory(
          composition.bodyFatPct,
          isMale: profile.sex == Sex.male,
        );

  final bmrMethod = fatFreeMass != null
      ? BmrMethod.katchMcArdle
      : BmrMethod.mifflinStJeor;
  final bmr = fatFreeMass != null
      ? katchMcArdleKcal(fatFreeMass)
      : mifflinStJeorKcal(
          isMale: profile.sex == Sex.male,
          age: profile.age,
          heightCm: profile.heightCm,
          weightKg: weight,
        );
  final maintainLow = bmr * activity.palLow;
  final maintainHigh = bmr * activity.palHigh;

  var advice = EnergyAdvice.maintain;
  DeficitBasis? basis;
  var targetLow = maintainLow;
  var targetHigh = maintainHigh;
  var proteinLow = 1.4 * weight;
  var proteinHigh = 2.0 * weight;
  var fromLeanMass = false;

  switch (profile.goal) {
    case TrainingGoal.buildMuscle:
      {
        advice = EnergyAdvice.surplus;
        final advanced = profile.experience == ExperienceLevel.advanced;
        targetLow = maintainLow * 1.10;
        targetHigh = maintainHigh * (advanced ? 1.10 : 1.20);
      }
    case TrainingGoal.loseFat:
      {
        advice = EnergyAdvice.deficit;
        final leaner =
            category != null &&
            category != BodyFatCategory.average &&
            category != BodyFatCategory.obese;
        if (leaner) {
          basis = DeficitBasis.rate;
          final smallest = weight * 0.005 * kKcalPerKgLost / 7;
          final largest = weight * 0.01 * kKcalPerKgLost / 7;
          targetLow = maintainLow - largest;
          targetHigh = maintainHigh - smallest;
        } else {
          basis = DeficitBasis.fixed;
          targetLow = maintainLow - 750;
          targetHigh = maintainHigh - 500;
        }
        if (fatFreeMass != null) {
          proteinLow = 2.3 * fatFreeMass;
          proteinHigh = 3.1 * fatFreeMass;
          fromLeanMass = true;
        } else {
          proteinLow = 1.6 * weight;
          proteinHigh = 2.4 * weight;
        }
      }
    case TrainingGoal.getStronger:
    case TrainingGoal.improveBodyComposition:
    case TrainingGoal.improveAthleticPerformance:
      break;
  }

  final kcalMid = (targetLow + targetHigh) / 2;
  final proteinMid = (proteinLow + proteinHigh) / 2;
  final fatLow = 0.20 * kcalMid / 9;
  final fatHigh = 0.35 * kcalMid / 9;
  final fatMid = (fatLow + fatHigh) / 2;
  final carbs = (kcalMid - proteinMid * 4 - fatMid * 9) / 4;

  return NutritionTargets(
    bmrKcal: bmr,
    bmrMethod: bmrMethod,
    maintenanceKcalLow: maintainLow,
    maintenanceKcalHigh: maintainHigh,
    advice: advice,
    deficitBasis: basis,
    targetKcalLow: targetLow,
    targetKcalHigh: targetHigh,
    proteinGLow: proteinLow,
    proteinGHigh: proteinHigh,
    proteinFromLeanMass: fromLeanMass,
    fatGLow: fatLow,
    fatGHigh: fatHigh,
    carbsG: carbs < 0 ? 0 : carbs,
    composition: composition,
    category: category,
  );
}
