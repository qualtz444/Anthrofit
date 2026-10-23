import '../cloud/cloud_store.dart';
import 'storage_scope.dart';
import 'stored_json.dart';

/// Keeps one account's saved data mirrored in the cloud.
///
/// The device stays the source of truth. Every read and write still goes to
/// local storage first and succeeds on its own; the cloud is best effort, so
/// no screen ever fails because the network did.
///
/// What it does, per document:
///   loading  compare timestamps. A newer cloud copy is written over the
///            local one; otherwise the local copy is pushed up.
///   saving   write locally, then push. A failed push is dropped: the next
///            load will push it instead.
///
/// Guests are never synced: there is no account to sync to. Conflicts are
/// settled per document by whichever was saved last, so editing the same kind
/// of data on two devices while offline keeps only the later save. Splitting
/// each program and session into its own document would merge properly, and
/// is the change to make if that ever matters.
class SyncService {
  SyncService({required this.cloud, required this.scope, required this.uid});

  /// Null disables syncing entirely (guest mode, or the cloud turned off).
  final CloudStore? cloud;

  final StorageScope scope;

  /// The account this data belongs to. Empty for a guest.
  final String uid;

  bool get isEnabled => cloud != null && uid.isNotEmpty && !scope.isGuest;

  /// Reconciles one document and returns what should be used.
  ///
  /// [local] is what the device has, or null if it has nothing. The returned
  /// map is already saved locally if it came from the cloud, so the caller can
  /// just use it.
  Future<Map<String, dynamic>?> pull(
    String key,
    Map<String, dynamic>? local,
  ) async {
    if (!isEnabled) return local;

    Map<String, dynamic>? remote;
    try {
      remote = await cloud!.read(uid: uid, key: key);
    } catch (_) {
      return local; // offline or refused: carry on with the device's copy
    }

    final localAt = _updatedAt(local);
    final remoteAt = _updatedAt(remote);

    if (remote != null && remoteAt > localAt) {
      try {
        await writeSavedObject(scope.key(key), remote);
      } catch (_) {
        // Could not cache it; still use it for this session.
      }
      return remote;
    }

    // The device is ahead (or the cloud has nothing): send it up.
    if (local != null && (remote == null || localAt > remoteAt)) {
      await push(key, local);
    }
    return local;
  }

  /// Sends one document up. Never throws: a failed push is not a failed save.
  Future<void> push(String key, Map<String, dynamic> value) async {
    if (!isEnabled) return;
    try {
      await cloud!.write(uid: uid, key: key, value: value);
    } catch (_) {
      // The next pull will notice the device is ahead and try again.
    }
  }

  static int _updatedAt(Map<String, dynamic>? doc) {
    final value = doc?[kCloudUpdatedAt];
    return value is num ? value.toInt() : 0;
  }

  /// Stamps a document so the newer copy can be told from the older one.
  static Map<String, dynamic> stamp(Map<String, dynamic> value) => {
    ...value,
    kCloudUpdatedAt: DateTime.now().millisecondsSinceEpoch,
  };
}
