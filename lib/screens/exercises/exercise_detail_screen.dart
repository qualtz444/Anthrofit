import 'package:flutter/material.dart';

import '../../content/app_content.dart';
import '../../intelligence/ai_explainer.dart';
import '../widgets/ai_explain_button.dart';

import '../../core/set_labels.dart';
import '../../models/models.dart';
import '../library/add_exercise_actions.dart';
import '../session/start_workout.dart';
import '../widgets/chip_row.dart';
import '../widgets/muscle_image.dart';

/// The exercise itself: classification, muscles, equipment, difficulty,
/// instructions. This is the reusable definition from the library.
///
/// If the user arrived from a workout, pass [planned] to also show a small
/// read-only "This workout" section. The Exercise is never modified and the
/// prescription is never stored on it.
class ExerciseDetailScreen extends StatelessWidget {
  const ExerciseDetailScreen({
    super.key,
    required this.exercise,
    this.planned,
    this.canStart = true,
    this.whyPrescription,
  });

  /// Why the sets, reps and rest are what they are, for this program's goal.
  final String? whyPrescription;

  final Exercise exercise;
  final PlannedExercise? planned;

  /// Offers "Start this exercise", which begins a one-exercise session with
  /// no program behind it. Off when the screen is reached from inside a
  /// workout that is already running.
  final bool canStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = planned;

    return Scaffold(
      appBar: AppBar(title: const Text('Exercise')),
      bottomNavigationBar: canStart
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            showAddExerciseSheet(context, exercise: exercise),
                        child: const Text('Add to…'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: () =>
                            startQuickWorkout(context, exercise: exercise),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start this exercise'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              exercise.name,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              exercise.movementPattern.label,
              style: theme.textTheme.titleMedium,
            ),
            Text(
              exercise.exerciseType.label,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            // Muscles are pictured so the target is visible. Primary is
            // outlined, secondary plain, so the difference shows at a glance.
            _DetailSection(
              title: 'Primary muscles',
              child: MuscleGallery(
                muscles: exercise.primaryMuscles,
                emphasised: true,
              ),
            ),
            _DetailSection(
              title: 'Secondary muscles',
              child: MuscleGallery(
                muscles: exercise.secondaryMuscles,
                size: 44,
                emptyText: 'None',
              ),
            ),
            _DetailSection(
              title: 'Equipment',
              child: ChipRow(
                labels: [
                  for (final e in exercise.equipment) e.label,
                  for (final id in exercise.extraEquipment)
                    AppContent.equipmentLabel(id),
                ],
              ),
            ),
            // Experience and complexity are ordered three-step scales, so
            // stars read faster than a word. The enum order is the rating.
            _DetailSection(
              title: 'Experience',
              child: Row(
                children: [
                  StarRating(filled: exercise.experienceLevel.index + 1),
                  const SizedBox(width: 8),
                  Text(exercise.experienceLevel.label),
                ],
              ),
            ),
            _DetailSection(
              title: 'Complexity',
              child: Row(
                children: [
                  StarRating(filled: exercise.complexity.index + 1),
                  const SizedBox(width: 8),
                  Text(exercise.complexity.label),
                ],
              ),
            ),
            _DetailSection(
              title: 'Instructions',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < exercise.instructions.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 24, child: Text('${i + 1}.')),
                          Expanded(child: Text(exercise.instructions[i])),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (plan != null)
              _DetailSection(
                title: 'This workout',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final set in plan.plannedSets)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 84,
                              child: Text(
                                set.setType.shortLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(child: Text(plannedSetDetails(set))),
                          ],
                        ),
                      ),
                    if (plan.note.isNotEmpty) Text(plan.note),
                  ],
                ),
              ),
            if (whyPrescription != null)
              _DetailSection(
                title: 'Why these sets, reps and rest',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      whyPrescription!,
                      key: const ValueKey('why-prescription'),
                    ),
                    AiExplainButton(
                      request: ExplainRequest(
                        kind: ExplainKind.tutorial,
                        facts: [
                          'Exercise: ${exercise.name}',
                          'Primary muscles: ${exercise.primaryMuscles.map((m) => m.label).join(', ')}',
                          whyPrescription!,
                          if (plan != null && plan.note.isNotEmpty) plan.note,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          DefaultTextStyle.merge(
            style: theme.textTheme.bodyLarge,
            child: child,
          ),
        ],
      ),
    );
  }
}
