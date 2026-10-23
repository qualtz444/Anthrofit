import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/training_stats.dart';
import '../../models/models.dart';
import 'workout_history_detail_screen.dart';

/// One completed workout in a list. Tap to open its detail.
///   Upper A
///   October 5
///   47 min · 4 exercises · 12 sets
class HistoryCard extends StatelessWidget {
  const HistoryCard({super.key, required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = session.duration ?? Duration.zero;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => WorkoutHistoryDetailScreen(session: session),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.workoutName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatDate(sessionDate(session), today: DateTime.now()),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '${formatDuration(duration)} · ${pluralize(exerciseCountOf(session), 'exercise')} · ${pluralize(session.completedSetCount, 'set')}',
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
    );
  }
}
