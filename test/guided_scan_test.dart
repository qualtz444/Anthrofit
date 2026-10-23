import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/composition/composition_models.dart';
import 'package:anthrofit/composition/composition_source.dart';
import 'package:anthrofit/composition/composition_visuals.dart';
import 'package:anthrofit/composition/silhouette_features.dart';
import 'package:anthrofit/data/measurement_repository.dart';
import 'package:anthrofit/data/profile_repository.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/scan/camera_permission.dart';
import 'package:anthrofit/scan/mock_scan_source.dart';
import 'package:anthrofit/scan/scan_source.dart';
import 'package:anthrofit/scan/scan_state.dart';
import 'package:anthrofit/screens/body_analysis/body_analysis_screen.dart';
import 'package:anthrofit/screens/scan/combined_scan_result_screen.dart';
import 'package:anthrofit/screens/scan/scan_choice_screen.dart';
import 'package:anthrofit/state/measurement_controller.dart';
import 'package:anthrofit/state/measurement_scope.dart';
import 'package:anthrofit/state/profile_controller.dart';
import 'package:anthrofit/state/profile_scope.dart';

import 'test_helpers.dart';

// The guided scan session, end to end, with hand-driven capture sources and
// the real composition models (so the estimate is the real pipeline's).

class _Granted implements CameraPermission {
  @override
  Future<CameraAccess> check() async => CameraAccess.granted;
  @override
  Future<CameraAccess> request() async => CameraAccess.granted;
  @override
  Future<bool> openSettings() async => true;
}

class _FakeScanSource implements ScanSource {
  final controller = StreamController<ScanState>.broadcast();
  int retries = 0;
  @override
  Stream<ScanState> get states => controller.stream;
  @override
  Widget preview() => const ColoredBox(color: Colors.black);
  @override
  void start() {}
  @override
  void retry() => retries++;
  @override
  void switchCamera() {}
  @override
  void dispose() => controller.close();
}

class _FakeCompositionSource implements CompositionSource {
  final controller = StreamController<CompositionCaptureState>.broadcast();
  int starts = 0;
  int retries = 0;
  @override
  Stream<CompositionCaptureState> get states => controller.stream;
  @override
  Widget preview() => const ColoredBox(color: Colors.black);
  @override
  void start() => starts++;
  @override
  void retry() => retries++;
  @override
  void dispose() => controller.close();
}

/// Records what would be written to the phone, without touching the disk.
class _SpyStore extends CompositionVisualStore {
  final saved = <String, CompositionVisuals>{};
  final deleted = <String>[];

  /// Makes the picture write fail, like a full disk.
  bool failSave = false;

  @override
  Future<void> save(String recordId, CompositionVisuals visuals) async {
    if (failSave) throw const FileSystemException('disk full');
    saved[recordId] = visuals;
  }

  @override
  Future<void> delete(String recordId) async {
    deleted.add(recordId);
    saved.remove(recordId);
  }

  @override
  Future<CompositionVisuals> load(String recordId) async =>
      saved[recordId] ?? CompositionVisuals.none;
}

const _models = 'assets/composition';
const _fixtures = 'test/fixtures/composition';

SilhouetteMask _mask(Map<String, dynamic> m) {
  final w = m['w'] as int;
  final h = m['h'] as int;
  final out = Uint8List(w * h);
  final rows = m['rows'] as List;
  for (var y = 0; y < h; y++) {
    final runs = (rows[y] as List).cast<int>();
    for (var i = 0; i < runs.length; i += 2) {
      out.fillRange(y * w + runs[i], y * w + runs[i] + runs[i + 1], 1);
    }
  }
  return SilhouetteMask(mask: out, width: w, height: h);
}

final _photo = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

void _useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// The text of the "session ended" card on the protocol screen. (The step
/// names also appear in the protocol's own instructions.)
Finder _banner(String text) => find.descendant(
  of: find.byKey(const ValueKey('scan-session-ended')),
  matching: find.textContaining(text),
);

void main() {
  late CompositionModels models;
  late SilhouetteMask front;
  late SilhouetteMask side;

  setUpAll(() async {
    models = await CompositionModels.load(
      manifestJson: File('$_models/manifest.json').readAsStringSync(),
      readFile: (file) async => File('$_models/$file').readAsBytesSync(),
    );
    final masks =
        jsonDecode(File('$_fixtures/sample_masks.json').readAsStringSync())
            as Map<String, dynamic>;
    front = _mask(masks['front'] as Map<String, dynamic>);
    side = _mask(masks['side'] as Map<String, dynamic>);
  });

  late _FakeScanSource scan;
  late _FakeCompositionSource comp;
  late _SpyStore store;
  late ProfileController profiles;
  late MeasurementController scans;
  bool? photosAsked;

  final earlierScan = mockMeasurement();
  final earlierRecord = CompositionRecord(
    id: 'earlier',
    takenAt: DateTime(2026, 1, 1),
    weightKg: 65,
    bodyFatPct: 20,
    bodyFatLow: 17,
    bodyFatHigh: 23,
    leanLimbKg: 23,
    fatFreeMassKg: 52,
    fatMassKg: 13,
    waistCm: 80,
    chestCm: 95,
    hipCm: 94,
    thighCm: 54,
    upperArmCm: 29,
    frameCount: 3,
  );

  Future<void> open(WidgetTester tester) async {
    seedNoProfile();
    scan = _FakeScanSource();
    comp = _FakeCompositionSource();
    store = _SpyStore();
    photosAsked = null;
    profiles = ProfileController(ProfileRepository());
    scans = MeasurementController(MeasurementRepository());
    _useTallScreen(tester);
    await tester.runAsync(() async {
      await profiles.save(
        sampleProfile.copyWith(
          sex: Sex.male,
          compositionLog: [earlierRecord],
        ),
      );
      await scans.add(earlierScan);
    });
    await tester.pumpWidget(
      ProfileScope(
        controller: profiles,
        child: MeasurementScope(
          controller: scans,
          child: MaterialApp(
            home: ScanChoiceScreen(
              permission: _Granted(),
              createScanSource: () => scan,
              createCompositionSource: (includePhotos) {
                photosAsked = includePhotos;
                return comp;
              },
              loadModels: () async => models,
              visualStore: store,
              handoff: const Duration(seconds: 3),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Start, then the height and weight check, left as it is.
  Future<void> startSession(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('start-guided-scan')));
    await settle(tester);
    expect(find.byKey(const ValueKey('body-check-sheet')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('body-check-continue')));
    await settle(tester);
    expect(find.text('Body Scan'), findsOneWidget);
  }

  Future<void> finishStep1(WidgetTester tester) async {
    scan.controller.add(
      ScanState(
        phase: ScanPhase.done,
        message: 'Done',
        measurement: mockMeasurement(),
      ),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('guided-handoff')), findsOneWidget);
    // No proportion result screen in between.
    expect(find.text('Scan result'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    expect(comp.starts, 1);
  }

  void finishStep2({List<SilhouetteMask>? frontMasks}) => comp.controller.add(
    CompositionCaptureState(
      phase: CompositionPhase.done,
      front: frontMasks ?? [front],
      side: [side],
      frontPhoto: _photo,
      sidePhoto: _photo,
    ),
  );

  Future<void> waitForResults(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await settle(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('a full session saves both once and shows one results screen', (
    tester,
  ) async {
    await open(tester);
    await startSession(tester);
    await finishStep1(tester);
    // Nothing saved yet: the proportion scan is held until step 2 succeeds.
    expect(scans.measurements, [earlierScan]);

    finishStep2();
    await waitForResults(tester);

    expect(find.byType(CombinedScanResultScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('section-proportions')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('section-composition')),
      300,
    );
    expect(find.byKey(const ValueKey('section-composition')), findsOneWidget);
    expect(find.byKey(const ValueKey('guided-not-saved')), findsNothing);

    // Saved once each, history kept apart, earlier results untouched.
    expect(scans.measurements, hasLength(2));
    expect(scans.measurements, contains(earlierScan));
    final log = profiles.profile!.compositionLog;
    expect(log, hasLength(2));
    expect(log.first.id, 'earlier');

    // Photos are always captured and stored with the finished session.
    expect(photosAsked, isTrue);
    expect(store.saved, hasLength(1));
    expect(store.saved.values.single.hasPhotos, isTrue);
    expect(store.saved.values.single.hasOutlines, isTrue);

    // Exactly the three next steps.
    expect(find.byKey(const ValueKey('guided-next-program')), findsOneWidget);
    expect(find.byKey(const ValueKey('guided-next-nutrition')), findsOneWidget);
    expect(find.byKey(const ValueKey('guided-next-analysis')), findsOneWidget);
    expect(find.text('Generate My Program'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('guided-next-analysis')));
    await tester.pumpAndSettle();
    expect(find.byType(BodyAnalysisScreen), findsOneWidget);
  });

  testWidgets('if the pictures cannot be saved, nothing is saved', (
    tester,
  ) async {
    await open(tester);
    store.failSave = true;
    await startSession(tester);
    await finishStep1(tester);
    finishStep2();
    await waitForResults(tester);

    expect(find.byKey(const ValueKey('guided-not-saved')), findsOneWidget);
    expect(scans.measurements, [earlierScan]);
    expect(profiles.profile!.compositionLog, [earlierRecord]);
    expect(store.saved, isEmpty);
    expect(store.deleted, hasLength(1)); // partial pictures cleaned up

    // Trying again once the phone accepts the write saves everything once.
    store.failSave = false;
    await tester.tap(find.text('Try saving again'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guided-not-saved')), findsNothing);
    expect(scans.measurements, hasLength(2));
    expect(profiles.profile!.compositionLog, hasLength(2));
    expect(store.saved, hasLength(1));
  });

  testWidgets('photos are always kept only with a finished session', (
    tester,
  ) async {
    await open(tester);
    await startSession(tester);
    await finishStep1(tester);
    expect(photosAsked, isTrue);
    finishStep2();
    await waitForResults(tester);
    expect(store.saved.values.single.hasPhotos, isTrue);
  });

  testWidgets('an unusable capture is retried in place, without a reset', (
    tester,
  ) async {
    await open(tester);
    await startSession(tester);

    // Step 1 fails once: Try again stays on step 1.
    scan.controller.add(
      const ScanState(
        phase: ScanPhase.failed,
        message: 'Lost you',
        failureReason: 'Only 8 of 20 frames were usable',
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(scan.retries, 1);
    expect(find.text('Body Scan'), findsOneWidget);
    await finishStep1(tester);

    // Step 2 gives no usable frames once: Try again stays on step 2.
    finishStep2(frontMasks: const []);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await settle(tester);
    expect(find.text("The capture didn't finish"), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(comp.retries, 1);
    expect(scans.measurements, [earlierScan]); // still nothing saved

    finishStep2();
    await waitForResults(tester);
    expect(find.byType(CombinedScanResultScreen), findsOneWidget);
    expect(scans.measurements, hasLength(2));
    expect(profiles.profile!.compositionLog, hasLength(2));
  });

  testWidgets('giving up on step 1 resets the session and saves nothing', (
    tester,
  ) async {
    await open(tester);
    await startSession(tester);
    scan.controller.add(
      const ScanState(
        phase: ScanPhase.failed,
        message: 'Lost you',
        failureReason: 'Only 8 of 20 frames were usable',
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(_banner('Step 1, body proportions'), findsOneWidget);
    expect(find.text('Start again'), findsOneWidget);
    expect(scans.measurements, [earlierScan]);
    expect(profiles.profile!.compositionLog, [earlierRecord]);
  });

  testWidgets('an empty proportion scan counts as a step 1 failure', (
    tester,
  ) async {
    await open(tester);
    await startSession(tester);
    scan.controller.add(
      const ScanState(phase: ScanPhase.done, message: 'Done'),
    );
    await tester.pumpAndSettle();
    expect(_banner('Step 1, body proportions'), findsOneWidget);
    expect(scans.measurements, [earlierScan]);
  });

  testWidgets('giving up on step 2 discards step 1 and returns to the start', (
    tester,
  ) async {
    await open(tester);
    await startSession(tester);
    await finishStep1(tester);
    comp.controller.add(
      const CompositionCaptureState(
        phase: CompositionPhase.failed,
        failureReason: 'Turn fully to the side',
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(_banner('Step 2, body composition'), findsOneWidget);
    expect(_banner('Turn fully to the side'), findsOneWidget);
    expect(scans.measurements, [earlierScan]);
    expect(profiles.profile!.compositionLog, [earlierRecord]);
    expect(store.saved, isEmpty);

    // A new session starts from step 1 with nothing left over.
    scan = _FakeScanSource();
    await startSession(tester);
  });

  testWidgets('height and weight are checked first, filled from the profile', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('start-guided-scan')));
    await settle(tester);

    // Filled in from the profile: 170 cm and 65.5 kg.
    Finder inSheet(String key, String text) => find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.text(text),
    );
    expect(inSheet('body-check-height', '170'), findsOneWidget);
    expect(inSheet('body-check-weight', '65.5'), findsOneWidget);

    // Closing the sheet does not start the scan or change the profile.
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(find.byKey(const ValueKey('body-check-sheet')), findsNothing);
    expect(find.text('Body Scan'), findsNothing);
    expect(profiles.profile!.weightKg, 65.5);

    // A changed weight is saved to the profile, then the scan starts.
    await tester.tap(find.byKey(const ValueKey('start-guided-scan')));
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('body-check-weight')),
        matching: find.byTooltip('More'),
      ),
    );
    await tester.pump();
    expect(inSheet('body-check-weight', '66.5'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('body-check-continue')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await settle(tester);
    expect(profiles.profile!.weightKg, 66.5);
    expect(profiles.profile!.heightCm, 170);
    expect(find.text('Body Scan'), findsOneWidget);
  });

  testWidgets('leaving mid-session cancels it and saves nothing', (
    tester,
  ) async {
    await open(tester);
    await startSession(tester);
    await finishStep1(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(_banner('Scan cancelled'), findsOneWidget);
    expect(scans.measurements, [earlierScan]);
    expect(profiles.profile!.compositionLog, [earlierRecord]);
  });
}
