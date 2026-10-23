import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's choice of light, dark or follow-the-phone. Remembered on this
/// phone only: it is a display preference, not account data, so it is not
/// synced.
class ThemeModeController extends ValueNotifier<ThemeMode> {
  ThemeModeController() : super(ThemeMode.system);

  static const String _key = 'theme_mode_v1';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      value = ThemeMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => ThemeMode.system,
      );
    } catch (_) {
      // Unreadable: keep following the phone.
    }
  }

  Future<void> set(ThemeMode mode) async {
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {
      // Not saved: it still applies until the app closes.
    }
  }
}

/// One for the whole app; app.dart listens to it.
final ThemeModeController themeMode = ThemeModeController()..load();

String themeModeLabel(ThemeMode m) => switch (m) {
  ThemeMode.system => 'Same as phone',
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
};
