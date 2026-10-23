import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../widgets/muscle_image.dart';

/// Compact row for one exercise:
///   Name
///   Type · Movement pattern
///   Primary muscles
///
/// [selected] == null: normal row with a chevron.
/// [selected] true/false: shows a check circle (used when picking exercises).
/// [footer]: optional extra content under the muscles (the workout screen uses
/// it to show the planned sets, reps, rest, and note).
class ExerciseCard extends StatelessWidget {
  const ExerciseCard({
    super.key,
    required this.exercise,
    required this.onTap,
    this.selected,
    this.footer,
  });

  final Exercise exercise;
  final VoidCallback onTap;
  final bool? selected;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muscles = exercise.primaryMuscles.map((m) => m.label).join(', ');
    final isSelected = selected ?? false;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // The main target muscle, pictured.
              if (exercise.primaryMuscles.isNotEmpty) ...[
                MuscleImage(exercise.primaryMuscles.first, size: 48),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${exercise.exerciseType.label} · ${exercise.movementPattern.label}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(muscles, style: theme.textTheme.bodyMedium),
                    if (footer != null) ...[const SizedBox(height: 6), footer!],
                  ],
                ),
              ),
              if (selected == null)
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              else
                Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
