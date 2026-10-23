import 'package:flutter/material.dart';

import '../../data/ready_made_programs.dart';
import 'ready_made_program_screen.dart';

/// The ready-made programs on offer. Tapping one shows what it contains
/// before anything is added.
class ProgramLibraryScreen extends StatelessWidget {
  const ProgramLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Programs')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Adding one makes your own copy. Editing it later never changes '
            'the original.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final recipe in readyMadePrograms())
            Card(
              key: ValueKey('ready-${recipe.id}'),
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                  recipe.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${recipe.summary}\n'
                  '${recipe.goal.label} · ${recipe.experience.label} · '
                  '${recipe.days.length} days a week',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReadyMadeProgramScreen(recipe: recipe),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
