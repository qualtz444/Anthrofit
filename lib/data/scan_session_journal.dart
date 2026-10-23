import '../models/models.dart';
import 'storage_scope.dart';
import 'stored_json.dart';

/// One finished guided scan that has been committed but not yet copied into
/// the scan history and the profile.
class PendingScanSession {
  const PendingScanSession({required this.measurement, required this.record});

  final Measurement measurement;
  final CompositionRecord record;
}

/// Makes saving a guided scan all or nothing.
///
/// The proportion scan and the composition estimate live under two different
/// storage keys, and the phone cannot write two keys as one step. So the
/// session is first written here, under ONE key, in one write. That write is
/// the commit:
///
///   it fails      nothing is saved anywhere
///   it succeeds   the session is saved. Both parts are then copied into
///                 their usual places and this entry is cleared. If that is
///                 interrupted (an error, the app closing), the copy is
///                 finished the next time the owner's data loads.
///
/// Copying is safe to repeat: both places replace an entry with the same id.
class ScanSessionJournal {
  ScanSessionJournal({this.scope = StorageScope.guest});

  /// Whose session this is, the same scope as their scans and profile.
  final StorageScope scope;

  static const String storageKey = 'pending_scan_session';

  String get _key => scope.key(storageKey);

  /// The commit. Throws if the phone did not accept it.
  Future<void> write(PendingScanSession session) => writeSavedObject(_key, {
    'measurement': session.measurement.toJson(),
    'composition': session.record.toJson(),
  });

  /// Null when nothing is pending, or the entry cannot be read (it is then
  /// kept aside by [readSavedObject], not lost).
  Future<PendingScanSession?> read() async {
    final map = await readSavedObject(_key);
    if (map == null) return null;
    try {
      return PendingScanSession(
        measurement: Measurement.fromJson(
          Map<String, dynamic>.from(map['measurement'] as Map),
        ),
        record: CompositionRecord.fromJson(
          Map<String, dynamic>.from(map['composition'] as Map),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() => removeSavedObject(_key);
}
