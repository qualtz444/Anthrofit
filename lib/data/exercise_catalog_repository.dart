import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../core/json_utils.dart';
import '../models/models.dart';

/// Loads the built-in exercise catalogue.
///
/// The catalogue lives in assets/data/exercises.json rather than in Dart, so
/// it can be edited without a code change and, later, served from Firestore
/// instead. The file's shape is the same shape a Firestore document would
/// have, so the swap is one implementation of this class:
///
///     { "schemaVersion": 1, "exercises": [ {...}, {...} ] }
///
/// Each entry is exactly [Exercise.toJson], so nothing has to be translated
/// in either direction.
abstract class ExerciseCatalogSource {
  /// Every built-in exercise. Throws if the catalogue cannot be read.
  Future<List<Exercise>> load();
}

/// Reads the catalogue shipped with the app.
class AssetExerciseCatalog implements ExerciseCatalogSource {
  const AssetExerciseCatalog({this.assetPath = defaultAssetPath});

  static const String defaultAssetPath = 'assets/data/exercises.json';

  /// The newest schema this build understands. A file written by a newer
  /// version still loads: unknown fields are ignored and unknown enum values
  /// fall back, so an older app degrades rather than breaking.
  static const int supportedSchemaVersion = 1;

  final String assetPath;

  @override
  Future<List<Exercise>> load() async {
    final raw = await rootBundle.loadString(assetPath);
    return parseCatalog(raw);
  }
}

/// Reads a catalogue from the JSON text itself.
///
/// Separate from the asset loading so it can be used with a Firestore
/// document, a downloaded file, or a string in a test.
List<Exercise> parseCatalog(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Exercise catalogue must be a JSON object');
  }
  final entries = parseMapList(decoded['exercises']);
  if (entries.isEmpty) {
    throw const FormatException('Exercise catalogue has no exercises');
  }

  final exercises = <Exercise>[];
  final seen = <String>{};
  for (final entry in entries) {
    final exercise = Exercise.fromJson(entry);
    // An entry with no id could never be referred to by a program, and a
    // repeat would make byId ambiguous. Both are data errors worth refusing.
    if (exercise.id.isEmpty) {
      throw const FormatException('Exercise catalogue has an entry with no id');
    }
    if (!seen.add(exercise.id)) {
      throw FormatException('Exercise catalogue repeats id ${exercise.id}');
    }
    exercises.add(exercise);
  }
  return exercises;
}
