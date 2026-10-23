import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Whether to remind the user on training days, and at what time.
///
/// Kept on this phone only, like the theme: notifications are shown by this
/// phone, so the setting belongs to it, not to the account.
class ReminderSettings {
  const ReminderSettings({
    this.enabled = false,
    this.hour = kDefaultReminderHour,
    this.minute = 0,
  });

  final bool enabled;
  final int hour;
  final int minute;

  ReminderSettings copyWith({bool? enabled, int? hour, int? minute}) =>
      ReminderSettings(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );

  String encode() => '${enabled ? 1 : 0}|$hour|$minute';

  static ReminderSettings decode(String? raw) {
    final parts = raw?.split('|');
    if (parts == null || parts.length != 3) return const ReminderSettings();
    final h = int.tryParse(parts[1]);
    final m = int.tryParse(parts[2]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return const ReminderSettings();
    }
    return ReminderSettings(enabled: parts[0] == '1', hour: h, minute: m);
  }

  @override
  bool operator ==(Object other) =>
      other is ReminderSettings &&
      other.enabled == enabled &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(enabled, hour, minute);
}

/// Off by default; 7:00 AM when first turned on. App design choice.
const int kDefaultReminderHour = 7;

class ReminderSettingsController extends ValueNotifier<ReminderSettings> {
  ReminderSettingsController() : super(const ReminderSettings());

  static const String _key = 'workout_reminders_v1';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = ReminderSettings.decode(prefs.getString(_key));
    } catch (_) {
      // Unreadable: reminders stay off.
    }
  }

  Future<void> set(ReminderSettings settings) async {
    value = settings;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, settings.encode());
    } catch (_) {
      // Not saved: it still applies until the app closes.
    }
  }
}

/// One for the whole app.
final ReminderSettingsController reminderSettings = ReminderSettingsController()
  ..load();

/// One reminder: when it first fires (phone time), and what it says. It
/// repeats every week on the same day and time.
class WorkoutReminder {
  const WorkoutReminder({
    required this.id,
    required this.day,
    required this.firstAt,
    required this.title,
    required this.body,
  });

  final int id;
  final Weekday day;
  final DateTime firstAt;
  final String title;
  final String body;
}

/// Ids 1000–1006, one per weekday, so a day's reminder is replaced, never
/// added twice.
const int kReminderIdBase = 1000;

/// The next [day] at [hour]:[minute] after [now], in phone time. Today
/// counts only if that time has not passed yet.
DateTime nextWeekly(DateTime now, Weekday day, int hour, int minute) {
  final daysAhead = (day.index - (now.weekday - 1)) % 7;
  var at = DateTime(now.year, now.month, now.day + daysAhead, hour, minute);
  if (!at.isAfter(now)) {
    at = DateTime(at.year, at.month, at.day + 7, hour, minute);
  }
  return at;
}

/// A reminder for each training day of [program], or none when reminders
/// are off or there is no active program.
List<WorkoutReminder> remindersFor(
  TrainingProgram? program,
  ReminderSettings settings,
  DateTime now,
) {
  if (!settings.enabled || program == null) return const [];
  return [
    for (final day in program.trainingDays)
      () {
        final workouts = program.workoutsForDay(day);
        final names = workouts.map((w) => w.name).join(' + ');
        return WorkoutReminder(
          id: kReminderIdBase + day.index,
          day: day,
          firstAt: nextWeekly(now, day, settings.hour, settings.minute),
          title: workouts.isEmpty
              ? 'Training day today'
              : 'Workout today: $names',
          body: '${program.name}: open ANTHROFIT to start when you are ready.',
        );
      }(),
  ];
}
