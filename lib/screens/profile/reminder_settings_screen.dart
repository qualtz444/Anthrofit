import 'package:flutter/material.dart';

import '../../notifications/app_notifications.dart';
import '../../notifications/reminder_settings.dart';
import '../../core/snack_bar_timing.dart';

/// Turns training-day reminders on or off and sets their time. The rest
/// alert needs no setting: it only appears when the app is in the
/// background while a rest is running.
class ReminderSettingsScreen extends StatelessWidget {
  const ReminderSettingsScreen({super.key});

  Future<void> _setEnabled(
    BuildContext context,
    ReminderSettings current,
    bool on,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    if (on) {
      final allowed = await appNotifications.requestPermission();
      if (!allowed) {
        messenger.showSnackBar(
          const SnackBar(duration: kSnackBarDuration, persist: false,
            content: Text(
              'Notifications are off for ANTHROFIT. Turn them on in your '
              "phone's Settings, under Apps, ANTHROFIT, Notifications.",
            ),
          ),
        );
      }
    }
    await reminderSettings.set(current.copyWith(enabled: on));
  }

  Future<void> _pickTime(BuildContext context, ReminderSettings current) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      helpText: 'Remind me at',
    );
    if (picked == null) return;
    await reminderSettings.set(
      current.copyWith(hour: picked.hour, minute: picked.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: ValueListenableBuilder<ReminderSettings>(
        valueListenable: reminderSettings,
        builder: (context, s, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            SwitchListTile(
              key: const ValueKey('reminders-switch'),
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('Workout reminders'),
              subtitle: const Text(
                "On your active program's training days.",
              ),
              value: s.enabled,
              onChanged: (on) => _setEnabled(context, s, on),
            ),
            ListTile(
              key: const ValueKey('reminders-time'),
              enabled: s.enabled,
              leading: const Icon(Icons.schedule),
              title: const Text('Time'),
              subtitle: Text(
                TimeOfDay(
                  hour: s.hour,
                  minute: s.minute,
                ).format(context),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickTime(context, s),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Rest timer alert', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Get notified when a rest ends, even if the app is closed '
                    'or the phone is locked. It may arrive a few seconds late.',
                    style: muted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Reminders are set on this phone only and follow your '
                    'active program, so changing the program or its days '
                    'updates them.',
                    style: muted,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
