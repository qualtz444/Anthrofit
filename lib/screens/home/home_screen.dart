import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/training_stats.dart';
import '../../models/models.dart';
import '../../state/profile_scope.dart';
import '../../state/session_scope.dart';
import '../exercises/exercise_library_screen.dart';
import '../history/history_screen.dart';
import '../history/workout_history_detail_screen.dart';
import '../session/start_workout.dart';
import '../../auth/auth_scope.dart';
import '../community/community_screen.dart';
import '../community/inbox_screen.dart';
import '../body_analysis/body_analysis_screen.dart';
import '../nutrition/nutrition_targets_screen.dart';
import '../scan/scan_choice_screen.dart';
import '../widgets/today_workout_card.dart';

/// Starting point: greeting, what to do today, and a short look back.
/// Every number is calculated from saved sessions (see training_stats.dart).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// If the app was left open overnight, "today" must be recalculated.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = ProfileScope.of(context).profile?.name.trim() ?? '';
    final sessions = SessionScope.of(context).completedSessions;
    final now = DateTime.now();

    final greeting = name.isEmpty
        ? greetingFor(now.hour)
        : '${greetingFor(now.hour)}, $name';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          // Notifications only exist for accounts, not guests.
          if (_signedInUid(context) case final uid?) InboxBell(uid: uid),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            greeting,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          // PAR-Q+ asks anyone with a YES to check first; the app reminds
          // rather than blocks.
          if (ProfileScope.of(context).profile case final p?
              when p.parqLevel != ParqConcern.none && !p.medicallyCleared) ...[
            Card(
              key: const ValueKey('parq-reminder'),
              margin: EdgeInsets.zero,
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      parqAdvice(p.parqLevel)!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('parq-cleared'),
                      onPressed: () => ProfileScope.of(
                        context,
                        listen: false,
                      ).save(p.copyWith(medicallyCleared: true)),
                      child: const Text('A doctor has cleared me to exercise'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          TodayWorkoutCard(now: now),
          const SizedBox(height: 12),
          // Train something that is not in any program: pick an exercise and
          // start. Nothing is added to the user's programs.
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _startQuickWorkout(context),
              icon: const Icon(Icons.bolt_outlined),
              label: const Text('Quick workout'),
            ),
          ),
          const SizedBox(height: 12),
          // Every main feature one tap from Home, so nothing has to be
          // hunted for in menus or other tabs.
          Text('Quick access', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          const _QuickAccess(),
          const SizedBox(height: 24),
          if (sessions.isEmpty)
            Text(
              'No completed workouts yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ..._recent(context, sessions, now),
        ],
      ),
    );
  }

  List<Widget> _recent(
    BuildContext context,
    List<WorkoutSession> sessions,
    DateTime now,
  ) {
    final theme = Theme.of(context);
    final latest = newestFirst(sessions).first;
    final streak = weekStreaks(sessions, now);

    // Recent progress: the first exercise of the latest workout, shown as its
    // best logged set that day.
    final log = latest.exerciseLogs
        .where((l) => workSetsOf(l).isNotEmpty)
        .firstOrNull;
    final best = log == null
        ? null
        : ExerciseEntry(
            date: sessionDate(latest),
            exerciseName: log.exerciseName,
            sets: workSetsOf(log),
          ).bestSet;

    return [
      if (log != null && best != null) ...[
        const _SectionLabel('Recent progress'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.exerciseName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(formatSetLog(best)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
      const _SectionLabel('Recent activity'),
      Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => WorkoutHistoryDetailScreen(session: latest),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        latest.workoutName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${formatRelativeDate(sessionDate(latest), today: now)} · ${formatDuration(latest.duration ?? Duration.zero)}',
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'This week: ${pluralize(workoutsInWeekOf(sessions, now), 'workout')} · Current streak: ${pluralize(streak.current, 'week')}',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const HistoryScreen()),
            );
          },
          child: const Text('View history'),
        ),
      ),
    ];
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Pick one exercise from the library and start it straight away.
Future<void> _startQuickWorkout(BuildContext context) async {
  final picked = await Navigator.of(context).push<List<Exercise>>(
    MaterialPageRoute<List<Exercise>>(
      builder: (_) => const ExerciseLibraryScreen(pickMode: true),
    ),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;
  await startQuickWorkout(context, exercise: picked.first);
}

/// The signed-in account's id, or null for guests and tests without accounts.
String? _signedInUid(BuildContext context) {
  final auth = context
      .dependOnInheritedWidgetOfExactType<AuthScope>()
      ?.notifier;
  if (auth == null || auth.isGuest) return null;
  return auth.user?.uid;
}

/// Shortcuts to the main features, in a 3 x 2 grid.
class _QuickAccess extends StatelessWidget {
  const _QuickAccess();

  @override
  Widget build(BuildContext context) {
    void open(Widget screen) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    final tiles = <(String, IconData, String, Widget)>[
      (
        'quick-scan',
        Icons.center_focus_strong,
        'Scan',
        const ScanChoiceScreen(),
      ),
      (
        'quick-body',
        Icons.accessibility_new,
        'Body analysis',
        const BodyAnalysisScreen(),
      ),
      (
        'quick-nutrition',
        Icons.restaurant_outlined,
        'Nutrition',
        const NutritionTargetsScreen(),
      ),
      ('quick-history', Icons.history, 'History', const HistoryScreen()),
      (
        'open-community',
        Icons.groups_outlined,
        'Community',
        const CommunityScreen(),
      ),
      (
        'quick-exercises',
        Icons.fitness_center,
        'Exercises',
        const ExerciseLibraryScreen(),
      ),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.1,
      children: [
        for (final t in tiles)
          _QuickTile(
            key: ValueKey(t.$1),
            icon: t.$2,
            label: t.$3,
            onTap: () => open(t.$4),
          ),
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 28),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
