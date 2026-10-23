import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/ready_made_programs.dart';
import '../models/models.dart';
import '../recommendation/proportion_rules.dart';
import '../recommendation/recommendation_weights.dart';
import 'content_models.dart';
import 'content_source.dart';

/// What the admin panel changed, as the phone app sees it.
///
/// Static, like ExerciseLibrary, because the recommendation code reaches it
/// from plain functions. Every getter falls back to what ships with the app,
/// so with nothing from the admin the app behaves exactly as before.
///
/// Loaded at start-up by ExerciseLibraryController in two steps, so the app
/// never waits on the network: first the copy saved on the phone last time
/// (instant), then Firestore in the background; when that answers, its
/// content replaces the saved copy and is saved for next time.
class AppContent {
  const AppContent._();

  static ContentSnapshot _snapshot = ContentSnapshot.empty;

  /// Where admin content comes from. Tests set it to null so nothing tries
  /// to reach Firebase.
  static ContentSource? remote = FirestoreContentSource();

  /// Longest wait for Firestore in the background. App design value.
  static const Duration timeout = Duration(seconds: 15);

  static const String _cacheKey = 'app_content_v1';

  static ContentSnapshot get snapshot => _snapshot;

  /// Installs [snapshot]. Used by [refresh] and by tests.
  static void apply(ContentSnapshot snapshot) => _snapshot = snapshot;

  /// Back to the built-in values only.
  static void reset() => _snapshot = ContentSnapshot.empty;

  /// Installs the copy saved on the phone, if there is one. Never throws.
  static Future<void> loadSaved() async {
    final saved = await _load();
    if (saved != null) apply(saved);
  }

  /// Reads the admin's content from Firestore, installs it and saves it for
  /// next time. Returns false (and changes nothing) when it cannot be read.
  /// Never throws.
  static Future<bool> fetchRemote() async {
    final source = remote;
    if (source == null) return false;
    try {
      final fresh = await source.fetch().timeout(timeout);
      apply(fresh);
      await _save(fresh);
      return true;
    } catch (e) {
      debugPrint('[content] admin content not loaded: $e');
      return false;
    }
  }

  static Future<void> _save(ContentSnapshot snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(snapshot.toJson()));
    } catch (_) {
      // Not saved: next start without a connection uses the built-ins.
    }
  }

  static Future<ContentSnapshot?> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return ContentSnapshot.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  // ---- what the rest of the app reads ------------------------------------

  static RecommendationWeights get weights =>
      _snapshot.config.weights ?? RecommendationWeights.standard;

  /// The built-in participant cut-offs, with any ratio the admin replaced.
  static ProportionThresholds get thresholds {
    final overrides = _snapshot.config.thresholds;
    if (overrides.isEmpty) return ProportionThresholds.participants;
    return ProportionThresholds({
      ...ProportionThresholds.participants.byRatio,
      for (final e in overrides.entries) e.key: e.value.threshold,
    });
  }

  /// The built-in rules the admin left on, then the admin's own.
  static List<ProportionRule> get proportionRules {
    final config = _snapshot.config;
    if (config.disabledRules.isEmpty && config.proportionRules.isEmpty) {
      return kProportionRules;
    }
    return [
      for (final rule in kProportionRules)
        if (!config.disabledRules.contains(rule.name)) rule,
      for (final rule in config.proportionRules)
        if (rule.enabled) rule.toRule(),
    ];
  }

  /// The admin's goal fit for [exerciseId], or null to use the heuristic.
  static double? goalFit(String exerciseId, TrainingGoal goal) =>
      _snapshot.config.goalFit[exerciseId]?[goal.name];

  /// The exercise ids a workout template starts with, or null for the
  /// built-in list.
  static List<String>? templateExercises(String templateName) =>
      _snapshot.config.templateExercises[templateName];

  static List<ReadyMadeProgram> get readyMade =>
      _snapshot.config.readyMade ?? kReadyMadePrograms;

  /// Admin-added equipment, hidden ones included.
  static List<EquipmentDef> get equipment => _snapshot.equipment;

  static EquipmentDef? equipmentById(String id) {
    for (final e in _snapshot.equipment) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// The name of an admin equipment id, or the id itself if unknown.
  static String equipmentLabel(String id) => equipmentById(id)?.label ?? id;

  static List<ExerciseOverride> get exercises => _snapshot.exercises;
}

/// The built-in catalogue with the admin's exercises applied: a doc with a
/// built-in id replaces that exercise, any other doc is added.
///
/// Returns the exercises to show and the ids hidden from browsing and
/// recommendations (still found by id, so old programs keep working).
({List<Exercise> exercises, Set<String> hidden}) mergeCatalog(
  List<Exercise> builtIn,
  List<ExerciseOverride> overrides,
) {
  final byId = {for (final o in overrides) o.exercise.id: o};
  final merged = <Exercise>[
    for (final e in builtIn) byId[e.id]?.exercise ?? e,
  ];
  final builtInIds = {for (final e in builtIn) e.id};
  for (final o in overrides) {
    if (!builtInIds.contains(o.exercise.id)) merged.add(o.exercise);
  }
  return (
    exercises: merged,
    hidden: {
      for (final o in overrides)
        if (o.hidden) o.exercise.id,
    },
  );
}
