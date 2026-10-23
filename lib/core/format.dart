import 'units.dart';

/// 170.0 -> "170", 65.5 -> "65.5". Used for height/weight display and inputs.
String formatNumber(double value) {
  if (!value.isFinite) return '—'; // never show NaN or Infinity
  final rounded = (value * 10).round() / 10;
  return rounded == rounded.roundToDouble()
      ? rounded.round().toString()
      : rounded.toStringAsFixed(1);
}

/// pluralize(1, 'set') -> "1 set", pluralize(3, 'set') -> "3 sets"
String pluralize(int count, String noun) =>
    count == 1 ? '1 $noun' : '$count ${noun}s';

/// 90 -> "01:30"
String formatClock(int totalSeconds) {
  final seconds = totalSeconds < 0 ? 0 : totalSeconds;
  final m = (seconds ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// "Less than 1 min", "47 min", "1 h 5 min", "2 h"
String formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  if (minutes < 1) return 'Less than 1 min';
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours h' : '$hours h $rest min';
}

const List<String> _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String monthName(int month) => _monthNames[month - 1];

String shortMonthName(int month) => monthName(month).substring(0, 3);

/// "October 2026"
String formatMonthYear(DateTime date) =>
    '${monthName(date.month)} ${date.year}';

/// "Oct 5"
String formatShortDate(DateTime date) =>
    '${shortMonthName(date.month)} ${date.day}';

/// "October 5", or "October 5, 2025" when the year is not [today]'s year.
String formatDate(DateTime date, {required DateTime today}) {
  final base = '${monthName(date.month)} ${date.day}';
  return date.year == today.year ? base : '$base, ${date.year}';
}

/// 12450 -> "12,450", 382.5 -> "382.5". Rounded to one decimal place.
String formatThousands(double value) {
  if (!value.isFinite) return '—';
  final rounded = (value * 10).round() / 10;
  final isWhole = rounded == rounded.roundToDouble();
  final text = isWhole
      ? rounded.round().toString()
      : rounded.toStringAsFixed(1);
  final parts = text.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (match) => ',',
  );
  return parts.length > 1 ? '$whole.${parts[1]}' : whole;
}

/// "12,450 kg"
/// Total load lifted. [units] only changes how it reads: volume is always
/// worked out in kilograms.
String formatVolume(double kg, [WeightUnit units = WeightUnit.kg]) =>
    units.isMetric
    ? '${formatThousands(kg)} kg'
    : '${formatThousands(poundsFromKg(kg))} lb';

/// "Today", "Yesterday", otherwise like [formatDate].
String formatRelativeDate(DateTime date, {required DateTime today}) {
  final day = DateTime(date.year, date.month, date.day);
  final now = DateTime(today.year, today.month, today.day);
  if (day == now) return 'Today';
  if (day == DateTime(now.year, now.month, now.day - 1)) return 'Yesterday';
  return formatDate(date, today: today);
}

/// Greeting for the Home screen. Before noon is morning, before 6 pm is
/// afternoon, otherwise evening.
String greetingFor(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}
