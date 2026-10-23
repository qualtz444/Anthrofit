// Onboarding answers about the person's life outside the gym: health
// screening, limitations, daily routine, available time and food.
// JSON stores `.name`, never the label, so wording can change safely.

import 'enums.dart';

/// The seven general health questions of the PAR-Q+, as published, without
/// the "please list" lines (the app does not collect conditions).
///
/// Source: PAR-Q+ Collaboration, The Physical Activity Readiness
/// Questionnaire for Everyone (PAR-Q+), 2023 edition (eparmedx.com).
const List<String> kParqQuestions = [
  'Has your doctor ever said that you have a heart condition OR high blood '
      'pressure?',
  'Do you feel pain in your chest at rest, during your daily activities of '
      'living, OR when you do physical activity?',
  'Do you lose balance because of dizziness OR have you lost consciousness '
      'in the last 12 months? Please answer NO if your dizziness was '
      'associated with over-breathing (including during vigorous exercise).',
  'Have you ever been diagnosed with another chronic medical condition '
      '(other than heart disease or high blood pressure)?',
  'Are you currently taking prescribed medications for a chronic medical '
      'condition?',
  'Do you currently have (or have had within the past 12 months) a bone, '
      'joint, or soft tissue (muscle, ligament, or tendon) problem that could '
      'be made worse by becoming more physically active? Please answer NO if '
      'you had a problem in the past, but it does not limit your current '
      'ability to be physically active.',
  'Has your doctor ever said that you should only do medically supervised '
      'physical activity?',
];

/// How much a set of PAR-Q+ answers asks of the person before exercising.
enum ParqConcern {
  /// Every answer NO (or not answered yet).
  none,

  /// A YES that the PAR-Q+ follows up: its later pages, or a doctor or
  /// qualified exercise professional.
  followUp,

  /// A YES to a current symptom or a doctor's restriction: medical
  /// clearance before exercising.
  clearanceFirst,
}

/// Questions whose YES means medical clearance first (0-based): chest pain
/// (2), dizziness or loss of consciousness (3), and a doctor's instruction
/// to exercise only under supervision (7).
///
/// Basis: ACSM preparticipation screening (Riebe et al., Med Sci Sports
/// Exerc 2015): anyone with signs or symptoms suggestive of cardiovascular,
/// metabolic or renal disease should not start, or should stop, exercise
/// and seek medical clearance. Question 7 is itself a medical restriction.
/// Splitting the seven PAR-Q+ questions into these two groups is the
/// app's reading of that rule; the PAR-Q+ itself sends every YES to its
/// follow-up pages.
const Set<int> kParqClearanceFirst = {1, 2, 6};

ParqConcern parqConcern(List<bool>? answers) {
  if (answers == null || !answers.contains(true)) return ParqConcern.none;
  for (final i in kParqClearanceFirst) {
    if (i < answers.length && answers[i]) return ParqConcern.clearanceFirst;
  }
  return ParqConcern.followUp;
}

/// Guidance for each level. Wording only; the app changes no program
/// setting because of an answer, since no source says how it should.
String? parqAdvice(ParqConcern concern) => switch (concern) {
  ParqConcern.none => null,
  ParqConcern.followUp =>
    'You answered YES to a health question. Talk to a doctor or qualified '
        'exercise professional before becoming more active.',
  ParqConcern.clearanceFirst =>
    'Based on your answers, do not start exercising until a doctor clears you. '
        'If you have chest pain now, get medical care right away.',
};

/// "What does a typical day look like for you?"
///
/// Each answer sets [activityLevel] for nutrition. The FAO/WHO/UNU (2004)
/// categories are defined by lifestyle, so this mapping is an app choice:
/// both sitting answers count as sedentary or light (FAO's example is office
/// work with little strenuous activity), on your feet as active, and
/// physically demanding work as vigorous.
enum DailyRoutine {
  mostlySitting(
    'Mostly sitting',
    'Studying, office work, or sitting for most of the day',
    ActivityLevel.sedentaryOrLight,
  ),
  mixed(
    'A mix of sitting and moving',
    'Some walking and movement throughout the day',
    ActivityLevel.sedentaryOrLight,
  ),
  onFeet(
    'On my feet most of the day',
    'Standing, walking, or moving around frequently',
    ActivityLevel.active,
  ),
  demanding(
    'Physically demanding',
    'Manual labor, lifting, or strenuous physical work',
    ActivityLevel.vigorous,
  );

  const DailyRoutine(this.label, this.description, this.activityLevel);
  final String label;
  final String description;
  final ActivityLevel activityLevel;
}

/// "How much time can you realistically set aside for exercise?"
///
/// Each answer sets the session length used for programs. App choices, no
/// source: a range uses its upper end, "more than 60" uses 75 minutes, and
/// "not sure yet" uses the shortest answer.
enum TimeBudget {
  min20to30('20–30 minutes', SessionDuration.min30),
  min30to45('30–45 minutes', SessionDuration.min45),
  min45to60('45–60 minutes', SessionDuration.min60),
  over60('More than 60 minutes', SessionDuration.min75),
  notSure("I'm not sure yet", SessionDuration.min30);

  const TimeBudget(this.label, this.duration);
  final String label;
  final SessionDuration duration;

  /// The answer an older profile would have given, from its session length.
  static TimeBudget fromDuration(SessionDuration d) => switch (d) {
    SessionDuration.min15 || SessionDuration.min30 => min20to30,
    SessionDuration.min45 => min30to45,
    SessionDuration.min60 => min45to60,
    SessionDuration.min75 || SessionDuration.min90Plus => over60,
  };
}

/// Body areas with an injury or limitation. Used only to show a caution on
/// exercises that load the area; nothing is removed or swapped.
enum LimitationArea {
  shoulder('Shoulder'),
  lowerBack('Lower back'),
  knee('Knee'),
  hip('Hip'),
  wristElbow('Wrist or elbow');

  const LimitationArea(this.label);
  final String label;
}

/// Food the person does not eat. Shown with the nutrition targets so
/// protein sources can be chosen to fit; it changes no number.
enum DietPattern {
  noRestriction('No restrictions'),
  noPork('No pork'),
  noBeef('No beef'),
  pescatarian('Fish but no meat'),
  vegetarian('Vegetarian');

  const DietPattern(this.label);
  final String label;
}
