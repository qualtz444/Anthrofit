import 'package:flutter/material.dart';

import 'nutrition_targets_card.dart';

/// The nutrition targets on their own page, reached from Profile.
class NutritionTargetsScreen extends StatelessWidget {
  const NutritionTargetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nutrition')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [NutritionTargetsCard()],
      ),
    );
  }
}
