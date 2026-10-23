import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../nutrition/meal_plan.dart';
import '../../nutrition/nutrition_targets.dart';
import 'nutrition_targets_summary.dart';

/// A sample day of meals on the Pinggang Pinoy plate, fitted to the
/// person's diet and allergy answers. "Another day" shows a different mix.
class SampleDayScreen extends StatefulWidget {
  const SampleDayScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<SampleDayScreen> createState() => _SampleDayScreenState();
}

class _SampleDayScreenState extends State<SampleDayScreen> {
  // Starts from today's date, so the first day shown changes daily.
  late int _day = SampleDayView.today;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Example meals')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            key: const ValueKey('another-day'),
            onPressed: () => setState(() => _day++),
            icon: const Icon(Icons.refresh),
            label: const Text('Show another example'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [SampleDayView(profile: widget.profile, dayIndex: _day)],
      ),
    );
  }
}

/// The example meals for one day, with what they are and are not. Used by
/// the Example meals page and the Personalized Plan's Nutrition tab.
class SampleDayView extends StatelessWidget {
  const SampleDayView({
    super.key,
    required this.profile,
    required this.dayIndex,
    this.showTargets = true,
  });

  final UserProfile profile;
  final int dayIndex;

  /// Off where the daily targets are already shown above, so the energy and
  /// macro summary is not repeated.
  final bool showTargets;

  /// The first day to show: today's date, so the example changes daily.
  static int get today => DateTime.now().difference(DateTime(2026)).inDays;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meals = sampleDay(profile, dayIndex);
    final targets = nutritionTargetsFor(profile);
    final hasFoodPreferences =
        profile.dietPattern != null || profile.foodAllergies.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          key: const ValueKey('example-label'),
          margin: const EdgeInsets.only(bottom: 12),
          color: theme.colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Example meals, not a prescribed diet. Adjust portions to '
              'your daily targets.',
              style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
        ),
        if (hasFoodPreferences)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Foods reflect your saved preferences. Check ingredients for '
              'allergens.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (targets != null) ...[
          if (showTargets) ...[
            NutritionTargetsSummary(targets: targets),
            const SizedBox(height: 8),
          ],
          Text(
            'Evenly split across three meals: about '
            '${(targets.proteinGLow / 3).round()}–'
            '${(targets.proteinGHigh / 3).round()} g protein each.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final meal in meals)
          Card(
            key: ValueKey('sample-meal-${meal.name.toLowerCase()}'),
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Text(meal.name, style: theme.textTheme.titleMedium),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _MealGroupCard(
                          title: '½ plants',
                          icon: Icons.eco_outlined,
                          color: theme.colorScheme.tertiaryContainer,
                          foods: [
                            for (final group in [
                              PlateGroup.vegetable,
                              PlateGroup.fruit,
                            ])
                              if (meal.foods[group] case final food?) food.name,
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _MealGroupCard(
                          title: '⅓ staples',
                          icon: Icons.rice_bowl_outlined,
                          color: theme.colorScheme.secondaryContainer,
                          foods: [
                            if (meal.foods[PlateGroup.go] case final food?)
                              food.name,
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _MealGroupCard(
                          title: '⅙ protein',
                          icon: Icons.restaurant_outlined,
                          color: theme.colorScheme.primaryContainer,
                          foods: [
                            if (meal.foods[PlateGroup.grow] case final food?)
                              food.name,
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MealGroupCard extends StatelessWidget {
  const _MealGroupCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.foods,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<String> foods;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18),
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            for (final food in foods)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(food, style: theme.textTheme.labelSmall),
              ),
          ],
        ),
      ),
    );
  }
}
