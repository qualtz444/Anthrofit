import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// The one place that touches SharedPreferences. The profile, program and
// session repositories all read and write through these two functions.

/// Reads one saved JSON object.
/// Returns null if nothing is saved. If something is saved but can't be read,
/// the text is kept under the same key plus ".unreadable" so it is not lost, and
/// null is returned.
Future<Map<String, dynamic>?> readSavedObject(String key) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(key);
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {
    // Handled below, the same as a JSON value that is not an object.
  }
  try {
    await prefs.setString('$key.unreadable', raw);
  } catch (_) {
    // Keeping a copy is best effort.
  }
  return null;
}

/// Saves one JSON object. Throws if the device did not accept the write.
Future<void> writeSavedObject(String key, Map<String, dynamic> value) async {
  final prefs = await SharedPreferences.getInstance();
  final ok = await prefs.setString(key, jsonEncode(value));
  if (!ok) {
    throw StateError('Could not save "$key".');
  }
}

/// Removes one saved object. Throws if the device did not accept it.
Future<void> removeSavedObject(String key) async {
  final prefs = await SharedPreferences.getInstance();
  final ok = await prefs.remove(key);
  if (!ok) {
    throw StateError('Could not remove "$key".');
  }
}
