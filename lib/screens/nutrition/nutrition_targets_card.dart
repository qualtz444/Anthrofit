import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../intelligence/ai_explainer.dart';
import '../../models/models.dart';
import '../../nutrition/nutrition_targets.dart';
import 'nutrition_targets_summary.dart';
import '../../state/profile_scope.dart';
import '../widgets/ai_explain_button.dart';
import 'sample_day_screen.dart';
import '../../core/snack_bar_timing.dart';

/// Daily energy and protein targets plus the Pinggang Pinoy plate, from the
/// saved profile. Asks for daily activity first if it has not been answered,
/// and saves the answer to the profile.
///
/// Renders nothing where there is no profile scope or no profile.
class NutritionTargetsCard extends StatelessWidget {
  const NutritionTargetsCard({super.key, this.showExampleMealsLink = true});

  /// Off where the example meals are already shown below the card.
  final bool showExampleMealsLink;

  Future<void> _setActivity(
    BuildContext context,
    UserProfile profile,
    ActivityLevel level,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = ProfileScope.of(context, listen: false);
    try {
      await controller.save(profile.copyWith(activityLevel: level));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(duration: kSnackBarDuration, persist: false, content: Text("Couldn't save your activity level.")),
      );
    }
  }

  static String? _foodNote(UserProfile profile) {
    final parts = [
      if (profile.dietPattern case final d? when d != DietPattern.noRestriction)
        d.label,
      if (profile.foodAllergies.isNotEmpty)
        'allergic to ${profile.foodAllergies}',
    ];
    if (parts.isEmpty) return null;
    return 'You noted: ${parts.join('; ')}. Pick protein and other foods '
        'that fit.';
  }

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ProfileScope>();
    final profile = scope?.notifier?.profile;
    if (profile == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final blocker = nutritionBlocker(profile);
    final targets = nutritionTargetsFor(profile);

    return Card(
      key: const ValueKey('nutrition-targets'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your daily targets',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            if (targets != null) ...[
              NutritionTargetsSummary(targets: targets),
              const SizedBox(height: 12),
            ],
            if (targets == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  blocker ?? '',
                  key: const ValueKey('nutrition-blocker'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            Text(
              'Activity outside your workouts',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final level in ActivityLevel.values)
                  Tooltip(
                    message: level.description,
                    child: FilterChip(
                      key: ValueKey('activity-${level.name}'),
                      label: Text(level.label),
                      selected: profile.activityLevel == level,
                      onSelected: (_) => _setActivity(context, profile, level),
                    ),
                  ),
              ],
            ),
            // From setup's food questions. Wording only; no number changes.
            if (_foodNote(profile) case final note?)
              Padding(
                key: const ValueKey('food-note'),
                padding: const EdgeInsets.only(top: 8),
                child: Text(note, style: theme.textTheme.bodyMedium),
              ),
            if (targets != null) ...[
              const SizedBox(height: 8),
              _TargetDetails(targets: targets, profile: profile),
              const SizedBox(height: 12),
              const _PlateGuide(),
              if (showExampleMealsLink)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const ValueKey('sample-day'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SampleDayScreen(profile: profile),
                        ),
                      ),
                      icon: const Icon(Icons.restaurant_menu),
                      label: const Text('Explore example meals'),
                    ),
                  ),
                ),
              AiExplainButton(
                request: ExplainRequest(
                  kind: ExplainKind.nutrition,
                  goal: profile.goal.label,
                  facts: [
                    'Maintenance: ${_kcal(targets.maintenanceKcalLow)}–'
                        '${_kcal(targets.maintenanceKcalHigh)} kcal a day, '
                        'resting energy by ${targets.bmrMethod.label}.',
                    'Daily target for the goal: '
                        '${_kcal(targets.targetKcalLow)}–'
                        '${_kcal(targets.targetKcalHigh)} kcal.',
                    'Protein ${targets.proteinGLow.round()}–'
                        '${targets.proteinGHigh.round()} g, fat '
                        '${targets.fatGLow.round()}–${targets.fatGHigh.round()} '
                        'g, carbohydrate about ${targets.carbsG.round()} g a day.',
                    targets.composition == null
                        ? 'Based on body weight only, no body composition scan.'
                        : 'Uses the body composition estimate'
                              '${targets.category == null ? '' : ' (${targets.category!.label} range)'}.',
                    'These are estimates from population equations. The app '
                        'does not log food, so it cannot tell whether the '
                        'targets are being followed.',
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text('Estimates, not a meal prescription.', style: muted),
          ],
        ),
      ),
    );
  }
}

class _TargetDetails extends StatelessWidget {
  const _TargetDetails({required this.targets, required this.profile});

  final NutritionTargets targets;
  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final composition = targets.composition;
    return ExpansionTile(
      key: const ValueKey('nutrition-target-details'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: const Text('Goal & calculation'),
      children: [
        const SizedBox(height: 4),
        _DetailBox(
          label: 'Maintenance estimate',
          value:
              '${_kcal(targets.maintenanceKcalLow)}–'
              '${_kcal(targets.maintenanceKcalHigh)} kcal/day',
          note: '${targets.bmrMethod.label}, adjusted for your activity.',
        ),
        const SizedBox(height: 8),
        _goalBox(targets, profile),
        const SizedBox(height: 8),
        _DetailBox(
          label: 'Macro basis',
          value: targets.proteinFromLeanMass
              ? 'Protein from estimated lean mass'
              : 'Protein from body weight',
          note: 'Fat is 20–35% of calories; carbs fill the rest.',
        ),
        const SizedBox(height: 12),
        Text(
          composition == null
              ? 'Based on body weight; a body-composition scan can make the '
                    'estimate more specific.'
              : 'Uses your body-composition estimate from '
                    '${formatDate(composition.takenAt, today: DateTime.now())}'
                    '${targets.category == null ? '' : ' (${targets.category!.label} range)'}.',
          key: const ValueKey('nutrition-basis'),
          style: muted,
        ),
      ],
    );
  }

  Widget _goalBox(NutritionTargets targets, UserProfile profile) {
    switch (targets.advice) {
      case EnergyAdvice.surplus:
        return _DetailBox(
          label: 'Goal adjustment',
          value: profile.experience == ExperienceLevel.advanced
              ? 'About 10% above maintenance'
              : 'About 10–20% above maintenance',
        );
      case EnergyAdvice.deficit:
        return _DetailBox(
          label: 'Goal adjustment',
          value: targets.deficitBasis == DeficitBasis.rate
              ? 'A gradual weekly weight-loss rate'
              : '500–750 kcal below maintenance',
          note: targets.deficitBasis == DeficitBasis.rate
              ? 'About 0.5–1% of body weight per week.'
              : null,
        );
      case EnergyAdvice.maintain:
        return const _DetailBox(
          label: 'Goal adjustment',
          value: 'Eat around maintenance',
        );
    }
  }
}

class _PlateGuide extends StatelessWidget {
  const _PlateGuide();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      key: const ValueKey('simple-plate-guide'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('A simple plate guide', style: theme.textTheme.titleSmall),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _PlatePart(
                fraction: '½',
                label: 'Plants',
                description: 'Vegetables + fruit',
                icon: Icons.eco_outlined,
                color: scheme.tertiaryContainer,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PlatePart(
                fraction: '⅓',
                label: 'Staples',
                description: 'Grains + starches',
                icon: Icons.rice_bowl_outlined,
                color: scheme.secondaryContainer,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PlatePart(
                fraction: '⅙',
                label: 'Protein',
                description: 'Fish, meat, eggs or beans',
                icon: Icons.restaurant_outlined,
                color: scheme.primaryContainer,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlatePart extends StatelessWidget {
  const _PlatePart({
    required this.fraction,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String fraction;
  final String label;
  final String description;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      key: ValueKey('plate-part-$fraction'),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18),
            const SizedBox(height: 6),
            Text(
              fraction,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(label, style: theme.textTheme.labelLarge),
            const SizedBox(height: 2),
            Text(description, style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

/// 2345.6 -> "2,346"
String _kcal(double value) {
  final digits = value.round().toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

class _DetailBox extends StatelessWidget {
  const _DetailBox({required this.label, required this.value, this.note});

  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 2),
            Text(note!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
