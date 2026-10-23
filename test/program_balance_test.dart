import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/data/setup_options.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/recommendation/personalization_service.dart';
import 'package:anthrofit/recommendation/prescription_rules.dart';
import 'package:anthrofit/recommendation/program_recommender.dart';
import 'package:anthrofit/recommendation/weekly_volume.dart';

import 'test_helpers.dart';

// Checks that days, schedule, session length, exercises, sets, reps, rest
// and weekly volume fit together, for every days x length combination.
// Run alone to see the weekly-volume table it prints:
//   flutter test test/program_balance_test.dart

const _rules = PrescriptionRules.standard;
const _recommender = ProgramRecommender();

UserProfile _profile(
  TrainingFrequency days,
  SessionDuration length,
  TrainingGoal goal, {
  ExperienceLevel experience = ExperienceLevel.intermediate,
}) => sampleProfile.copyWith(
  trainingFrequency: days,
  sessionDuration: length,
  goal: goal,
  experience: experience,
  equipment: const [EquipmentAccess.fullGym],
);

RecommendedProgram _build(UserProfile profile) => _recommender.recommend(
  profile: profile,
  setup: resolveSetup(profile: profile).setup,
);

void main() {
  useExerciseLibrary();

  const goals = [
    TrainingGoal.getStronger,
    TrainingGoal.buildMuscle,
    TrainingGoal.improveAthleticPerformance,
  ];

  test('the schedule has exactly the days asked for', () {
    for (final days in TrainingFrequency.values) {
      final p = _build(
        _profile(days, SessionDuration.min60, TrainingGoal.buildMuscle),
      ).program;
      expect(p.schedule.length, days.days, reason: days.label);
      expect(p.trainingDays.toSet().length, days.days, reason: days.label);
      for (final slot in p.schedule) {
        expect(p.workoutById(slot.workoutId), isNotNull);
      }
    }
  });

  test('every session is trained at least twice a week (ACSM 2009)', () {
    for (final days in TrainingFrequency.values) {
      final p = _build(
        _profile(days, SessionDuration.min60, TrainingGoal.buildMuscle),
      ).program;
      for (final w in p.workouts) {
        final times = p.schedule.where((s) => s.workoutId == w.id).length;
        expect(
          times,
          greaterThanOrEqualTo(2),
          reason: '${w.name} on ${days.days} days',
        );
      }
    }
  });

  test('no selected muscle is left out of a split', () {
    for (final days in TrainingFrequency.values) {
      final profile = _profile(
        days,
        SessionDuration.min60,
        TrainingGoal.buildMuscle,
      );
      final setup = resolveSetup(profile: profile).setup;
      final split = splitFor(days: days.days, focus: setup.focus);
      final covered = {
        for (final s in splitSessions(split, setup)) ...s.muscles,
      };
      expect(covered, setup.muscles.toSet(), reason: '${days.days} days');
      expect(covered, containsAll(musclesForFocus(TrainingFocus.fullBody)));
    }
  });

  test('every session fits the length chosen', () {
    for (final days in TrainingFrequency.values) {
      for (final length in SessionDuration.values) {
        for (final goal in [...goals, TrainingGoal.loseFat]) {
          final p = _build(_profile(days, length, goal)).program;
          for (final w in p.workouts) {
            final minutes = w.exercises.fold<double>(
              0,
              (sum, e) => sum + _rules.estimatedMinutes(e),
            );
            if (w.exercises.length > 1) {
              expect(
                minutes,
                lessThanOrEqualTo(length.minutes),
                reason: '${w.name}, ${days.days} days, ${length.label}, '
                    '${goal.label}: ${minutes.toStringAsFixed(1)} min',
              );
            }
          }
        }
      }
    }
  });

  test('sets, reps and rest match ACSM 2009 for the goal and level', () {
    for (final goal in goals) {
      for (final level in ExperienceLevel.values) {
        final p = _build(
          _profile(
            TrainingFrequency.three,
            SessionDuration.min60,
            goal,
            experience: level,
          ),
        );
        final (repMin, repMax) = _rules.repsFor(goal, level);
        for (final s in p.workouts) {
          for (final e in s.exercises) {
            if (e.exercise.exerciseType == ExerciseType.cardio) continue;
            final sets = e.planned.plannedSets;
            expect(sets.length, _rules.setsFor(goal, level));
            expect(sets.first.targetRepMin, repMin);
            expect(sets.first.targetRepMax, repMax);
            expect(
              sets.first.restSeconds,
              _rules.restFor(goal, level, e.exercise),
            );
          }
        }
      }
    }
  });

  test('upper and lower body both get direct sets every week', () {
    for (final length in [
      SessionDuration.min30,
      SessionDuration.min45,
      SessionDuration.min60,
    ]) {
      for (final days in TrainingFrequency.values) {
        final sets = weeklyDirectSets(
          _build(_profile(days, length, TrainingGoal.buildMuscle)).program,
        );
        for (final region in [MuscleRegion.upper, MuscleRegion.lower]) {
          final total = sets.entries
              .where((e) => e.key.region == region)
              .fold<int>(0, (sum, e) => sum + e.value);
          expect(
            total,
            greaterThan(0),
            reason: '${region.label}, ${days.days} days x ${length.label}',
          );
        }
      }
    }
  });

  test('weekly direct sets per muscle', () {
    final lines = <String>[];
    for (final length in [SessionDuration.min45, SessionDuration.min60]) {
      for (final days in TrainingFrequency.values) {
        final p = _build(
          _profile(days, length, TrainingGoal.buildMuscle),
        ).program;
        final sets = weeklyDirectSets(p);
        final freq = weeklyMuscleDays(p);
        final row = [
          for (final m in MuscleGroup.values)
            '${m.label} ${sets[m] ?? 0}/${freq[m] ?? 0}d',
        ].join(', ');
        lines.add('${days.days} days x ${length.label}: $row');
      }
    }
    expect(lines, isNotEmpty);
  });
}
