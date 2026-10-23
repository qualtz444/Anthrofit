import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'set_coach.dart';

/// Keeps approved Autofill suggestions for the workout in progress, so they
/// survive the app being closed. On this phone only, never synced: they are
/// suggestions, not records. Only one workout runs at a time, so one entry
/// is kept, tagged with its session id; a different session ignores it.
class AutofillStore {
  static const String _key = 'autofill_suggestions_v1';

  static Future<Map<String, Map<int, SetProposal>>> load(
    String sessionId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return {};
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['sessionId'] != sessionId) return {};
      final logs = data['logs'] as Map<String, dynamic>;
      return {
        for (final e in logs.entries)
          e.key: {
            for (final s in (e.value as Map<String, dynamic>).entries)
              int.parse(s.key): SetProposal(
                setIndex: int.parse(s.key),
                loadKg: (s.value['loadKg'] as num?)?.toDouble(),
                reps: (s.value['reps'] as num?)?.toInt(),
              ),
          },
      };
    } catch (_) {
      // Damaged or missing: start without suggestions.
      return {};
    }
  }

  static Future<void> save(
    String sessionId,
    Map<String, Map<int, SetProposal>> byLog,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'sessionId': sessionId,
          'logs': {
            for (final e in byLog.entries)
              e.key: {
                for (final p in e.value.values)
                  '${p.setIndex}': {'loadKg': p.loadKg, 'reps': p.reps},
              },
          },
        }),
      );
    } catch (_) {
      // Suggestions are a convenience; failing to keep them is not an error.
    }
  }
}
