import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/models.dart';
import 'reminder_settings.dart';

/// Notifications shown by this phone (no server): the rest timer finishing
/// while the app is in the background, and training-day reminders.
///
/// Every call is best effort. Off Android (including widget tests), or if
/// the plugin fails, nothing happens and nothing throws: a missed
/// notification must never break a workout.
abstract class AppNotifications {
  /// Asks for permission to show notifications (Android 13 and later).
  /// True when allowed.
  Future<bool> requestPermission();

  /// Shows "Rest is over" after [after], unless cancelled first.
  Future<void> scheduleRestOver({
    required Duration after,
    required String body,
  });

  Future<void> cancelRestOver();

  /// Replaces every training-day reminder with the ones for [program].
  Future<void> syncWorkoutReminders(
    TrainingProgram? program,
    ReminderSettings settings,
  );
}

class LocalNotifications implements AppNotifications {
  Future<FlutterLocalNotificationsPlugin?>? _ready;

  static const int _restId = 1;

  static const AndroidNotificationDetails _restDetails =
      AndroidNotificationDetails(
        'rest_timer',
        'Rest timer',
        channelDescription: 'Tells you when your rest between sets is over.',
        importance: Importance.high,
        priority: Priority.high,
      );

  static const NotificationDetails _restNotificationDetails =
      NotificationDetails(android: _restDetails);

  static const AndroidNotificationDetails _reminderDetails =
      AndroidNotificationDetails(
        'workout_reminders',
        'Workout reminders',
        channelDescription: "Reminders on your program's training days.",
      );

  static const NotificationDetails _reminderNotificationDetails =
      NotificationDetails(android: _reminderDetails);

  Future<FlutterLocalNotificationsPlugin?> _plugin() =>
      _ready ??= _init();

  Future<FlutterLocalNotificationsPlugin?> _init() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      tzdata.initializeTimeZones();
      final plugin = FlutterLocalNotificationsPlugin();
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await plugin.initialize(settings);
      return plugin;
    } catch (e) {
      debugPrint('[Notifications] init failed: $e');
      return null;
    }
  }

  /// Phone time to the same moment in UTC, for the plugin.
  static tz.TZDateTime _utc(DateTime local) =>
      tz.TZDateTime.from(local.toUtc(), tz.UTC);

  @override
  Future<bool> requestPermission() async {
    final plugin = await _plugin();
    if (plugin == null) return false;
    try {
      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.requestNotificationsPermission() ?? false;
    } catch (e) {
      debugPrint('[Notifications] permission request failed: $e');
      return false;
    }
  }

  @override
  Future<void> scheduleRestOver({
    required Duration after,
    required String body,
  }) async {
    final plugin = await _plugin();
    if (plugin == null || after <= Duration.zero) return;
    try {
      await plugin.zonedSchedule(
        _restId,
        'Rest is over',
        body,
        _utc(DateTime.now().add(after)),
        _restNotificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('[Notifications] rest alert failed: $e');
    }
  }

  @override
  Future<void> cancelRestOver() async {
    final plugin = await _plugin();
    if (plugin == null) return;
    try {
      await plugin.cancel(_restId);
    } catch (e) {
      debugPrint('[Notifications] cancel failed: $e');
    }
  }

  @override
  Future<void> syncWorkoutReminders(
    TrainingProgram? program,
    ReminderSettings settings,
  ) async {
    final plugin = await _plugin();
    if (plugin == null) return;
    try {
      for (final day in Weekday.values) {
        await plugin.cancel(kReminderIdBase + day.index);
      }
      for (final r in remindersFor(program, settings, DateTime.now())) {
        await plugin.zonedSchedule(
          r.id,
          r.title,
          r.body,
          _utc(r.firstAt),
          _reminderNotificationDetails,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      debugPrint('[Notifications] reminders failed: $e');
    }
  }
}

/// The notifications the app uses. Tests can swap it for a fake.
AppNotifications appNotifications = LocalNotifications();
