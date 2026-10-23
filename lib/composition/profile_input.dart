import '../models/models.dart';
import 'body_composition.dart';

/// The one place the composition module reads the app's own types.
///
/// Returns null when the profile cannot supply what the models need. The
/// models were trained on males and females only, so "prefer not to say" gets
/// no estimate rather than a guessed one.
CompositionInput? compositionInputFrom(UserProfile profile) {
  final bool isMale;
  switch (profile.sex) {
    case Sex.male:
      isMale = true;
    case Sex.female:
      isMale = false;
    case Sex.preferNotToSay:
      return null;
  }
  final dob = profile.dateOfBirth;
  final age = dob != null ? calculateAge(dob) : profile.age;
  return CompositionInput(
    heightCm: profile.heightCm,
    weightKg: profile.weightKg,
    age: age,
    isMale: isMale,
  );
}
