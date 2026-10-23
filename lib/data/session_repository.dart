import '../core/json_utils.dart';
import '../models/models.dart';
import 'storage_scope.dart';
import 'stored_json.dart';
import 'sync_service.dart';

/// Everything saved about workout sessions:
///  - the one in-progress session, if any (so it can be resumed)
///  - all completed sessions (the data History and Progress read)
class SessionData {
  const SessionData({this.activeSession, this.sessions = const []});

  final WorkoutSession? activeSession;
  final List<WorkoutSession> sessions;
}

class SessionRepository {
  SessionRepository({this.scope = StorageScope.guest, this.sync});

  /// Mirrors this data to the cloud when an account is signed in. Null, or a
  /// disabled service, means local only. The device is always written first,
  /// so a save never depends on the network.
  final SyncService? sync;

  /// Whose sessions these are (including an unfinished one). Defaults to the guest's.
  final StorageScope scope;

  static const String storageKey = 'session_data';

  /// Returns empty data if nothing is saved, or if saved data can't be read.
  Future<SessionData> load() async {
    var map = await readSavedObject(scope.key(storageKey));
    map = await sync?.pull(storageKey, map) ?? map;
    if (map == null) return const SessionData();
    try {
      final active = map['activeSession'];
      return SessionData(
        activeSession: active is Map
            ? WorkoutSession.fromJson(Map<String, dynamic>.from(active))
            : null,
        sessions: parseMapList(
          map['sessions'],
        ).map(WorkoutSession.fromJson).toList(),
      );
    } catch (_) {
      return const SessionData();
    }
  }

  Future<void> save(SessionData data) async {
    final value = SyncService.stamp({
      'activeSession': data.activeSession?.toJson(),
      'sessions': data.sessions.map((s) => s.toJson()).toList(),
    });
    await writeSavedObject(scope.key(storageKey), value);
    await sync?.push(storageKey, value);
  }
}
