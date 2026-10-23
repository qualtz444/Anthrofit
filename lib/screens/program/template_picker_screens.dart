import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/workout_templates.dart';

/// Step 1 of a new workout. Pops with the chosen WorkoutTemplate.
class WorkoutTemplateScreen extends StatelessWidget {
  const WorkoutTemplateScreen({super.key});

  static String _subtitle(WorkoutTemplate template) {
    if (template == WorkoutTemplate.custom) {
      return 'Name it and add exercises yourself';
    }
    if (template.currentExerciseIds.isEmpty) {
      return 'No ${template.label.toLowerCase()} exercises in the library yet';
    }
    return 'Starts with '
        '${pluralize(template.currentExerciseIds.length, 'exercise')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a workout type')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final template in WorkoutTemplate.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  title: Text(
                    template.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(_subtitle(template)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).pop(template),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
