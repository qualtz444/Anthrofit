import '../core/json_utils.dart';
import '../models/models.dart';

/// The single source of truth for exercise definitions.
/// Browsing, search, detail screens, and (later) Planning all read from here.
///
/// Static and seeded for now. If exercises ever need to be user-editable,
/// only this file has to change.
///
/// Classification note: cable exercises use ExerciseType.machine, because the
/// baseline only has three types (bodyweight, machine, free weight).
/// The exercises the user created.
///
/// The built-in catalogue is code and never changes: editing a built-in
/// exercise makes a copy rather than altering it, so a program saved months
/// ago still means exactly what it meant then.
class ExerciseLibraryData {
  const ExerciseLibraryData({this.custom = const []});

  final List<Exercise> custom;

  bool get isEmpty => custom.isEmpty;

  static const ExerciseLibraryData empty = ExerciseLibraryData();

  Map<String, dynamic> toJson() => {
    'custom': custom.map((e) => e.toJson()).toList(),
  };

  factory ExerciseLibraryData.fromJson(Map<String, dynamic> json) =>
      ExerciseLibraryData(
        custom: parseMapList(json['custom']).map(Exercise.fromJson).toList(),
      );
}

/// The single source of truth for exercise definitions.
///
/// It is the fixed built-in catalogue below, plus the exercises the user
/// created. Browsing, search, planning, the session screen and the
/// recommendation engine all read from here, so a user's own exercise behaves
/// exactly like a built-in one everywhere.
///
/// The user's exercises are held statically because every caller reaches this
/// class statically. ExerciseLibraryController installs them once at start-up
/// and after every change; nothing else should call [applyCustomisations].
class ExerciseLibrary {
  const ExerciseLibrary._();

  static ExerciseLibraryData _data = ExerciseLibraryData.empty;
  static List<Exercise> _builtIn = const [];
  static Set<String> _hidden = const {};
  static List<Exercise> _merged = const [];
  static Map<String, Exercise> _byId = const {};

  /// The built-in catalogue, as loaded from assets/data/exercises.json.
  /// Empty until [applyBuiltIn] has been called.
  static List<Exercise> get builtIn => _builtIn;

  /// True once the catalogue has been loaded.
  static bool get isLoaded => _builtIn.isNotEmpty;

  /// Installs the built-in catalogue. Called once at start-up by
  /// ExerciseLibraryController, and by tests.
  ///
  /// [hidden] are ids an admin hid: left out of [all] (so out of browsing
  /// and recommendations) but still found by [byId], so programs that
  /// already use them keep working.
  static void applyBuiltIn(
    List<Exercise> exercises, {
    Set<String> hidden = const {},
  }) {
    _builtIn = List.unmodifiable(exercises);
    _hidden = Set.unmodifiable(hidden);
    applyCustomisations(_data);
  }

  /// True for an exercise an admin hid.
  static bool isHidden(String id) => _hidden.contains(id);

  /// True for an exercise that ships with the app. These cannot be edited in
  /// place or removed: editing one creates a copy the user owns.
  static bool isBuiltIn(String id) => _builtIn.any((e) => e.id == id);

  /// The exercises the user created.
  static ExerciseLibraryData get customisations => _data;

  /// Installs the user's exercises. Called by the controller, and by tests.
  static void applyCustomisations(ExerciseLibraryData data) {
    _data = data;
    final merged = <Exercise>[..._builtIn, ...data.custom];
    _merged = List.unmodifiable(
      merged.where((e) => !_hidden.contains(e.id)),
    );
    _byId = {for (final e in merged) e.id: e};
  }

  /// Back to the built-in catalogue only. The catalogue itself is kept.
  static void reset() => applyCustomisations(ExerciseLibraryData.empty);

  /// Forgets everything, catalogue included. For tests that need a clean
  /// slate; the app never calls this.
  static void clear() {
    _builtIn = const [];
    _hidden = const {};
    applyCustomisations(ExerciseLibraryData.empty);
  }

  static List<Exercise> get all => _merged;

  /// Returns null if the id is not in the library.
  static Exercise? byId(String id) => _byId[id];

  /// Filters the library. Every argument is optional and they combine (AND).
  ///
  /// [query] matches the exercise name OR a primary muscle name,
  /// ignoring case, so "chest" finds Push-Up and Barbell Bench Press too.
  static List<Exercise> filter({
    String query = '',
    ExerciseType? exerciseType,
    MovementPattern? movementPattern,
  }) {
    final q = query.trim().toLowerCase();
    return all.where((e) {
      if (exerciseType != null && e.exerciseType != exerciseType) return false;
      if (movementPattern != null && e.movementPattern != movementPattern) {
        return false;
      }
      if (q.isEmpty) return true;
      if (e.name.toLowerCase().contains(q)) return true;
      return e.primaryMuscles.any((m) => m.label.toLowerCase().contains(q));
    }).toList();
  }
}
