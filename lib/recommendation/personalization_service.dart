import '../data/exercise_library.dart';
import '../data/setup_options.dart';
import '../models/models.dart';
import 'program_recommender.dart';
import 'proportion_rules.dart';

// Connects what the app already knows to the existing ProgramRecommender.
//
// Nothing here recommends anything. It decides WHICH setup to hand the
// recommender, calls it, and turns the outcome into something a screen can
// show without overclaiming. The recommendation rules stay in
// program_recommender.dart and the files beneath it.

/// Shown when the exercise catalogue never loaded. The same wording the
/// library controller uses, so there is one message for one problem.
const String kCatalogUnavailable = 'The exercise list could not be loaded.';

/// The recommender the app uses: proportion rules on, with the cut-offs from
/// this project's measured participants.
const ProgramRecommender kAppRecommender = ProgramRecommender(
  thresholds: ProportionThresholds.participants,
);

/// Where the setup used for a recommendation came from.
enum SetupSource {
  /// Reused from the user's active program, so nothing is asked twice.
  activeProgram,

  /// Built from the profile, when there is no usable program setup.
  profile,
}

class ResolvedSetup {
  const ResolvedSetup(this.setup, this.source);

  final ProgramSetup setup;
  final SetupSource source;
}

/// Picks the setup to recommend from.
///
///   1. The active program's setup, if it has a usable one.
///   2. Otherwise the profile: its goal, session length and equipment, with
///      a full-body focus.
///
/// Nothing is invented. A profile value is used as it is, and the muscles
/// are simply everything, which is what "full body" already means in the
/// setup wizard.
///
/// "Usable" means it still names at least one muscle and one piece of
/// equipment: a setup with neither could only produce an empty program.
ResolvedSetup resolveSetup({
  required UserProfile profile,
  TrainingProgram? activeProgram,
}) {
  final fromProgram = activeProgram?.setup;
  if (fromProgram != null &&
      fromProgram.muscles.isNotEmpty &&
      fromProgram.equipment.isNotEmpty) {
    return ResolvedSetup(fromProgram, SetupSource.activeProgram);
  }

  final categories = categoriesFromProfile(profile);
  return ResolvedSetup(
    ProgramSetup(
      goal: profile.goal,
      sessionDuration: profile.sessionDuration,
      focus: TrainingFocus.fullBody,
      muscles: musclesForFocus(TrainingFocus.fullBody),
      equipmentCategories: categories,
      equipment: equipmentForCategories(categories),
      extraEquipment: [
        for (final e in extraEquipmentForCategories(categories)) e.id,
      ],
    ),
    SetupSource.profile,
  );
}

/// What came of asking for a personalised program.
class PersonalizationOutcome {
  const PersonalizationOutcome.success(
    RecommendedProgram this.recommended,
    SetupSource this.source,
  ) : failure = null;

  const PersonalizationOutcome.failure(String this.failure)
    : recommended = null,
      source = null;

  final RecommendedProgram? recommended;
  final SetupSource? source;

  /// Why nothing was built, in words for the user.
  final String? failure;

  bool get succeeded => recommended != null;
}

/// Builds a program from the user's setup, or says plainly why it could not.
///
/// Never throws and never returns a half-built program: an empty result is a
/// failure here, because previewing a program with nothing in it would only
/// invite the user to save it.
///
/// [goal], when given, overrides the setup's goal for this plan.
///
/// [measurement] is passed through to the recommender, which decides for
/// itself whether it can be used. Whether it WAS used is reported on
/// [RecommendedProgram.usedProportions], not assumed here.
PersonalizationOutcome personalizeProgram({
  required UserProfile? profile,
  TrainingProgram? activeProgram,
  Measurement? measurement,
  ProgramRecommender recommender = kAppRecommender,
  String? catalogError,
  TrainingGoal? goal,
}) {
  // No exercises, no program. No Dart fallback list: the catalogue is data.
  if (!ExerciseLibrary.isLoaded) {
    return PersonalizationOutcome.failure(catalogError ?? kCatalogUnavailable);
  }
  if (profile == null) {
    return const PersonalizationOutcome.failure(
      'Set up your profile first, so there is something to build the '
      'program around.',
    );
  }

  try {
    final resolved = resolveSetup(
      profile: profile,
      activeProgram: activeProgram,
    );
    // A goal chosen for this plan (from a body composition result) replaces
    // whatever goal the setup carried. Everything else in the setup stays.
    final setup = goal == null
        ? resolved.setup
        : resolved.setup.copyWith(goal: goal);
    final result = recommender.recommend(
      profile: profile,
      setup: setup,
      measurement: measurement,
    );
    if (result.isEmpty) {
      return PersonalizationOutcome.failure(
        result.note ??
            'No exercises matched your equipment and settings. Adding more '
                'equipment would give more options.',
      );
    }
    return PersonalizationOutcome.success(result, resolved.source);
  } catch (_) {
    return const PersonalizationOutcome.failure(
      "Couldn't build a program. Try again.",
    );
  }
}

/// What the preview says about the scan.
class ScanInfluence {
  const ScanInfluence({
    required this.headline,
    required this.detail,
    required this.usedScan,
  });

  final String headline;
  final String detail;
  final bool usedScan;
}

/// Words for the preview, from what the scan actually did and nothing else.
///
/// [usedProportions]: a scan and thresholds were both available.
/// [tipExercises] and [changedPicks]: what that changed (see
/// RecommendedProgram). A scan that was checked but changed nothing says
/// so, rather than claiming it shaped the program.
ScanInfluence describeScanInfluence({
  required bool usedProportions,
  List<String> tipExercises = const [],
  int changedPicks = 0,
}) {
  if (usedProportions && (tipExercises.isNotEmpty || changedPicks > 0)) {
    final tips = tipExercises.length == 1
        ? '1 exercise'
        : '${tipExercises.length} exercises';
    final picks = changedPicks == 1
        ? '1 exercise differs'
        : '$changedPicks exercises differ';
    final parts = <String>[
      if (tipExercises.isNotEmpty)
        'Setup tips from your proportions for $tips: '
            '${tipExercises.join(', ')}.',
      if (changedPicks > 0)
        '$picks from the program you would get without your scan.',
    ];
    return ScanInfluence(
      headline: 'Used your scan',
      detail: parts.join(' '),
      usedScan: true,
    );
  }
  if (usedProportions) {
    return const ScanInfluence(
      headline: "Your scan didn't change this program",
      detail:
          'Your proportions were checked. No changes were needed, so it is the '
          'same as it would be without a scan.',
      usedScan: true,
    );
  }
  return const ScanInfluence(
    headline: "Your body scan wasn't used",
    detail:
        'This program comes from your profile only. Do a body scan to fit '
        'exercises to your proportions.',
    usedScan: false,
  );
}
