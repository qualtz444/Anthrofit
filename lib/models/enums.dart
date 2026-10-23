// All fixed option sets for the baseline.
// Each enum has a human-readable `label` for the UI.
// JSON stores `.name`, never `label`, so labels can change safely.

enum Sex {
  male('Male'),
  female('Female'),
  preferNotToSay('Prefer not to say');

  const Sex(this.label);
  final String label;
}

enum TrainingGoal {
  buildMuscle('Build muscle'),
  getStronger('Get stronger'),
  loseFat('Lose fat'),
  improveBodyComposition('Improve body composition'),
  improveAthleticPerformance('Improve athletic performance');

  const TrainingGoal(this.label);
  final String label;
}

/// Habitual physical activity, all day and not only in the gym.
///
/// The three lifestyle categories and their PAL (physical activity level)
/// ranges are FAO/WHO/UNU, Human Energy Requirements (2004), Table 5.3.
/// PAL multiplies basal metabolic rate to give daily energy needs.
enum ActivityLevel {
  sedentaryOrLight(
    'Sedentary or light',
    'Mostly sitting or standing during the day',
    1.40,
    1.69,
  ),
  active(
    'Active or moderately active',
    'On your feet and moving for much of the day',
    1.70,
    1.99,
  ),
  vigorous(
    'Vigorous',
    'Heavy physical work or long daily exercise',
    2.00,
    2.40,
  );

  const ActivityLevel(this.label, this.description, this.palLow, this.palHigh);
  final String label;
  final String description;
  final double palLow;
  final double palHigh;
}

/// Weight-training experience. [question] and [description] are how setup
/// asks it, since most people do not know what "intermediate" means. The
/// descriptions follow the ACSM (2009) progression position stand: novice
/// = no resistance training or none for several years, intermediate = about
/// 6 months of consistent training, advanced = years of training.
enum ExperienceLevel {
  beginner(
    'Beginner',
    'New to weight training',
    "I don't lift weights yet, or haven't for several years",
  ),
  intermediate(
    'Intermediate',
    'Some experience',
    'About 6 months or more of regular weight training',
  ),
  advanced(
    'Advanced',
    'Experienced',
    'Years of regular weight training',
  );

  const ExperienceLevel(this.label, this.question, this.description);
  final String label;
  final String question;
  final String description;
}

/// Training days per week. `days` is the number shown; sixPlus stores 6.
enum TrainingFrequency {
  two('2', 2),
  three('3', 3),
  four('4', 4),
  five('5', 5),
  sixPlus('6+', 6);

  const TrainingFrequency(this.label, this.days);
  final String label;
  final int days;
}

/// Session duration option. `minutes` is the option value; min90Plus stores 90.
enum SessionDuration {
  min15('15 min', 15),
  min30('30 min', 30),
  min45('45 min', 45),
  min60('60 min', 60),
  min75('75 min', 75),
  min90Plus('90+ min', 90);

  const SessionDuration(this.label, this.minutes);
  final String label;
  final int minutes;
}

/// What the USER has access to (profile onboarding).
enum EquipmentAccess {
  fullGym('Full gym'),
  machines('Machines'),
  cables('Cables'),
  freeWeights('Free weights'),
  bodyweight('Bodyweight');

  const EquipmentAccess(this.label);
  final String label;
}

/// What an EXERCISE physically needs (exercise library).
/// What an EXERCISE physically needs, and the smallest place you would
/// normally find it. [categories] lists every place that has it, so a
/// commercial gym offers everything a home setup does.
enum EquipmentItem {
  // Needs nothing at all, so it is available everywhere.
  none('None', {
    EquipmentCategory.home,
    EquipmentCategory.calisthenics,
    EquipmentCategory.smallGym,
    EquipmentCategory.commercialGym,
  }),
  dumbbell('Dumbbell', {
    EquipmentCategory.home,
    EquipmentCategory.smallGym,
    EquipmentCategory.commercialGym,
  }),
  kettlebell('Kettlebell', {
    EquipmentCategory.home,
    EquipmentCategory.smallGym,
    EquipmentCategory.commercialGym,
  }),
  bench('Bench', {
    EquipmentCategory.home,
    EquipmentCategory.smallGym,
    EquipmentCategory.commercialGym,
  }),
  pullUpBar('Pull-up bar', {
    EquipmentCategory.home,
    EquipmentCategory.calisthenics,
    EquipmentCategory.smallGym,
    EquipmentCategory.commercialGym,
  }),
  dipStation('Dip station', {
    EquipmentCategory.calisthenics,
    EquipmentCategory.smallGym,
    EquipmentCategory.commercialGym,
  }),
  barbell('Barbell', {
    EquipmentCategory.smallGym,
    EquipmentCategory.commercialGym,
  }),
  ezBar('EZ bar', {
    EquipmentCategory.smallGym,
    EquipmentCategory.commercialGym,
  }),
  rack('Rack', {EquipmentCategory.smallGym, EquipmentCategory.commercialGym}),
  cable('Cable', {EquipmentCategory.commercialGym}),
  machine('Machine', {EquipmentCategory.commercialGym}),
  smithMachine('Smith machine', {EquipmentCategory.commercialGym});

  const EquipmentItem(this.label, this.categories);
  final String label;

  /// Every category that offers this item.
  final Set<EquipmentCategory> categories;

  /// Lookup by stable id (`.name`). Null if the id is unknown.
  static EquipmentItem? byId(String id) {
    for (final item in values) {
      if (item.name == id) return item;
    }
    return null;
  }
}

enum ExerciseType {
  bodyweight('Bodyweight'),
  machine('Machine'),
  freeWeight('Free weight'),
  cardio('Cardio');

  const ExerciseType(this.label);
  final String label;
}

enum MovementPattern {
  kneeDominant('Knee Dominant'),
  hipDominant('Hip Dominant'),
  horizontalPush('Horizontal Push'),
  verticalPush('Vertical Push'),
  horizontalPull('Horizontal Pull'),
  verticalPull('Vertical Pull'),
  // Single-joint work: curls, raises, extensions, calf and ab work. Not
  // forced into push or pull, because it is neither.
  isolation('Isolation'),
  // Cardio has no push/pull pattern at all; it gets its own value so the
  // field can stay required.
  cardio('Cardio');

  const MovementPattern(this.label);
  final String label;
}

/// Where a muscle sits on the body. Independent of [MovementGroup].
enum MuscleRegion {
  upper('Upper body'),
  lower('Lower body'),
  core('Core');

  const MuscleRegion(this.label);
  final String label;
}

/// Which half of a push/pull split a muscle belongs to. Independent of
/// [MuscleRegion]: quads are lower AND push, lats are upper AND pull.
/// [neither] is for muscles that fit no push/pull split, such as the core.
enum MovementGroup {
  push('Push'),
  pull('Pull'),
  neither('Neither');

  const MovementGroup(this.label);
  final String label;
}

/// The muscles the exercise library and program setup both use.
/// `.name` is the stable id that gets saved; [label] is only for display.
enum MuscleGroup {
  chest('Chest', MuscleRegion.upper, MovementGroup.push),
  lats('Lats', MuscleRegion.upper, MovementGroup.pull),
  upperBack('Upper Back', MuscleRegion.upper, MovementGroup.pull),
  traps('Traps', MuscleRegion.upper, MovementGroup.pull),
  // Trained by extension (a push) and by holding a braced position; grouped
  // with the core because it fits no push/pull split cleanly.
  lowerBack('Lower Back', MuscleRegion.core, MovementGroup.neither),
  frontDelts('Front Delts', MuscleRegion.upper, MovementGroup.push),
  sideDelts('Side Delts', MuscleRegion.upper, MovementGroup.push),
  rearDelts('Rear Delts', MuscleRegion.upper, MovementGroup.pull),
  biceps('Biceps', MuscleRegion.upper, MovementGroup.pull),
  triceps('Triceps', MuscleRegion.upper, MovementGroup.push),
  forearms('Forearms', MuscleRegion.upper, MovementGroup.pull),
  core('Core', MuscleRegion.core, MovementGroup.neither),
  quads('Quads', MuscleRegion.lower, MovementGroup.push),
  hamstrings('Hamstrings', MuscleRegion.lower, MovementGroup.pull),
  glutes('Glutes', MuscleRegion.lower, MovementGroup.pull),
  calves('Calves', MuscleRegion.lower, MovementGroup.push);

  const MuscleGroup(this.label, this.region, this.movementGroup);
  final String label;
  final MuscleRegion region;
  final MovementGroup movementGroup;

  /// Lookup by stable id (`.name`). Null if the id is unknown.
  static MuscleGroup? byId(String id) {
    for (final muscle in values) {
      if (muscle.name == id) return muscle;
    }
    return null;
  }
}

/// What a program should train. Each option is only a filter over
/// [MuscleGroup]; see musclesForFocus() in data/setup_options.dart.
enum TrainingFocus {
  fullBody('Full body'),
  push('Push muscles'),
  pull('Pull muscles'),
  upperBody('Upper body'),
  lowerBody('Lower body'),
  chooseMuscles('Choose muscles');

  const TrainingFocus(this.label);
  final String label;
}

/// Where the user trains. Decides which [EquipmentItem]s are offered.
enum EquipmentCategory {
  home('Home equipment'),
  calisthenics('Calisthenics equipment'),
  smallGym('Small gym'),
  commercialGym('Commercial gym');

  const EquipmentCategory(this.label);
  final String label;
}

/// How technically demanding an exercise is.
enum Complexity {
  low('Low'),
  moderate('Moderate'),
  high('High');

  const Complexity(this.label);
  final String label;
}

enum Weekday {
  monday('Monday', 'Mon', 'M'),
  tuesday('Tuesday', 'Tue', 'T'),
  wednesday('Wednesday', 'Wed', 'W'),
  thursday('Thursday', 'Thu', 'Th'),
  friday('Friday', 'Fri', 'F'),
  saturday('Saturday', 'Sat', 'Sa'),
  sunday('Sunday', 'Sun', 'Su');

  const Weekday(this.label, this.shortLabel, this.compactLabel);
  final String label;
  final String shortLabel;

  /// For "M/W/F" style lists.
  final String compactLabel;

  /// Dart's DateTime.weekday is 1 (Mon) .. 7 (Sun).
  static Weekday fromDateTime(DateTime date) =>
      Weekday.values[date.weekday - 1];
}

/// What kind of set it is. JSON stores `.name` ("warmUp", "working", "failure").
/// [label] is the full name for editors; [shortLabel] is for compact lines.
enum SetType {
  warmUp('Warm-up', 'Warm-up'),
  working('Working Set', 'Working'),
  failure('Failure', 'Failure');

  const SetType(this.label, this.shortLabel);
  final String label;
  final String shortLabel;
}
