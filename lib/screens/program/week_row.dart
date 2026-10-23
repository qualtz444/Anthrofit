import 'package:flutter/material.dart';

import '../../models/models.dart';

/// A program's week, Monday to Sunday, as a row of boxes: each shows the
/// day and its workout, or "Rest". Today is outlined. Used on the Program
/// tab and on a program's own page.
class WeekRow extends StatelessWidget {
  const WeekRow({super.key, required this.program, required this.now});

  final TrainingProgram program;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final today = Weekday.fromDateTime(now);
    final training = program.trainingDays.toSet();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final day in Weekday.values) ...[
          if (day != Weekday.monday) const SizedBox(width: 4),
          Expanded(
            child: _DayBox(
              key: ValueKey('schedule-day-${day.name}'),
              day: day,
              isToday: day == today,
              // A training day with no workout left in the program.
              text: !training.contains(day)
                  ? 'Rest'
                  : program.workoutsForDay(day).isEmpty
                  ? 'Missing'
                  : program.workoutsForDay(day).map((w) => w.name).join(' · '),
              isRest: !training.contains(day),
            ),
          ),
        ],
      ],
    );
  }
}

class _DayBox extends StatelessWidget {
  const _DayBox({
    super.key,
    required this.day,
    required this.text,
    required this.isToday,
    required this.isRest,
  });

  final Weekday day;
  final String text;
  final bool isToday;
  final bool isRest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fill = isRest
        ? scheme.surfaceContainerHighest
        : scheme.primaryContainer;
    final ink = isRest ? scheme.onSurfaceVariant : scheme.onPrimaryContainer;

    return Semantics(
      label: '${day.label}${isToday ? ', today' : ''}: $text',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isToday ? scheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Text(
              day.shortLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: ink,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: ink,
                fontWeight: isRest ? FontWeight.w400 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
