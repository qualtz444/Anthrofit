import '../core/json_utils.dart';
import '../models/models.dart';
import 'storage_scope.dart';
import 'stored_json.dart';
import 'sync_service.dart';

/// Everything saved about programs: the programs themselves plus which one
/// is active. Stored together so they can never disagree.
class ProgramData {
  const ProgramData({this.programs = const [], this.activeProgramId});

  final List<TrainingProgram> programs;
  final String? activeProgramId;
}

/// Programs contain their workouts and planned exercises, so one saved object
/// covers programs, schedules, workouts, and planned exercises.
class ProgramRepository {
  ProgramRepository({this.scope = StorageScope.guest, this.sync});

  /// Mirrors this data to the cloud when an account is signed in. Null, or a
  /// disabled service, means local only. The device is always written first,
  /// so a save never depends on the network.
  final SyncService? sync;

  /// Whose programs these are. Defaults to the guest's.
  final StorageScope scope;

  static const String storageKey = 'program_data';

  /// Returns empty data if nothing is saved, or if saved data can't be read.
  Future<ProgramData> load() async {
    var map = await readSavedObject(scope.key(storageKey));
    map = await sync?.pull(storageKey, map) ?? map;
    if (map == null) return const ProgramData();
    try {
      final active = map['activeProgramId'];
      return ProgramData(
        programs: parseMapList(
          map['programs'],
        ).map(TrainingProgram.fromJson).toList(),
        activeProgramId: active is String ? active : null,
      );
    } catch (_) {
      return const ProgramData();
    }
  }

  Future<void> save(ProgramData data) async {
    final value = SyncService.stamp({
      'activeProgramId': data.activeProgramId,
      'programs': data.programs.map((p) => p.toJson()).toList(),
    });
    await writeSavedObject(scope.key(storageKey), value);
    await sync?.push(storageKey, value);
  }
}
