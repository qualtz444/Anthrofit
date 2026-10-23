/// The boundary between ANTHROFIT and the cloud.
///
/// Only firestore_store.dart knows Firestore exists. Everything else uses this
/// interface, so sync can be tested with a fake and a Firestore outage can
/// never reach a screen.
///
/// A "document" here is one whole saved object, matching what the device
/// already stores: the profile, all programs, all sessions, all scans. There
/// is no second data model.
abstract class CloudStore {
  /// Reads one document, or null if it does not exist.
  /// Throws if the cloud could not be reached.
  Future<Map<String, dynamic>?> read({
    required String uid,
    required String key,
  });

  /// Writes one document, replacing whatever was there.
  Future<void> write({
    required String uid,
    required String key,
    required Map<String, dynamic> value,
  });
}

/// The field every synced document carries, so the newer copy can be told
/// from the older one. Milliseconds since epoch, written by the device that
/// last changed the data.
const String kCloudUpdatedAt = 'updatedAt';
