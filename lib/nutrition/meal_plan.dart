import '../models/models.dart';

/// A sample day of Filipino meals built on the FNRI-DOST Pinggang Pinoy
/// plate: every meal has a Go food (⅓ plate), a Grow food (⅙ plate), and
/// vegetables and fruit (½ plate).
///
/// Examples, not a prescribed diet. The plate is the source. The food list,
/// three meals a day, and the daily rotation are design choices, not
/// evidence-based requirements. No portion amounts are given, so the meals
/// cannot guarantee the nutrition targets are met; the targets themselves
/// come only from nutrition_targets.dart.

enum PlateGroup { go, grow, vegetable, fruit }

/// What a food contains, for diet and allergy filtering.
enum FoodTag { pork, beef, chicken, fish, shellfish, egg, soy, peanut, milk }

class Food {
  const Food(this.name, this.group, [this.tags = const {}]);
  final String name;
  final PlateGroup group;
  final Set<FoodTag> tags;
}

/// Plain, widely available foods for each part of the plate.
const List<Food> kFoods = [
  // Go: rice, corn, bread, oatmeal, root crops
  Food('Rice', PlateGroup.go),
  Food('Brown rice', PlateGroup.go),
  Food('Boiled corn', PlateGroup.go),
  Food('Pandesal', PlateGroup.go, {FoodTag.milk, FoodTag.egg}),
  Food('Oatmeal', PlateGroup.go),
  Food('Boiled kamote', PlateGroup.go),
  Food('Boiled gabi', PlateGroup.go),
  // Grow: fish, meat, poultry, eggs, beans and legumes
  Food('Grilled bangus', PlateGroup.grow, {FoodTag.fish}),
  Food('Paksiw na galunggong', PlateGroup.grow, {FoodTag.fish}),
  Food('Sardines', PlateGroup.grow, {FoodTag.fish}),
  Food('Chicken tinola', PlateGroup.grow, {FoodTag.chicken}),
  Food('Grilled chicken breast', PlateGroup.grow, {FoodTag.chicken}),
  Food('Pork adobo', PlateGroup.grow, {FoodTag.pork}),
  Food('Beef nilaga', PlateGroup.grow, {FoodTag.beef}),
  Food('Boiled eggs', PlateGroup.grow, {FoodTag.egg}),
  Food('Tokwa (tofu)', PlateGroup.grow, {FoodTag.soy}),
  Food('Ginisang monggo', PlateGroup.grow),
  Food('Sinigang na hipon', PlateGroup.grow, {FoodTag.shellfish}),
  // Glow: vegetables
  Food('Steamed kangkong', PlateGroup.vegetable),
  Food('Ginisang pechay', PlateGroup.vegetable),
  Food('Ensaladang talong', PlateGroup.vegetable),
  Food('Boiled okra', PlateGroup.vegetable),
  Food('Ginataang kalabasa at sitaw', PlateGroup.vegetable),
  Food('Malunggay soup', PlateGroup.vegetable),
  // Glow: fruit
  Food('Banana', PlateGroup.fruit),
  Food('Papaya', PlateGroup.fruit),
  Food('Mango', PlateGroup.fruit),
  Food('Pineapple', PlateGroup.fruit),
  Food('Watermelon', PlateGroup.fruit),
  Food('Guava', PlateGroup.fruit),
];

/// Words in the allergy note that rule out each tag.
const Map<FoodTag, List<String>> _allergyWords = {
  FoodTag.fish: ['fish', 'isda', 'seafood', 'bangus', 'galunggong', 'sardine'],
  FoodTag.shellfish: [
    'shellfish', 'shrimp', 'hipon', 'prawn', 'crab', 'seafood', 'alamang',
  ],
  FoodTag.egg: ['egg', 'itlog'],
  FoodTag.soy: ['soy', 'tofu', 'tokwa'],
  FoodTag.peanut: ['peanut', 'mani'],
  FoodTag.milk: ['milk', 'dairy', 'lactose', 'gatas'],
  FoodTag.pork: ['pork', 'baboy'],
  FoodTag.beef: ['beef', 'baka'],
  FoodTag.chicken: ['chicken', 'manok'],
};

/// Tags each diet answer rules out. "Vegetarian" keeps eggs and milk
/// (lacto-ovo), which is an app choice; an egg or milk allergy still
/// removes them.
Set<FoodTag> _excludedBy(DietPattern? diet) => switch (diet) {
  null || DietPattern.noRestriction => const {},
  DietPattern.noPork => const {FoodTag.pork},
  DietPattern.noBeef => const {FoodTag.beef},
  DietPattern.pescatarian => const {
    FoodTag.pork,
    FoodTag.beef,
    FoodTag.chicken,
  },
  DietPattern.vegetarian => const {
    FoodTag.pork,
    FoodTag.beef,
    FoodTag.chicken,
    FoodTag.fish,
    FoodTag.shellfish,
  },
};

/// True when the food fits the person's diet and allergy answers.
bool foodFits(Food food, UserProfile profile) {
  final excluded = {..._excludedBy(profile.dietPattern)};
  final allergies = profile.foodAllergies.toLowerCase();
  if (allergies.isNotEmpty) {
    for (final entry in _allergyWords.entries) {
      if (entry.value.any(allergies.contains)) excluded.add(entry.key);
    }
    // A food named in the note is out too ("kangkong", "mango").
    for (final word in allergies.split(RegExp(r'[^a-z]+'))) {
      if (word.length >= 4 && food.name.toLowerCase().contains(word)) {
        return false;
      }
    }
  }
  return !food.tags.any(excluded.contains);
}

class SampleMeal {
  const SampleMeal(this.name, this.foods);
  final String name;

  /// One food per plate group that has a fitting food.
  final Map<PlateGroup, Food> foods;
}

/// Three meals for day [dayIndex], so each day shows a different mix.
/// Within a day, no Grow food repeats when there are enough to choose from.
List<SampleMeal> sampleDay(UserProfile profile, int dayIndex) {
  final fits = [for (final f in kFoods) if (foodFits(f, profile)) f];
  List<Food> of(PlateGroup g) => [for (final f in fits) if (f.group == g) f];

  const names = ['Breakfast', 'Lunch', 'Dinner'];
  return [
    for (var meal = 0; meal < names.length; meal++)
      SampleMeal(names[meal], {
        for (final g in PlateGroup.values)
          if (of(g).isNotEmpty)
            g: of(g)[(dayIndex * names.length + meal) % of(g).length],
      }),
  ];
}

/// Plate share of each group, per Pinggang Pinoy.
String plateShare(PlateGroup g) => switch (g) {
  PlateGroup.go => '⅓ plate',
  PlateGroup.grow => '⅙ plate',
  PlateGroup.vegetable || PlateGroup.fruit => '½ plate together',
};
