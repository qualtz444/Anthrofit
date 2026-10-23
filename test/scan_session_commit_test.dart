import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/data/measurement_repository.dart';
import 'package:anthrofit/data/profile_repository.dart';
import 'package:anthrofit/data/scan_session_journal.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/scan/mock_scan_source.dart';
import 'package:anthrofit/state/measurement_controller.dart';
import 'package:anthrofit/state/profile_controller.dart';
import 'package:anthrofit/state/scan_session_commit.dart';

import 'test_helpers.dart';

// Saving a guided scan is all or nothing: either both the proportion scan
// and the composition record end up saved (now, or after the next load), or
// neither does. Storage failures are simulated by repositories that refuse
// to write.

class _FlakyScans extends MeasurementRepository {
  bool fail = false;
  @override
  Future<void> save(List<Measurement> measurements) async {
    if (fail) throw StateError('disk');
    return super.save(measurements);
  }
}

class _FlakyProfiles extends ProfileRepository {
  bool fail = false;
  @override
  Future<void> save(UserProfile profile) async {
    if (fail) throw StateError('disk');
    return super.save(profile);
  }
}

class _FlakyJournal extends ScanSessionJournal {
  bool fail = false;
  @override
  Future<void> write(PendingScanSession session) async {
    if (fail) throw StateError('disk');
    return super.write(session);
  }
}

CompositionRecord _record(String id) => CompositionRecord(
  id: id,
  takenAt: DateTime(2026, 10, 13),
  weightKg: 65.5,
  bodyFatPct: 18.4,
  bodyFatLow: 14.9,
  bodyFatHigh: 22.1,
  leanLimbKg: 24,
  fatFreeMassKg: 53.4,
  fatMassKg: 12.1,
  waistCm: 82.1,
  chestCm: 98,
  hipCm: 95.3,
  thighCm: 55.4,
  upperArmCm: 30.2,
  frameCount: 3,
);

void main() {
  late _FlakyScans scanRepo;
  late _FlakyProfiles profileRepo;
  late _FlakyJournal journal;
  late MeasurementController scans;
  late ProfileController profiles;

  setUp(() async {
    seedNoProfile();
    scanRepo = _FlakyScans();
    profileRepo = _FlakyProfiles();
    journal = _FlakyJournal();
    scans = MeasurementController(scanRepo);
    profiles = ProfileController(profileRepo);
    await scans.load();
    await profiles.save(sampleProfile.copyWith(sex: Sex.male));
  });

  /// What the next launch sees: fresh controllers reading storage, then the
  /// same recovery the app runs once both have loaded.
  Future<(MeasurementController, ProfileController)> relaunch() async {
    final s = MeasurementController(MeasurementRepository());
    final p = ProfileController(ProfileRepository());
    await Future.wait([s.load(), p.load()]);
    await applyPendingScanSession(
      journal: ScanSessionJournal(),
      profiles: p,
      scans: s,
    );
    return (s, p);
  }

  Future<bool> commit(PendingScanSession session) => commitScanSession(
    journal: journal,
    session: session,
    profiles: profiles,
    scans: scans,
  );

  test('both parts are saved, once, and nothing is left pending', () async {
    final scan = mockMeasurement();
    expect(
      await commit(PendingScanSession(measurement: scan, record: _record('a'))),
      isTrue,
    );
    expect(scans.measurements.map((m) => m.id), [scan.id]);
    expect(profiles.profile!.compositionLog.map((r) => r.id), ['a']);
    expect(await journal.read(), isNull);

    final (s, p) = await relaunch();
    expect(s.measurements, hasLength(1));
    expect(p.profile!.compositionLog, hasLength(1));
  });

  test('if the commit fails, nothing is saved anywhere', () async {
    journal.fail = true;
    final ok = await commit(
      PendingScanSession(measurement: mockMeasurement(), record: _record('a')),
    );
    expect(ok, isFalse);
    expect(scans.measurements, isEmpty);
    expect(profiles.profile!.compositionLog, isEmpty);

    final (s, p) = await relaunch();
    expect(s.measurements, isEmpty);
    expect(p.profile!.compositionLog, isEmpty);
  });

  test('a scan copy that fails is finished on the next load', () async {
    scanRepo.fail = true;
    final scan = mockMeasurement();
    expect(
      await commit(PendingScanSession(measurement: scan, record: _record('a'))),
      isTrue, // committed: it will not be lost
    );
    expect(await journal.read(), isNotNull);

    final (s, p) = await relaunch();
    expect(s.measurements.map((m) => m.id), [scan.id]);
    expect(p.profile!.compositionLog.map((r) => r.id), ['a']);
    expect(await journal.read(), isNull);
  });

  test('a profile copy that fails is finished without a second scan', () async {
    profileRepo.fail = true;
    final scan = mockMeasurement();
    await commit(PendingScanSession(measurement: scan, record: _record('a')));
    // The scan copied in, the record did not: still pending.
    expect(scans.measurements, hasLength(1));
    expect(await journal.read(), isNotNull);

    final (s, p) = await relaunch();
    expect(s.measurements, hasLength(1));
    expect(p.profile!.compositionLog.map((r) => r.id), ['a']);
    expect(await journal.read(), isNull);
  });

  test('finishing twice changes nothing', () async {
    profileRepo.fail = true;
    await commit(
      PendingScanSession(measurement: mockMeasurement(), record: _record('a')),
    );
    profileRepo.fail = false;
    for (var i = 0; i < 2; i++) {
      await applyPendingScanSession(
        journal: journal,
        profiles: profiles,
        scans: scans,
      );
    }
    expect(scans.measurements, hasLength(1));
    expect(profiles.profile!.compositionLog, hasLength(1));
  });

  test('a stuck earlier session is never overwritten by a new one', () async {
    profileRepo.fail = true;
    final first = mockMeasurement();
    await commit(PendingScanSession(measurement: first, record: _record('a')));

    // The earlier one cannot be finished yet, so the new one is refused
    // rather than written over it.
    final second = mockMeasurement();
    expect(
      await commit(
        PendingScanSession(measurement: second, record: _record('b')),
      ),
      isFalse,
    );
    expect(scans.byId(second.id), isNull);

    // Once storage works again, both end up saved.
    profileRepo.fail = false;
    expect(
      await commit(
        PendingScanSession(measurement: second, record: _record('b')),
      ),
      isTrue,
    );
    expect(scans.measurements, hasLength(2));
    expect(
      profiles.profile!.compositionLog.map((r) => r.id),
      containsAll(['a', 'b']),
    );
    expect(await journal.read(), isNull);
  });
}
