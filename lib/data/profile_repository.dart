import '../models/models.dart';
import 'storage_scope.dart';
import 'stored_json.dart';
import 'sync_service.dart';

/// Saves and loads the single local profile.
/// Phase 8 note: all repositories share stored_json.dart.
class ProfileRepository {
  ProfileRepository({this.scope = StorageScope.guest, this.sync});

  /// Mirrors this data to the cloud when an account is signed in. Null, or a
  /// disabled service, means local only. The device is always written first,
  /// so a save never depends on the network.
  final SyncService? sync;

  /// Whose profile this is. Defaults to the guest's.
  final StorageScope scope;

  static const String storageKey = 'user_profile';

  /// Returns null if nothing is saved yet, or if the saved data can't be read.
  Future<UserProfile?> load() async {
    var map = await readSavedObject(scope.key(storageKey));
    // Best effort: brings down a newer copy, or sends this one up.
    map = await sync?.pull(storageKey, map) ?? map;
    if (map == null) return null;
    try {
      return UserProfile.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(UserProfile profile) async {
    final value = SyncService.stamp(profile.toJson());
    await writeSavedObject(scope.key(storageKey), value); // the device first
    await sync?.push(storageKey, value); // then the cloud, best effort
  }
}
