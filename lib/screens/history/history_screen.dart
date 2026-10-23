import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/training_stats.dart';
import '../../state/session_scope.dart';
import '../widgets/empty_state.dart';
import 'history_calendar.dart';
import 'history_card.dart';

/// Completed workouts, two views of the same saved sessions:
/// a month calendar (tap a day) and a newest-first list.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late DateTime _month; // first day of the month on show
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = dateOnly(now);
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = SessionScope.of(context).completedSessions;
    final today = DateTime.now();

    if (sessions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('History')),
        body: const EmptyState(
          title: 'No completed workouts yet.',
          message: 'Complete a workout and it will appear here.',
        ),
      );
    }

    final byDate = sessionsByDate(sessions);
    final daySessions = byDate[_selected] ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          HistoryCalendar(
            month: _month,
            markedDates: byDate.keys.toSet(),
            selected: _selected,
            today: today,
            onSelect: (date) => setState(() => _selected = date),
            onPreviousMonth: () => _changeMonth(-1),
            onNextMonth: () => _changeMonth(1),
          ),
          const SizedBox(height: 16),
          Column(
            key: const ValueKey('selected-day-panel'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatDate(_selected, today: today),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (daySessions.isEmpty)
                Text(
                  'No workouts',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                for (final session in daySessions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: HistoryCard(session: session),
                  ),
            ],
          ),
          const SizedBox(height: 16),
          Text('All workouts', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final session in newestFirst(sessions))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: HistoryCard(
                key: ValueKey('history-card-${session.id}'),
                session: session,
              ),
            ),
        ],
      ),
    );
  }
}
