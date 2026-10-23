import '../core/json_utils.dart';
import '../core/units.dart';
import 'body_weight_entry.dart';
import 'composition_record.dart';
import 'enums.dart';
import 'screening.dart';

/// Calculates age in years from date of birth relative to [today].
int calculateAge(DateTime dob, [DateTime? today]) {
  final now = today ?? DateTime.now();
  var age = now.year - dob.year;
  if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
    age--;
  }
  return age;
}

/// The single local user's profile. Baseline has one profile, so no id.
class UserProfile {
  final String name;
  final int age;
  final DateTime? dateOfBirth;
  final Sex sex;
  final double heightCm;
  final double weightKg;
  final TrainingGoal goal;
  final ExperienceLevel experience;
  final TrainingFrequency trainingFrequency;
  final SessionDuration sessionDuration;
  final List<EquipmentAccess> equipment;

  /// Which units to SHOW. Height and weight above are always stored in
  /// centimetres and kilograms, whatever these say.
  ///
  /// Two settings, not one: someone may know their height in feet and their
  /// weight in kilos.
  final HeightUnit heightUnit;
  final WeightUnit weightUnit;

  /// Every weight this profile has had, one per day, oldest first.
  ///
  /// [weightKg] is only ever the latest, so this is what lets Progress show
  /// a trend. Added to by ProfileController when the weight changes, and
  /// never by anything else. Empty for profiles saved before it existed.
  final List<BodyWeightEntry> weightLog;

  /// Daily activity outside training, for nutrition targets. Null until the
  /// user answers, including for every profile saved before it existed.
  final ActivityLevel? activityLevel;

  /// Every saved body composition estimate, oldest first.
  final List<CompositionRecord> compositionLog;

  /// The newest body composition estimate, or null when there is none.
  CompositionRecord? get latestComposition =>
      compositionLog.isEmpty ? null : compositionLog.last;

  /// PAR-Q+ answers, one per [kParqQuestions] item, true = YES. Null for
  /// profiles saved before the screening existed.
  final List<bool>? parqAnswers;

  /// True when any PAR-Q+ answer is YES.
  bool get parqAnyYes => parqAnswers?.contains(true) ?? false;

  ParqConcern get parqLevel => parqConcern(parqAnswers);

  /// The person said a doctor cleared them to exercise. Self-reported; the
  /// app cannot check it. Reset whenever the health answers change.
  final bool medicallyCleared;

  /// Medical clearance is needed and has not been reported.
  bool get needsClearance =>
      parqLevel == ParqConcern.clearanceFirst && !medicallyCleared;

  /// Body areas with an injury or limitation, and anything else the person
  /// wrote about it. Both optional.
  final List<LimitationArea> limitations;
  final String limitationNote;

  /// Lifestyle answers from setup. Null for older profiles.
  final DailyRoutine? dailyRoutine;
  final TimeBudget? timeBudget;

  /// Food screening. Optional; changes no number.
  final DietPattern? dietPattern;
  final String foodAllergies;

  const UserProfile({
    required this.name,
    required this.age,
    this.dateOfBirth,
    required this.sex,
    required this.heightCm,
    required this.weightKg,
    required this.goal,
    required this.experience,
    required this.trainingFrequency,
    required this.sessionDuration,
    required this.equipment,
    this.heightUnit = HeightUnit.cm,
    this.weightUnit = WeightUnit.kg,
    this.weightLog = const [],
    this.activityLevel,
    this.compositionLog = const [],
    this.parqAnswers,
    this.medicallyCleared = false,
    this.limitations = const [],
    this.limitationNote = '',
    this.dailyRoutine,
    this.timeBudget,
    this.dietPattern,
    this.foodAllergies = '',
  });

  UserProfile copyWith({
    String? name,
    int? age,
    DateTime? dateOfBirth,
    Sex? sex,
    double? heightCm,
    double? weightKg,
    TrainingGoal? goal,
    ExperienceLevel? experience,
    TrainingFrequency? trainingFrequency,
    SessionDuration? sessionDuration,
    List<EquipmentAccess>? equipment,
    HeightUnit? heightUnit,
    WeightUnit? weightUnit,
    List<BodyWeightEntry>? weightLog,
    ActivityLevel? activityLevel,
    List<CompositionRecord>? compositionLog,
    List<bool>? parqAnswers,
    bool? medicallyCleared,
    List<LimitationArea>? limitations,
    String? limitationNote,
    DailyRoutine? dailyRoutine,
    TimeBudget? timeBudget,
    DietPattern? dietPattern,
    String? foodAllergies,
  }) {
    return UserProfile(
      name: name ?? this.name,
      age: age ?? this.age,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      sex: sex ?? this.sex,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      goal: goal ?? this.goal,
      experience: experience ?? this.experience,
      trainingFrequency: trainingFrequency ?? this.trainingFrequency,
      sessionDuration: sessionDuration ?? this.sessionDuration,
      equipment: equipment ?? this.equipment,
      heightUnit: heightUnit ?? this.heightUnit,
      weightUnit: weightUnit ?? this.weightUnit,
      weightLog: weightLog ?? this.weightLog,
      activityLevel: activityLevel ?? this.activityLevel,
      compositionLog: compositionLog ?? this.compositionLog,
      parqAnswers: parqAnswers ?? this.parqAnswers,
      medicallyCleared: medicallyCleared ?? this.medicallyCleared,
      limitations: limitations ?? this.limitations,
      limitationNote: limitationNote ?? this.limitationNote,
      dailyRoutine: dailyRoutine ?? this.dailyRoutine,
      timeBudget: timeBudget ?? this.timeBudget,
      dietPattern: dietPattern ?? this.dietPattern,
      foodAllergies: foodAllergies ?? this.foodAllergies,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'age': age,
    if (dateOfBirth != null) 'dateOfBirth': dateOfBirth!.toIso8601String(),
    'sex': sex.name,
    'heightCm': heightCm,
    'weightKg': weightKg,
    'goal': goal.name,
    'experience': experience.name,
    'trainingFrequency': trainingFrequency.name,
    'sessionDuration': sessionDuration.name,
    'equipment': enumNames(equipment),
    'heightUnit': heightUnit.name,
    'weightUnit': weightUnit.name,
    'weightLog': weightLog.map((e) => e.toJson()).toList(),
    if (activityLevel != null) 'activityLevel': activityLevel!.name,
    if (compositionLog.isNotEmpty)
      'compositionLog': compositionLog.map((e) => e.toJson()).toList(),
    if (parqAnswers != null) 'parqAnswers': parqAnswers,
    if (medicallyCleared) 'medicallyCleared': true,
    if (limitations.isNotEmpty) 'limitations': enumNames(limitations),
    if (limitationNote.isNotEmpty) 'limitationNote': limitationNote,
    if (dailyRoutine != null) 'dailyRoutine': dailyRoutine!.name,
    if (timeBudget != null) 'timeBudget': timeBudget!.name,
    if (dietPattern != null) 'dietPattern': dietPattern!.name,
    if (foodAllergies.isNotEmpty) 'foodAllergies': foodAllergies,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final dob = parseDate(json['dateOfBirth']);
    return UserProfile(
      name: parseString(json['name']),
      age: dob != null ? calculateAge(dob) : parseInt(json['age']),
      dateOfBirth: dob,
      sex: enumByName(Sex.values, json['sex'], Sex.preferNotToSay),
      heightCm: parseDouble(json['heightCm']),
      weightKg: parseDouble(json['weightKg']),
      goal: enumByName(
        TrainingGoal.values,
        json['goal'],
        TrainingGoal.buildMuscle,
      ),
      experience: enumByName(
        ExperienceLevel.values,
        json['experience'],
        ExperienceLevel.beginner,
      ),
      trainingFrequency: enumByName(
        TrainingFrequency.values,
        json['trainingFrequency'],
        TrainingFrequency.three,
      ),
      sessionDuration: enumByName(
        SessionDuration.values,
        json['sessionDuration'],
        SessionDuration.min60,
      ),
      equipment: enumListByName(EquipmentAccess.values, json['equipment']),
      // Profiles saved before units existed read as cm and kg, as they were.
      // A profile from the one short-lived combined setting maps across, so
      // someone who chose imperial keeps feet and pounds.
      heightUnit: enumByName(
        HeightUnit.values,
        json['heightUnit'],
        json['units'] == 'imperial' ? HeightUnit.feetInches : HeightUnit.cm,
      ),
      weightUnit: enumByName(
        WeightUnit.values,
        json['weightUnit'],
        json['units'] == 'imperial' ? WeightUnit.lb : WeightUnit.kg,
      ),
      weightLog: parseMapList(
        json['weightLog'],
      ).map(BodyWeightEntry.fromJson).toList(),
      activityLevel: _activityFrom(json['activityLevel']),
      compositionLog: parseMapList(
        json['compositionLog'],
      ).map(CompositionRecord.fromJson).toList(),
      parqAnswers: _boolsFrom(json['parqAnswers']),
      medicallyCleared: json['medicallyCleared'] == true,
      limitations: enumListByName(LimitationArea.values, json['limitations']),
      limitationNote: parseString(json['limitationNote']),
      dailyRoutine: _optionalByName(DailyRoutine.values, json['dailyRoutine']),
      timeBudget: _optionalByName(TimeBudget.values, json['timeBudget']),
      dietPattern: _optionalByName(DietPattern.values, json['dietPattern']),
      foodAllergies: parseString(json['foodAllergies']),
    );
  }

  /// A saved answer list only counts when it is complete.
  static List<bool>? _boolsFrom(Object? raw) {
    if (raw is! List || raw.length != kParqQuestions.length) return null;
    if (raw.any((e) => e is! bool)) return null;
    return raw.cast<bool>();
  }

  static T? _optionalByName<T extends Enum>(List<T> values, Object? raw) {
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return null;
  }

  static ActivityLevel? _activityFrom(Object? raw) {
    for (final level in ActivityLevel.values) {
      if (level.name == raw) return level;
    }
    return null;
  }
}
