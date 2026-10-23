import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/cloud/cloud_store.dart';
import 'package:anthrofit/data/measurement_repository.dart';
import 'package:anthrofit/data/profile_repository.dart';
import 'package:anthrofit/data/program_repository.dart';
import 'package:anthrofit/data/session_repository.dart';
import 'package:anthrofit/data/storage_scope.dart';
import 'package:anthrofit/data/sync_service.dart';
import 'package:anthrofit/models/models.dart';

import 'test_helpers.dart';

/// A cloud that lives in memory, so sync can be tested without Firestore.
class FakeCloudStore implements CloudStore {
  final Map<String, Map<String, dynamic>> docs = {};

  /// Set to make the next call fail, like being offline.
  bool offline = false;

  int reads = 0;
  int writes = 0;

  String _path(String uid, String key) => '$uid/$key';

  @override
  Future<Map<String, dynamic>?> read({
    required String uid,
    required String key,
  }) async {
    reads++;
    if (offline) throw StateError('offline');
    return docs[_path(uid, key)];
  }

  @override
  Future<void> write({
    required String uid,
    required String key,
    required Map<String, dynamic> value,
  }) async {
    writes++;
    if (offline) throw StateError('offline');
    docs[_path(uid, key)] = value;
  }

  @override
  Future<void> deleteAll({required String uid}) async {
    if (offline) throw StateError('offline');
    docs.removeWhere((path, _) => path.startsWith('$uid/'));
  }

  /// Puts a document in the cloud as if another device had saved it.
  void seed(String uid, String key, Map<String, dynamic> value, int updatedAt) {
    docs[_path(uid, key)] = {...value, kCloudUpdatedAt: updatedAt};
  }
}

const _uid = 'uid_ann';
final _scope = StorageScope.user(_uid);

SyncService _sync(FakeCloudStore cloud) =>
    SyncService(cloud: cloud, scope: _scope, uid: _uid);

void main() {
  // The exercise catalogue is an asset now, so it has to be loaded.
  useExerciseLibrary();

  group('SyncService', () {
    test('it does nothing for a guest', () async {
      final cloud = FakeCloudStore();
      final sync = SyncService(
        cloud: cloud,
        scope: StorageScope.guest,
        uid: '',
      );
      expect(sync.isEnabled, isFalse);

      expect(await sync.pull('k', {'a': 1}), {'a': 1});
      await sync.push('k', {'a': 1});
      expect(cloud.reads, 0);
      expect(cloud.writes, 0);
    });

    test('it does nothing when there is no cloud', () async {
      final sync = SyncService(cloud: null, scope: _scope, uid: _uid);
      expect(sync.isEnabled, isFalse);
      expect(await sync.pull('k', null), isNull);
    });

    test('a newer cloud copy wins and is cached on the device', () async {
      seedNoProfile();
      final cloud = FakeCloudStore();
      cloud.seed(_uid, 'k', {'value': 'from the cloud'}, 2000);

      final result = await _sync(
        cloud,
      ).pull('k', {'value': 'on the device', kCloudUpdatedAt: 1000});

      expect(result!['value'], 'from the cloud');
      // Cached, so the next launch has it even offline.
      expect(
        (await readSavedObjectForTest(_scope.key('k')))!['value'],
        'from the cloud',
      );
    });

    test('a newer device copy is sent up instead', () async {
      seedNoProfile();
      final cloud = FakeCloudStore();
      cloud.seed(_uid, 'k', {'value': 'old cloud'}, 1000);

      final result = await _sync(
        cloud,
      ).pull('k', {'value': 'new device', kCloudUpdatedAt: 2000});

      expect(result!['value'], 'new device');
      expect(cloud.docs['$_uid/k']!['value'], 'new device');
    });

    test('an empty cloud receives whatever the device has', () async {
      seedNoProfile();
      final cloud = FakeCloudStore();
      await _sync(cloud).pull('k', {'value': 'only here', kCloudUpdatedAt: 5});
      expect(cloud.docs['$_uid/k']!['value'], 'only here');
    });

    test('an empty device takes whatever the cloud has', () async {
      seedNoProfile();
      final cloud = FakeCloudStore();
      cloud.seed(_uid, 'k', {'value': 'from another device'}, 1);
      final result = await _sync(cloud).pull('k', null);
      expect(result!['value'], 'from another device');
    });

    test('being offline never loses the device copy', () async {
      seedNoProfile();
      final cloud = FakeCloudStore()..offline = true;
      final local = {'value': 'on the device', kCloudUpdatedAt: 1};

      expect(await _sync(cloud).pull('k', local), local);
      await _sync(cloud).push('k', local); // must not throw
    });

    test('stamp records when the data was saved', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final stamped = SyncService.stamp({'a': 1});
      expect(stamped['a'], 1);
      expect(stamped[kCloudUpdatedAt], greaterThanOrEqualTo(before));
    });
  });

  // ---------------------------------------------------------------------
  group('the repositories', () {
    test('saving writes the device first, then the cloud', () async {
      seedNoProfile();
      final cloud = FakeCloudStore();
      final repo = ProfileRepository(scope: _scope, sync: _sync(cloud));

      await repo.save(sampleProfile.copyWith(name: 'Ann'));

      // On the device...
      final onDevice = await ProfileRepository(scope: _scope).load();
      expect(onDevice!.name, 'Ann');
      // ...and in the cloud.
      expect(cloud.docs['$_uid/user_profile']!['name'], 'Ann');
      expect(cloud.docs['$_uid/user_profile']![kCloudUpdatedAt], isNotNull);
    });

    test('an offline save still succeeds locally', () async {
      seedNoProfile();
      final cloud = FakeCloudStore()..offline = true;
      final repo = ProfileRepository(scope: _scope, sync: _sync(cloud));

      await repo.save(sampleProfile.copyWith(name: 'Ann')); // must not throw

      final onDevice = await ProfileRepository(scope: _scope).load();
      expect(onDevice!.name, 'Ann');
      expect(cloud.docs, isEmpty);
    });

    test('a program saved on another device arrives on this one', () async {
      seedNoProfile();
      final cloud = FakeCloudStore();
      cloud.seed(_uid, 'program_data', {
        'activeProgramId': 'p1',
        'programs': [
          TrainingProgram(
            id: 'p1',
            name: 'From the other phone',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ).toJson(),
        ],
      }, 9999);

      final data = await ProgramRepository(
        scope: _scope,
        sync: _sync(cloud),
      ).load();
      expect(data.programs.single.name, 'From the other phone');
      expect(data.activeProgramId, 'p1');

      // It was cached, so the next launch has it with no cloud at all.
      final offline = await ProgramRepository(scope: _scope).load();
      expect(offline.programs.single.name, 'From the other phone');
    });

    test('sessions and scans sync the same way', () async {
      seedNoProfile();
      final cloud = FakeCloudStore();

      await SessionRepository(scope: _scope, sync: _sync(cloud)).save(
        SessionData(
          sessions: [
            WorkoutSession(
              id: 's1',
              workoutId: 'w',
              workoutName: 'Upper A',
              startedAt: DateTime(2026, 1, 1, 9),
              completedAt: DateTime(2026, 1, 1, 10),
            ),
          ],
        ),
      );
      await MeasurementRepository(scope: _scope, sync: _sync(cloud)).save([
        Measurement.fromNative(const {
          'ratios': {'a': 1.0},
        }),
      ]);

      expect(cloud.docs.containsKey('$_uid/session_data'), isTrue);
      expect(cloud.docs.containsKey('$_uid/measurement_data'), isTrue);
    });

    test('a guest repository never touches the cloud', () async {
      seedNoProfile();
      final cloud = FakeCloudStore();
      final sync = SyncService(
        cloud: cloud,
        scope: StorageScope.guest,
        uid: '',
      );

      await ProfileRepository(sync: sync).save(sampleProfile);
      await ProfileRepository(sync: sync).load();

      expect(cloud.reads, 0);
      expect(cloud.writes, 0);
      expect((await ProfileRepository().load())!.name, sampleProfile.name);
    });

    test('one account never reads another account\'s cloud data', () async {
      seedNoProfile();
      final cloud = FakeCloudStore();
      cloud.seed(
        'uid_ann',
        'user_profile',
        sampleProfile.copyWith(name: 'Ann').toJson(),
        100,
      );

      final bobScope = StorageScope.user('uid_bob');
      final bob = await ProfileRepository(
        scope: bobScope,
        sync: SyncService(cloud: cloud, scope: bobScope, uid: 'uid_bob'),
      ).load();

      expect(bob, isNull);
    });
  });
}
