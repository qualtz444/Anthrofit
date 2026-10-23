import 'exercise_library.dart';
import 'storage_scope.dart';
import 'stored_json.dart';
import 'sync_service.dart';

/// Saves the user's own exercises, their edits to built-in ones, and the ones
/// they removed. The built-in catalogue itself is code and is never saved.
///
/// Scoped and synced like everything else, so a user's library follows their
/// account and still works offline.
class ExerciseLibraryRepository {
  ExerciseLibraryRepository({this.scope = StorageScope.guest, this.sync});

  final StorageScope scope;
  final SyncService? sync;

  static const String storageKey = 'exercise_library_data';

  Future<ExerciseLibraryData> load() async {
    var map = await readSavedObject(scope.key(storageKey));
    map = await sync?.pull(storageKey, map) ?? map;
    if (map == null) return ExerciseLibraryData.empty;
    try {
      return ExerciseLibraryData.fromJson(map);
    } catch (_) {
      return ExerciseLibraryData.empty;
    }
  }

  Future<void> save(ExerciseLibraryData data) async {
    final value = SyncService.stamp(data.toJson());
    await writeSavedObject(scope.key(storageKey), value);
    await sync?.push(storageKey, value);
  }
}
