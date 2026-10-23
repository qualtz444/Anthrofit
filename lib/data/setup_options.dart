import '../content/app_content.dart';
import '../content/content_models.dart';
import '../models/models.dart';

// The filters behind the program setup questions. Kept out of the screens so
// the future program generator can use exactly the same rules.

/// The muscles a focus covers, in the order they appear in [MuscleGroup].
///
///   fullBody / chooseMuscles -> every muscle
///   push / pull              -> by movementGroup
///   upperBody / lowerBody    -> by region
///
/// Region and movement group are independent, so "Lower body" includes both
/// quads (push) and hamstrings (pull), and "Push" includes both chest (upper)
/// and quads (lower).
List<MuscleGroup> musclesForFocus(TrainingFocus focus) {
  switch (focus) {
    case TrainingFocus.fullBody:
    case TrainingFocus.chooseMuscles:
      return MuscleGroup.values;
    case TrainingFocus.push:
      return MuscleGroup.values
          .where((m) => m.movementGroup == MovementGroup.push)
          .toList();
    case TrainingFocus.pull:
      return MuscleGroup.values
          .where((m) => m.movementGroup == MovementGroup.pull)
          .toList();
    case TrainingFocus.upperBody:
      return MuscleGroup.values
          .where((m) => m.region == MuscleRegion.upper)
          .toList();
    case TrainingFocus.lowerBody:
      return MuscleGroup.values
          .where((m) => m.region == MuscleRegion.lower)
          .toList();
  }
}

/// Which muscles start out selected for a focus.
/// A named focus selects all of its muscles; "Choose muscles" starts empty so
/// the user picks deliberately.
List<MuscleGroup> defaultMusclesForFocus(TrainingFocus focus) =>
    focus == TrainingFocus.chooseMuscles ? const [] : musclesForFocus(focus);

/// Every equipment item offered by [categories], in [EquipmentItem] order.
/// "None" is left out: it means an exercise needs no equipment, which is not
/// something to tick.
List<EquipmentItem> equipmentForCategories(Set<EquipmentCategory> categories) {
  if (categories.isEmpty) return const [];
  return EquipmentItem.values
      .where(
        (item) =>
            item != EquipmentItem.none &&
            item.categories.any(categories.contains),
      )
      .toList();
}

/// Admin-added equipment offered by [categories], in the admin's order.
/// Hidden items are left out.
List<EquipmentDef> extraEquipmentForCategories(
  Set<EquipmentCategory> categories,
) {
  if (categories.isEmpty) return const [];
  return AppContent.equipment
      .where((e) => !e.hidden && e.categories.any(categories.contains))
      .toList();
}

/// A starting guess at the categories, from what the profile says the user has.
/// Only a default: the user can change it.
Set<EquipmentCategory> categoriesFromProfile(UserProfile? profile) {
  final access = profile?.equipment ?? const <EquipmentAccess>[];
  final categories = <EquipmentCategory>{};
  for (final item in access) {
    switch (item) {
      case EquipmentAccess.fullGym:
      case EquipmentAccess.machines:
      case EquipmentAccess.cables:
        categories.add(EquipmentCategory.commercialGym);
      case EquipmentAccess.freeWeights:
        categories.add(EquipmentCategory.smallGym);
      case EquipmentAccess.bodyweight:
        categories.add(EquipmentCategory.calisthenics);
    }
  }
  return categories;
}
