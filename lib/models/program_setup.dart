import '../core/json_utils.dart';
import 'enums.dart';

/// What the user asked for when a program was created: the goal, how long a
/// session should be, which muscles to train, and what equipment is available.
///
/// This is INPUT, not a result. Nothing generates a program from it yet; it is
/// recorded on the program so the future generator has the user's answers.
///
/// Muscles and equipment are stored as their enum `.name` ids, never labels,
/// so wording can change without touching saved programs. Unknown ids (from a
/// newer version) are dropped on load rather than crashing.
class ProgramSetup {
  const ProgramSetup({
    required this.goal,
    required this.sessionDuration,
    required this.focus,
    required this.muscles,
    required this.equipmentCategories,
    required this.equipment,
    this.extraEquipment = const [],
  });

  final TrainingGoal goal;
  final SessionDuration sessionDuration;

  /// How the muscles below were chosen. Kept so the generator can tell
  /// "upper body" from the same muscles picked one at a time.
  final TrainingFocus focus;

  /// The muscles to train. Always a subset of musclesForFocus(focus).
  final List<MuscleGroup> muscles;

  /// Where the user trains.
  final Set<EquipmentCategory> equipmentCategories;

  /// The specific equipment available, within those categories.
  final List<EquipmentItem> equipment;

  /// Admin-added equipment available, by id. Empty when there is none.
  final List<String> extraEquipment;

  ProgramSetup copyWith({
    TrainingGoal? goal,
    SessionDuration? sessionDuration,
    TrainingFocus? focus,
    List<MuscleGroup>? muscles,
    Set<EquipmentCategory>? equipmentCategories,
    List<EquipmentItem>? equipment,
    List<String>? extraEquipment,
  }) {
    return ProgramSetup(
      goal: goal ?? this.goal,
      sessionDuration: sessionDuration ?? this.sessionDuration,
      focus: focus ?? this.focus,
      muscles: muscles ?? this.muscles,
      equipmentCategories: equipmentCategories ?? this.equipmentCategories,
      equipment: equipment ?? this.equipment,
      extraEquipment: extraEquipment ?? this.extraEquipment,
    );
  }

  Map<String, dynamic> toJson() => {
    'goal': goal.name,
    'sessionDuration': sessionDuration.name,
    'focus': focus.name,
    'muscles': muscles.map((m) => m.name).toList(),
    'equipmentCategories': equipmentCategories.map((c) => c.name).toList(),
    'equipment': equipment.map((e) => e.name).toList(),
    if (extraEquipment.isNotEmpty) 'extraEquipment': extraEquipment,
  };

  factory ProgramSetup.fromJson(Map<String, dynamic> json) {
    final extra = json['extraEquipment'];
    return ProgramSetup(
      goal: enumByName(
        TrainingGoal.values,
        json['goal'],
        TrainingGoal.buildMuscle,
      ),
      sessionDuration: enumByName(
        SessionDuration.values,
        json['sessionDuration'],
        SessionDuration.min60,
      ),
      focus: enumByName(
        TrainingFocus.values,
        json['focus'],
        TrainingFocus.fullBody,
      ),
      muscles: enumListByName(MuscleGroup.values, json['muscles']),
      equipmentCategories: enumListByName(
        EquipmentCategory.values,
        json['equipmentCategories'],
      ).toSet(),
      equipment: enumListByName(EquipmentItem.values, json['equipment']),
      extraEquipment: extra is List
          ? extra.whereType<String>().toList()
          : const [],
    );
  }
}
