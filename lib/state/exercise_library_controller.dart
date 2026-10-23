import 'dart:async';

import 'package:flutter/foundation.dart';

import '../content/app_content.dart';
import '../core/id.dart';
import '../data/exercise_catalog_repository.dart';
import '../data/exercise_library.dart';
import '../data/exercise_library_repository.dart';
import '../models/models.dart';

/// Owns the user's changes to the exercise library.
///
/// Every change is saved first, then installed into [ExerciseLibrary], so the
/// whole app, including the recommendation engine, sees one library. Memory
/// only updates if the save worked.
class ExerciseLibraryController extends ChangeNotifier {
  ExerciseLibraryController(
    this._repository, {
    this.catalog = const AssetExerciseCatalog(),
  });

  final ExerciseLibraryRepository _repository;

  /// Where the built-in exercises come from. An asset today; a Firestore
  /// collection later, by passing a different source.
  final ExerciseCatalogSource catalog;

  /// Set when the built-in catalogue could not be read, so a screen can say
  /// so rather than showing an empty library with no explanation.
  String? _catalogError;
  String? get catalogError => _catalogError;

  ExerciseLibraryData _data = ExerciseLibraryData.empty;
  bool _isLoaded = false;
  bool _disposed = false;

  /// The catalogue as shipped, kept so the admin's content can be applied
  /// again when it arrives from Firestore.
  List<Exercise>? _shipped;

  bool get isLoaded => _isLoaded;

  /// Every exercise, built-in and the user's own, as the app sees it.
  List<Exercise> get all => ExerciseLibrary.all;

  /// True for an exercise that ships with the app. Built-ins are fixed: they
  /// cannot be changed in place or removed.
  bool isBuiltIn(String id) => ExerciseLibrary.isBuiltIn(id);

  /// True for an exercise the user created.
  bool isCustom(String id) => _data.custom.any((e) => e.id == id);

  Future<void> load() async {
    // The built-in catalogue first: the user's own exercises are merged on
    // top of it, so it has to be in place before they are applied.
    // Already loaded means a second owner in the same session; the
    // catalogue is the same for everyone, so it is not read twice.
    if (!ExerciseLibrary.isLoaded) {
      // The admin's content as saved on the phone last time, so their
      // exercises, equipment and recommendation settings are in place
      // before anything reads them. Instant; never throws.
      await AppContent.loadSaved();
      try {
        _shipped = await catalog.load();
        _installCatalog();
        _catalogError = null;
      } catch (error) {
        _catalogError = 'The exercise list could not be loaded.';
      }
      // Then the latest from Firestore, without making anyone wait.
      unawaited(_fetchAdminContent());
    }

    try {
      _data = await _repository.load();
    } catch (_) {
      _data = ExerciseLibraryData.empty;
    }
    ExerciseLibrary.applyCustomisations(_data);
    _isLoaded = true;
    notifyListeners();
  }

  void _installCatalog() {
    final shipped = _shipped;
    if (shipped == null) return;
    final merged = mergeCatalog(shipped, AppContent.exercises);
    ExerciseLibrary.applyBuiltIn(merged.exercises, hidden: merged.hidden);
  }

  Future<void> _fetchAdminContent() async {
    final fetched = await AppContent.fetchRemote();
    if (!fetched || _disposed) return;
    _installCatalog();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Creates an exercise. [draft]'s id is ignored: a new one is generated, so
  /// a user's exercise can never collide with a built-in one.
  Future<Exercise> add(Exercise draft) async {
    final created = _withNewId(draft);
    await _commit(ExerciseLibraryData(custom: [..._data.custom, created]));
    return created;
  }

  /// Saves a change.
  ///
  /// A custom exercise is changed in place, keeping its id, so programs that
  /// use it follow the change. Editing a BUILT-IN one cannot change it: a
  /// copy is created and returned instead, and the original is untouched.
  /// Callers should tell the user which happened.
  Future<Exercise> update(Exercise exercise) async {
    if (isCustom(exercise.id)) {
      await _commit(
        ExerciseLibraryData(
          custom: [
            for (final e in _data.custom) e.id == exercise.id ? exercise : e,
          ],
        ),
      );
      return exercise;
    }
    // A built-in: fork it rather than editing the catalogue.
    return add(
      exercise.name == ExerciseLibrary.byId(exercise.id)?.name
          ? exercise.copyWith(name: '${exercise.name} (custom)')
          : exercise,
    );
  }

  /// Copies an exercise into a new one the user owns.
  Future<Exercise> duplicate(Exercise exercise) =>
      add(exercise.copyWith(name: '${exercise.name} copy'));

  /// Deletes one of the user's own exercises.
  ///
  /// Built-in exercises cannot be removed, so this does nothing for one.
  /// Programs that already use a deleted exercise will show it as unknown,
  /// which is why the UI warns first.
  Future<void> remove(String id) async {
    if (!isCustom(id)) return;
    await _commit(
      ExerciseLibraryData(
        custom: _data.custom.where((e) => e.id != id).toList(),
      ),
    );
  }

  Exercise _withNewId(Exercise draft) => Exercise(
    id: 'custom_${generateId()}',
    name: draft.name,
    exerciseType: draft.exerciseType,
    movementPattern: draft.movementPattern,
    primaryMuscles: draft.primaryMuscles,
    secondaryMuscles: draft.secondaryMuscles,
    equipment: draft.equipment,
    extraEquipment: draft.extraEquipment,
    experienceLevel: draft.experienceLevel,
    complexity: draft.complexity,
    instructions: draft.instructions,
  );

  Future<void> _commit(ExerciseLibraryData data) async {
    await _repository.save(data);
    _data = data;
    ExerciseLibrary.applyCustomisations(data);
    notifyListeners();
  }
}
