import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/training_stats.dart';
import '../../models/models.dart';

/// "2026-10-05". Used in widget keys so tests (and nothing else) can find a day.
String calendarDateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One month, Monday first. Days with a completed workout get a dot.
/// It only draws what it is given; it does not read any data itself.
class HistoryCalendar extends StatelessWidget {
  const HistoryCalendar({
    super.key,
    required this.month,
    required this.markedDates,
    required this.selected,
    required this.today,
    required this.onSelect,
    required this.onPreviousMonth,
    required this.onNextMonth,
  });

  /// Any date in the month to show.
  final DateTime month;

  /// Dates (midnight) that have at least one completed workout.
  final Set<DateTime> markedDates;
  final DateTime? selected;
  final DateTime today;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday - 1; // blank cells before the 1st
    final rows = (leading + daysInMonth + 6) ~/ 7;

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              icon: const Icon(Icons.chevron_left),
              onPressed: onPreviousMonth,
            ),
            Expanded(
              child: Center(
                child: Text(
                  formatMonthYear(first),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              icon: const Icon(Icons.chevron_right),
              onPressed: onNextMonth,
            ),
          ],
        ),
        Row(
          children: [
            for (final day in Weekday.values)
              Expanded(
                child: Center(
                  child: Text(
                    day.shortLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var row = 0; row < rows; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: _buildCell(
                    context,
                    row * 7 + col - leading + 1,
                    daysInMonth,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildCell(BuildContext context, int dayNumber, int daysInMonth) {
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox(height: 48);
    }
    final theme = Theme.of(context);
    final date = DateTime(month.year, month.month, dayNumber);
    final isMarked = markedDates.contains(date);
    final isSelected = selected == date;
    final isToday = date == dateOnly(today);
    final key = calendarDateKey(date);

    return SizedBox(
      height: 48,
      child: Semantics(
        button: true,
        selected: isSelected,
        excludeSemantics: true,
        label:
            '${monthName(date.month)} $dayNumber${isMarked ? ', workout completed' : ''}',
        child: InkWell(
          key: ValueKey('calendar-day-$key'),
          customBorder: const CircleBorder(),
          onTap: () => onSelect(date),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? theme.colorScheme.primary : null,
                  border: isToday && !isSelected
                      ? Border.all(color: theme.colorScheme.primary)
                      : null,
                ),
                child: Text(
                  '$dayNumber',
                  style: TextStyle(
                    color: isSelected ? theme.colorScheme.onPrimary : null,
                    fontWeight: isMarked ? FontWeight.w700 : null,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                width: 6,
                height: 6,
                child: isMarked
                    ? DecoratedBox(
                        key: ValueKey('calendar-marker-$key'),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
