import 'package:flutter/material.dart';

import '../../state/measurement_scope.dart';
import '../../state/profile_scope.dart';
import '../../state/program_scope.dart';
import '../../state/session_scope.dart';
import '../program/create_program_screen.dart';
import '../scan/scan_choice_screen.dart';

/// A first-time user: no programs, no scans of either kind and no finished
/// workouts yet. They are pointed at a scan first rather than at creating a
/// program. False until the scans have loaded, so the prompt never flashes.
bool isFirstTimeUser(BuildContext context) {
  final programs = context
      .dependOnInheritedWidgetOfExactType<ProgramScope>()
      ?.notifier;
  if (programs == null || programs.programs.isNotEmpty) return false;
  final scans = context
      .dependOnInheritedWidgetOfExactType<MeasurementScope>()
      ?.notifier;
  if (scans == null || !scans.isLoaded || scans.measurements.isNotEmpty) {
    return false;
  }
  final profile = context
      .dependOnInheritedWidgetOfExactType<ProfileScope>()
      ?.notifier
      ?.profile;
  if (profile != null && profile.compositionLog.isNotEmpty) return false;
  final sessions = context
      .dependOnInheritedWidgetOfExactType<SessionScope>()
      ?.notifier;
  return sessions == null || sessions.completedSessions.isEmpty;
}

/// For first-time users, in place of "Create program": a scan first, with
/// setting a program up by hand still possible underneath.
class FirstScanPrompt extends StatelessWidget {
  const FirstScanPrompt({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        key: const ValueKey('first-scan-prompt'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.center_focus_strong,
            size: 40,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Run your first scan to personalize your training. It checks your '
            'proportions and body composition, then suggests a program.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('first-scan-cta'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ScanChoiceScreen()),
            ),
            icon: const Icon(Icons.center_focus_strong),
            label: const Text('Run your first scan'),
          ),
          TextButton(
            key: const ValueKey('create-program'),
            onPressed: () => startProgramCreation(context),
            child: const Text('Set up a program myself'),
          ),
        ],
      ),
    );
  }
}
