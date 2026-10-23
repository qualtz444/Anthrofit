import 'package:flutter/material.dart';

import '../exercises/exercise_library_screen.dart';
import 'program_library_screen.dart';

/// Where ready-made training content lives.
///
///   Programs   ready-made programs to copy into your own
///   Exercises  the existing exercise library
///
/// Separate from Create program, which asks about you and builds something
/// to fit. The Library is for taking something off the shelf.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Ready-made programs and the full exercise list. Anything you '
              'take from here becomes yours to edit.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.library_books_outlined),
            title: const Text('Programs'),
            subtitle: const Text('Ready-made programs you can copy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ProgramLibraryScreen(),
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.fitness_center),
            title: const Text('Exercises'),
            subtitle: const Text('Browse every exercise'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ExerciseLibraryScreen(),
              ),
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}
