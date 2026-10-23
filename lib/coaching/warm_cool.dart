import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Warm-up and cool-down prompts around a workout.
//
// Source for the structure: ACSM position stand (Garber et al., 2011, Med
// Sci Sports Exerc 43(7):1334-59): a session has a warm-up and a cool-down of
// at least 5-10 minutes of light-to-moderate activity each, and flexibility
// work is done when the muscles are warm, after the warm-up or the
// cool-down, holding each static stretch about 10-30 seconds.
//
// APP DESIGN CHOICES, not from the source: the 5-minute starting timer, the
// one-minute extension, suggesting stretches in the cool-down rather than
// before lifting, pointing to light warm-up sets of the first exercise, and
// that both prompts are optional and on by default.

/// The timer each prompt starts with. App design value.
const Duration kWarmCoolTimer = Duration(minutes: 5);

const String kWarmUpText =
    '5-10 minutes of light activity, such as brisk walking or easy cycling, '
    'then a few light warm-up sets of your first exercise.';

const String kCoolDownText =
    '5-10 minutes of easy walking, then stretch the muscles you trained for '
    '10-30 seconds each. Mild tension, never pain.';

/// Whether the prompts show. On this phone only, like the theme.
class WarmCoolSettings extends ValueNotifier<bool> {
  WarmCoolSettings() : super(true);

  static const String _key = 'warm_cool_v1';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_key);
      if (saved != null) value = saved;
    } catch (_) {
      // Unreadable: keep showing them.
    }
  }

  Future<void> set(bool on) async {
    value = on;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, on);
    } catch (_) {
      // Not saved: it still applies until the app closes.
    }
  }
}

/// One for the whole app.
final WarmCoolSettings warmCoolSettings = WarmCoolSettings()..load();
