import '../core/json_utils.dart';
import '../models/models.dart';
import 'storage_scope.dart';
import 'stored_json.dart';
import 'sync_service.dart';

/// Saves and loads completed body scans, one JSON object per owner, through
/// the same storage as the profile, programs and sessions.
class MeasurementRepository {
  MeasurementRepository({this.scope = StorageScope.guest, this.sync});

  /// Mirrors this data to the cloud when an account is signed in. Null, or a
  /// disabled service, means local only. The device is always written first,
  /// so a save never depends on the network.
  final SyncService? sync;

  /// Whose scans these are. Defaults to the guest's.
  final StorageScope scope;

  static const String storageKey = 'measurement_data';

  /// Returns an empty list if nothing is saved, or if saved data can't be read.
  Future<List<Measurement>> load() async {
    var map = await readSavedObject(scope.key(storageKey));
    map = await sync?.pull(storageKey, map) ?? map;
    if (map == null) return const [];
    try {
      return parseMapList(
        map['measurements'],
      ).map(Measurement.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<Measurement> measurements) async {
    final value = SyncService.stamp({
      'measurements': measurements.map((m) => m.toJson()).toList(),
    });
    await writeSavedObject(scope.key(storageKey), value);
    await sync?.push(storageKey, value);
  }
}
