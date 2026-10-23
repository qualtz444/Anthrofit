import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../recommendation/personalization_service.dart';
import '../../recommendation/program_recommender.dart';
import '../../state/exercise_library_scope.dart';
import '../../state/profile_scope.dart';
import '../../state/program_scope.dart';
import 'personalized_plan_screen.dart';

/// The short pause between "Generate My Program" and the Personalized Plan.
///
/// This is a transition and nothing more. Building the program takes
/// milliseconds and is already done by the time the screen appears; the delay
/// only keeps the change of screen from feeling like a flicker, so it does
/// not claim to be doing heavy work.
///
/// Back-safe: leaving during the pause cancels the timer, and nothing is
/// built into the user's programs either way. Saving only ever happens from
/// the Personalized Plan, when the user confirms.
class PersonalizeProgramScreen extends StatefulWidget {
  const PersonalizeProgramScreen({
    super.key,
    this.measurement,
    this.goal,
    this.baseProgram,
    this.recommender = kAppRecommender,
    this.delay = const Duration(milliseconds: 1500),
  });

  /// The scan just taken, handed to the recommender. Whether it influences
  /// anything is the recommender's call, and is reported on the plan.
  final Measurement? measurement;

  /// The goal to build for, when the user just chose one (from a body
  /// composition result). Null keeps the usual setup's goal.
  final TrainingGoal? goal;

  /// Rebuild THIS program instead of planning from the active one: its own
  /// setup is used, and the plan offers to update it in place.
  final TrainingProgram? baseProgram;

  final ProgramRecommender recommender;

  /// How long the transition lasts. Tests shorten it.
  final Duration delay;

  @override
  State<PersonalizeProgramScreen> createState() =>
      _PersonalizeProgramScreenState();
}

class _PersonalizeProgramScreenState extends State<PersonalizeProgramScreen> {
  late final PersonalizationOutcome _outcome;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Worked out straight away: it is fast, and a failure should show at once
    // rather than after a pause that was only ever for show.
    _outcome = personalizeProgram(
      profile: ProfileScope.of(context, listen: false).profile,
      activeProgram:
          widget.baseProgram ??
          ProgramScope.of(context, listen: false).activeProgram,
      measurement: widget.measurement,
      goal: widget.goal,
      recommender: widget.recommender,
      catalogError: ExerciseLibraryScope.of(
        context,
        listen: false,
      ).catalogError,
    );
    if (_outcome.succeeded) _timer = Timer(widget.delay, _showPreview);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _showPreview() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PersonalizedPlanScreen(
          recommended: _outcome.recommended!,
          source: _outcome.source!,
          updateProgramId: widget.baseProgram?.id,
        ),
      ),
    );
  }

  void _backToHome() =>
      Navigator.of(context).popUntil((route) => route.isFirst);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failure = _outcome.failure;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: failure != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 48,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Couldn't build a program",
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        failure,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _backToHome,
                        child: const Text('Back to Home'),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 24),
                      Text(
                        'Building your personalized plan…',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'A training program from your current setup, and '
                        'nutrition targets from your profile.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
