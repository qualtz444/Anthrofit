import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/app.dart';
import 'package:anthrofit/scan/camera_permission.dart';
import 'package:anthrofit/scan/mock_scan_source.dart';
import 'package:anthrofit/scan/scan_source.dart';
import 'package:anthrofit/data/measurement_repository.dart';
import 'package:anthrofit/data/program_repository.dart';
import 'package:anthrofit/data/storage_scope.dart';
import 'package:anthrofit/models/measurement.dart';
import 'package:anthrofit/scan/scan_state.dart';
import 'package:anthrofit/screens/body_analysis/body_analysis_screen.dart';
import 'package:anthrofit/screens/scan/scan_result_screen.dart';
import 'package:anthrofit/state/measurement_controller.dart';
import 'package:anthrofit/state/measurement_scope.dart';
import 'package:anthrofit/screens/scan/scan_screen.dart';

import 'test_helpers.dart';

/// Stands in for the system permission dialog.
class FakeCameraPermission implements CameraPermission {
  FakeCameraPermission({
    this.initial = CameraAccess.notRequested,
    this.answer = CameraAccess.granted,
    this.settingsOpen = true,
  });

  /// What check() reports before anything is asked.
  CameraAccess initial;

  /// What the user chooses in the dialog.
  CameraAccess answer;

  /// Whether Settings could be opened.
  bool settingsOpen;

  int checks = 0;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<CameraAccess> check() async {
    checks++;
    return initial;
  }

  @override
  Future<CameraAccess> request() async {
    requests++;
    initial = answer; // the system remembers the answer
    return answer;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return settingsOpen;
  }
}

/// Records what the screen asked of the source, and never builds a platform view.
class SpyScanSource implements ScanSource {
  SpyScanSource({MockScanSource? inner}) : _inner = inner ?? MockScanSource();

  final MockScanSource _inner;
  int previewsBuilt = 0;
  int starts = 0;
  int retries = 0;
  int switches = 0;
  bool disposed = false;

  @override
  Stream<ScanState> get states => _inner.states;

  @override
  Widget preview() {
    previewsBuilt++;
    return const ColoredBox(
      key: ValueKey('fake-preview'),
      color: Colors.black,
      child: SizedBox.expand(),
    );
  }

  @override
  void start() {
    starts++;
    _inner.start();
  }

  @override
  void retry() {
    retries++;
    _inner.retry();
  }

  @override
  void switchCamera() {
    switches++;
    _inner.switchCamera();
  }

  @override
  void dispose() {
    disposed = true;
    _inner.dispose();
  }
}

/// ScanScreen saves a finished scan, so it needs the scan store above it.
/// The app supplies this through UserDataHost; a bare screen test has to.
Widget hostScanScreen(Widget child, {MeasurementController? store}) {
  return MeasurementScope(
    controller: store ?? MeasurementController(MeasurementRepository()),
    child: MaterialApp(home: child),
  );
}

void main() {
  // The exercise catalogue is an asset now, so it has to be loaded.
  useExerciseLibrary();

  // ---------------------------------------------------------------------
  group('ScanState from a native event', () {
    test('a full event is read as sent', () {
      final state = ScanState.fromEvent({
        'phase': 'measuring',
        'message': 'Measuring - keep still',
        'holdProgress': 1.0,
        'framesCaptured': 7,
        'framesTotal': 20,
      });
      expect(state.phase, ScanPhase.measuring);
      expect(state.message, 'Measuring - keep still');
      expect(state.holdProgress, 1);
      expect(state.framesCaptured, 7);
      expect(state.framesTotal, 20);
      expect(state.failureReason, isNull);
      expect(state.hasMeasurement, isFalse);
    });

    test('every phase the Kotlin sends is mapped', () {
      ScanPhase phase(String? raw) => ScanState.fromEvent({'phase': raw}).phase;
      expect(phase('guiding'), ScanPhase.guiding);
      expect(phase('holding'), ScanPhase.holding);
      expect(phase('measuring'), ScanPhase.measuring);
      expect(phase('done'), ScanPhase.done);
      expect(phase('failed'), ScanPhase.failed);
      expect(phase('something-new'), ScanPhase.guiding); // safe fallback
      expect(phase(null), ScanPhase.guiding);
    });

    test('a failure carries its reason', () {
      final state = ScanState.fromEvent({
        'phase': 'failed',
        'message': 'Only 8 of 20 frames were usable',
        'failureReason': 'Only 8 of 20 frames were usable',
      });
      expect(state.phase, ScanPhase.failed);
      expect(state.failureReason, 'Only 8 of 20 frames were usable');
    });

    test('a completed scan carries the whole measurement through', () {
      final state = ScanState.fromEvent({
        'phase': 'done',
        'message': 'Done',
        'measurement': {
          'takenAt': 1700000000000,
          'ratios': {'femur_torso_ratio': 1.08, 'arm_torso_ratio': 1.31},
          'precision': {
            'femur_torso_ratio': {
              'iqr': 0.01,
              'iqrPct': 0.9,
              'min': 1.07,
              'max': 1.09,
            },
          },
          'framesUsed': 18,
          'framesTotal': 20,
          'worstIqrPct': 2.8,
          'captureQuality': 'acceptable',
        },
      });
      expect(state.phase, ScanPhase.done);
      expect(state.hasMeasurement, isTrue);

      final m = state.measurement!;
      expect(m.ratios['femur_torso_ratio'], 1.08);
      expect(m.ratios['arm_torso_ratio'], 1.31);
      expect(m.precision['femur_torso_ratio']!.iqrPct, 0.9);
      expect(m.framesUsed, 18);
      expect(m.framesTotal, 20);
      expect(m.worstIqrPct, 2.8);
      expect(m.captureQuality, 'acceptable');
      expect(m.takenAt.millisecondsSinceEpoch, 1700000000000);
    });

    test('a malformed measurement loses only the bad parts', () {
      final state = ScanState.fromEvent({
        'phase': 'done',
        'measurement': {
          'ratios': {'femur_torso_ratio': 1.08, 'broken': 'not a number'},
          'precision': 'not a map',
        },
      });
      final m = state.measurement!;
      expect(m.ratios, {'femur_torso_ratio': 1.08});
      expect(m.precision, isEmpty);
      expect(m.framesUsed, 0);
      expect(m.captureQuality, '');
    });

    test('missing or odd values never crash the screen', () {
      final empty = ScanState.fromEvent({});
      expect(empty.phase, ScanPhase.guiding);
      expect(empty.message, '');
      expect(empty.holdProgress, 0);
      expect(empty.framesTotal, 20);
      expect(empty.hasMeasurement, isFalse);
      expect(empty.measurement, isNull);

      final odd = ScanState.fromEvent({
        'holdProgress': 5.0, // out of range
        'framesCaptured': 99, // more than the total
        'framesTotal': 20,
        'message': 42, // not a string
        'failureReason': '',
      });
      expect(odd.holdProgress, 1);
      expect(odd.framesCaptured, 20);
      expect(odd.message, '');
      expect(odd.failureReason, isNull);

      final nan = ScanState.fromEvent({'holdProgress': double.nan});
      expect(nan.holdProgress, 0);
    });
  });

  group('MockScanSource', () {
    testWidgets('walks guiding -> holding -> measuring -> done', (
      tester,
    ) async {
      final source = MockScanSource();
      final seen = <ScanPhase>[];
      source.states.listen((s) => seen.add(s.phase));
      source.start();
      await tester.pump(MockScanSource.tick * 50);
      await tester.pump();
      source.dispose();

      expect(seen.first, ScanPhase.guiding);
      expect(seen, contains(ScanPhase.holding));
      expect(seen, contains(ScanPhase.measuring));
      expect(seen.last, ScanPhase.done);
      expect(seen.last, isNot(ScanPhase.failed));
    });

    testWidgets('can end in failure instead', (tester) async {
      final source = MockScanSource(failInstead: true);
      ScanPhase? last;
      source.states.listen((s) => last = s.phase);
      source.start();
      await tester.pump(MockScanSource.tick * 50);
      await tester.pump();
      source.dispose();
      expect(last, ScanPhase.failed);
    });
  });

  // ---------------------------------------------------------------------
  group('Scan screen: permission comes first', () {
    Future<SpyScanSource> open(
      WidgetTester tester,
      FakeCameraPermission permission, {
      bool failInstead = false,
    }) async {
      final source = SpyScanSource(
        inner: MockScanSource(failInstead: failInstead),
      );
      seedNoProfile();
      await tester.pumpWidget(
        hostScanScreen(
          ScanScreen(permission: permission, createSource: () => source),
        ),
      );
      await tester.pumpAndSettle();
      return source;
    }

    testWidgets('nothing is created until the camera is allowed', (
      tester,
    ) async {
      final permission = FakeCameraPermission(answer: CameraAccess.denied);
      final source = await open(tester, permission);

      expect(permission.requests, 1); // asked on arrival
      expect(source.previewsBuilt, 0); // no platform view
      expect(source.starts, 0);
      expect(find.byKey(const ValueKey('fake-preview')), findsNothing);
      expect(find.text('Camera access is needed to scan'), findsOneWidget);
    });

    testWidgets('allowing the camera builds the preview and starts the scan', (
      tester,
    ) async {
      final permission = FakeCameraPermission(answer: CameraAccess.granted);
      final source = await open(tester, permission);

      expect(source.previewsBuilt, 1);
      expect(source.starts, 1);
      expect(find.byKey(const ValueKey('fake-preview')), findsOneWidget);
      expect(find.text('Camera access is needed to scan'), findsNothing);
    });

    testWidgets('an already-granted permission does not ask again', (
      tester,
    ) async {
      final permission = FakeCameraPermission(initial: CameraAccess.granted);
      final source = await open(tester, permission);

      expect(permission.requests, 0);
      expect(source.starts, 1);
    });

    testWidgets('refused once: explain, then let them ask again', (
      tester,
    ) async {
      final permission = FakeCameraPermission(answer: CameraAccess.denied);
      final source = await open(tester, permission);

      expect(find.text('Allow camera'), findsOneWidget);
      expect(find.text('Open Settings'), findsNothing);
      expect(
        find.textContaining('Nothing is recorded or uploaded'),
        findsOneWidget,
      );
      expect(
        find.textContaining('The rest of ANTHROFIT works without'),
        findsOneWidget,
      );

      permission.answer = CameraAccess.granted;
      await tester.tap(find.text('Allow camera'));
      await tester.pumpAndSettle();

      expect(permission.requests, 2);
      expect(source.previewsBuilt, 1);
      expect(find.byKey(const ValueKey('fake-preview')), findsOneWidget);
    });

    testWidgets('refused for good: Settings is the only way forward', (
      tester,
    ) async {
      final permission = FakeCameraPermission(
        answer: CameraAccess.permanentlyDenied,
      );
      await open(tester, permission);

      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.text('Allow camera'), findsNothing);
      expect(
        find.textContaining('Open Settings and allow the camera'),
        findsOneWidget,
      );

      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();
      expect(permission.settingsOpened, 1);
      expect(permission.requests, 1); // never asks again: it would not show
    });

    testWidgets('a device that cannot open Settings says so', (tester) async {
      final permission = FakeCameraPermission(
        answer: CameraAccess.permanentlyDenied,
        settingsOpen: false,
      );
      await open(tester, permission);

      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();
      expect(
        find.text("Couldn't open Settings on this device."),
        findsOneWidget,
      );
    });

    testWidgets('Not now closes the screen', (tester) async {
      final permission = FakeCameraPermission(answer: CameraAccess.denied);
      seedNoProfile();
      await tester.pumpWidget(
        hostScanScreen(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ScanScreen(
                        permission: permission,
                        createSource: SpyScanSource.new,
                      ),
                    ),
                  ),
                  child: const Text('Open scan'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open scan'));
      await tester.pumpAndSettle();
      expect(find.text('Body Scan'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Body Scan'), findsNothing);
      expect(find.text('Open scan'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------
  group('Scan screen: the capture flow', () {
    Future<SpyScanSource> openGranted(
      WidgetTester tester, {
      bool failInstead = false,
    }) async {
      final source = SpyScanSource(
        inner: MockScanSource(failInstead: failInstead),
      );
      seedNoProfile();
      await tester.pumpWidget(
        hostScanScreen(
          ScanScreen(
            permission: FakeCameraPermission(initial: CameraAccess.granted),
            createSource: () => source,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return source;
    }

    testWidgets('guidance, the hold timer, the frame count, then complete', (
      tester,
    ) async {
      await openGranted(tester);

      // Guiding.
      await tester.pump(MockScanSource.tick);
      expect(find.text('Step back so your whole body fits'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      // Holding: the timer appears.
      await tester.pump(MockScanSource.tick * 11);
      expect(find.text('Hold still'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // Measuring: frames are counted.
      await tester.pump(MockScanSource.tick * 14);
      expect(find.text('Measuring - keep still'), findsOneWidget);
      expect(find.textContaining('of 20 frames'), findsOneWidget);

      // Done: the result screen opens by itself.
      await tester.pump(MockScanSource.tick * 25);
      await tester.pumpAndSettle();
      expect(find.text('Scan result'), findsOneWidget);
      expect(find.text('Femur to torso'), findsOneWidget);
      expect(find.text('1.08'), findsOneWidget);
      expect(find.textContaining('18 of 20 frames'), findsOneWidget);

      // Closing it returns to the scan, which offers it again.
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Scan complete'), findsOneWidget);
      expect(find.text('7 measurements recorded.'), findsOneWidget);
      await tester.tap(find.text('View result'));
      await tester.pumpAndSettle();
      expect(find.text('Scan result'), findsOneWidget);
    });

    testWidgets('a failed capture explains itself and can be retried', (
      tester,
    ) async {
      final source = await openGranted(tester, failInstead: true);
      await tester.pump(MockScanSource.tick * 45);
      await tester.pumpAndSettle();

      expect(find.text("The scan didn't finish"), findsOneWidget);
      expect(
        find.textContaining('Only 8 of 20 frames were usable'),
        findsWidgets,
      );

      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(source.retries, 1);
      expect(find.text("The scan didn't finish"), findsNothing);
      // The camera was not rebuilt.
      expect(source.previewsBuilt, 1);
    });

    testWidgets('the camera can be switched, without rebuilding the preview', (
      tester,
    ) async {
      final source = await openGranted(tester);
      await tester.tap(find.byTooltip('Switch camera'));
      await tester.pump();
      await tester.pump();

      expect(source.switches, 1);
      expect(source.previewsBuilt, 1);
      expect(find.textContaining('Switched to front camera'), findsOneWidget);
    });

    testWidgets('leaving the screen shuts the scan down', (tester) async {
      seedNoProfile();
      final source = SpyScanSource();
      await tester.pumpWidget(
        hostScanScreen(
          Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => ScanScreen(
                permission: FakeCameraPermission(initial: CameraAccess.granted),
                createSource: () => source,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(source.disposed, isFalse);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      expect(source.disposed, isTrue);
    });
  });

  // ---------------------------------------------------------------------
  group('the result screen', () {
    Future<void> showResult(
      WidgetTester tester,
      Measurement measurement,
    ) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: ScanResultScreen(measurement: measurement)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows every ratio it can describe, with its spread', (
      tester,
    ) async {
      await showResult(tester, mockMeasurement());

      // Skeleton ratios.
      expect(find.text('Femur to torso'), findsOneWidget);
      expect(find.text('1.08'), findsOneWidget);
      expect(find.text('Arm to torso'), findsOneWidget);
      expect(find.text('1.31'), findsOneWidget);
      expect(find.text('Upper body to stature'), findsOneWidget);
      expect(find.text('Shoulder to hip'), findsOneWidget);

      // Outline ratios are grouped separately.
      expect(find.text('From the body outline'), findsOneWidget);
      expect(find.text('Waist to hip (outline)'), findsOneWidget);
      expect(find.text('0.84'), findsOneWidget);

      // Precision is reported where the pipeline gave it.
      expect(find.text('Varied by 0.9% across frames'), findsOneWidget);
      expect(find.text('Varied by 2.8% across frames'), findsOneWidget);

      // And the capture summary.
      expect(find.text('Acceptable'), findsOneWidget);
      expect(
        find.textContaining('18 of 20 frames were usable'),
        findsOneWidget,
      );
      expect(find.textContaining('widest spread 2.8%'), findsOneWidget);
    });

    testWidgets('an unsteady capture says so plainly', (tester) async {
      await showResult(
        tester,
        Measurement.fromNative({
          'takenAt': DateTime.now().millisecondsSinceEpoch,
          'ratios': {'femur_torso_ratio': 1.1},
          'precision': <String, dynamic>{},
          'framesUsed': 9,
          'framesTotal': 20,
          'worstIqrPct': 11.4,
          'captureQuality': 'unstable',
        }),
      );

      expect(find.text('Unsteady'), findsOneWidget);
      expect(find.textContaining('moved a lot between frames'), findsOneWidget);
      expect(find.textContaining('9 of 20 frames'), findsOneWidget);
      // No spread line for a ratio the pipeline gave no precision for.
      expect(find.textContaining('Varied by'), findsNothing);
    });

    testWidgets('a scan with no ratios says so instead of showing nothing', (
      tester,
    ) async {
      await showResult(tester, Measurement.fromNative(const {}));
      expect(find.text('This scan produced no measurements.'), findsOneWidget);
      expect(find.text('Femur to torso'), findsNothing);
    });

    testWidgets(
      'ratios this version cannot describe are counted, not guessed',
      (tester) async {
        await showResult(
          tester,
          Measurement.fromNative({
            'ratios': {'femur_torso_ratio': 1.08, 'brand_new_ratio': 0.5},
            'framesUsed': 20,
            'framesTotal': 20,
            'captureQuality': 'good',
          }),
        );

        expect(find.text('Femur to torso'), findsOneWidget);
        expect(find.textContaining('brand_new_ratio'), findsNothing);
        expect(find.textContaining('Not shown: 1 measurement'), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------
  group('saving a scan', () {
    test('a scan is kept, newest first, and survives a restart', () async {
      seedNoProfile();
      final store = MeasurementController(MeasurementRepository());
      await store.load();
      expect(store.measurements, isEmpty);
      expect(store.latest, isNull);

      final older = Measurement.fromNative({
        'id': 'older',
        'takenAt': DateTime(2026, 10, 1).millisecondsSinceEpoch,
        'ratios': {'femur_torso_ratio': 1.05},
        'framesUsed': 20,
        'framesTotal': 20,
        'captureQuality': 'good',
      });
      final newer = Measurement.fromNative({
        'id': 'newer',
        'takenAt': DateTime(2026, 10, 5).millisecondsSinceEpoch,
        'ratios': {'femur_torso_ratio': 1.08},
        'precision': {
          'femur_torso_ratio': {
            'iqr': 0.01,
            'iqrPct': 0.9,
            'min': 1.07,
            'max': 1.09,
          },
        },
        'framesUsed': 18,
        'framesTotal': 20,
        'worstIqrPct': 2.8,
        'captureQuality': 'acceptable',
      });

      await store.add(older);
      await store.add(newer);
      expect(store.measurements.map((m) => m.id).toList(), ['newer', 'older']);
      expect(store.latest!.id, 'newer');

      // Reload from storage: everything comes back.
      final reloaded = MeasurementController(MeasurementRepository());
      await reloaded.load();
      expect(reloaded.measurements.map((m) => m.id).toList(), [
        'newer',
        'older',
      ]);
      final back = reloaded.byId('newer')!;
      expect(back.ratios['femur_torso_ratio'], 1.08);
      expect(back.precision['femur_torso_ratio']!.iqrPct, 0.9);
      expect(back.framesUsed, 18);
      expect(back.captureQuality, 'acceptable');
      expect(back.takenAt, DateTime(2026, 10, 5));
    });

    test('saving the same scan twice does not duplicate it', () async {
      seedNoProfile();
      final store = MeasurementController(MeasurementRepository());
      await store.load();
      final scan = mockMeasurement();
      await store.add(scan);
      await store.add(scan);
      expect(store.measurements.length, 1);
    });

    test('a scan can be deleted', () async {
      seedNoProfile();
      final store = MeasurementController(MeasurementRepository());
      await store.load();
      final scan = mockMeasurement();
      await store.add(scan);
      await store.delete(scan.id);
      expect(store.measurements, isEmpty);

      final reloaded = MeasurementController(MeasurementRepository());
      await reloaded.load();
      expect(reloaded.measurements, isEmpty);
    });

    testWidgets('deleting a scan from Body Analysis removes it after confirmation',
        (tester) async {
      seedNoProfile();
      final store = MeasurementController(MeasurementRepository());
      await store.load();
      final scan = mockMeasurement();
      await store.add(scan);

      await tester.pumpWidget(
        MeasurementScope(
          controller: store,
          child: const MaterialApp(home: BodyAnalysisScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Current analysis'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete scan').first);
      await tester.pumpAndSettle();

      expect(find.text('Delete scan?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Scan deleted'), findsOneWidget);
      expect(store.measurements, isEmpty);
    });

    test('one owner never sees another owner\'s scans', () async {
      seedNoProfile();
      final guest = MeasurementController(MeasurementRepository());
      await guest.load();
      await guest.add(mockMeasurement());

      final account = MeasurementController(
        MeasurementRepository(scope: StorageScope.user('uid_ann')),
      );
      await account.load();
      expect(account.measurements, isEmpty);
      expect(guest.measurements.length, 1);
    });

    testWidgets('finishing a scan saves it', (tester) async {
      seedNoProfile();
      final store = MeasurementController(MeasurementRepository());
      await store.load();
      final source = SpyScanSource();
      await tester.pumpWidget(
        hostScanScreen(
          ScanScreen(
            permission: FakeCameraPermission(initial: CameraAccess.granted),
            createSource: () => source,
          ),
          store: store,
        ),
      );
      await tester.pumpAndSettle();

      await tester.pump(MockScanSource.tick * 50);
      await tester.pumpAndSettle();

      expect(find.text('Scan result'), findsOneWidget);
      expect(store.measurements.length, 1);
      expect(store.latest!.ratios['femur_torso_ratio'], 1.08);
      expect(find.textContaining("wasn't saved"), findsNothing);
    });

    testWidgets('finishing a scan never personalizes by itself', (
      tester,
    ) async {
      seedNoProfile();
      final store = MeasurementController(MeasurementRepository());
      await store.load();
      final source = SpyScanSource();
      await tester.pumpWidget(
        hostScanScreen(
          ScanScreen(
            permission: FakeCameraPermission(initial: CameraAccess.granted),
            createSource: () => source,
          ),
          store: store,
        ),
      );
      await tester.pumpAndSettle();

      await tester.pump(MockScanSource.tick * 50);
      await tester.pumpAndSettle();

      // The result is shown, with the choice offered...
      expect(find.text('Scan result'), findsOneWidget);
      expect(find.text('Personalize My Program'), findsOneWidget);
      // ...but nothing has been started or built on the user's behalf.
      expect(find.text('Building your personalized plan…'), findsNothing);
      expect(find.text('Your program'), findsNothing);
      final programs = await tester.runAsync(() => ProgramRepository().load());
      expect(programs!.programs, isEmpty);
      // The scan itself was still saved, as before.
      expect(store.measurements.length, 1);
    });

    testWidgets('an empty scan is shown but not kept', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScanResultScreen(
            measurement: Measurement.fromNative(const {}),
            saved: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('This scan produced no measurements.'), findsOneWidget);
      expect(
        find.textContaining("wasn't saved"),
        findsNothing,
      ); // empty state only
    });
  });

  // ---------------------------------------------------------------------
  group('the Scan button in the app shell', () {
    void useTallScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('the four tabs still work and Scan sits in the middle', (
      tester,
    ) async {
      seedSavedProfile();
      useTallScreen(tester);
      await tester.pumpWidget(AnthrofitApp(authService: FakeAuthService()));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      for (final label in ['Home', 'Progress', 'Program', 'Profile']) {
        expect(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
          findsOneWidget,
          reason: label,
        );
      }
      expect(find.byTooltip('Body scan'), findsOneWidget);

      // Each tab still opens its own screen.
      for (final label in ['Progress', 'Program', 'Profile', 'Home']) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(AppBar, label),
          findsOneWidget,
          reason: label,
        );
      }
    });

    testWidgets(
      'the Scan button opens the scan protocol, and back returns to the tabs',
      (tester) async {
        seedSavedProfile();
        useTallScreen(tester);
        await tester.pumpWidget(AnthrofitApp(authService: FakeAuthService()));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Body scan'));
        await tester.pump(); // start the route
        await tester.pump(const Duration(seconds: 1)); // let it land

        // The protocol: one guided session to start, and each scan still
        // reachable on its own.
        expect(find.byKey(const ValueKey('start-guided-scan')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('choose-proportion-scan')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('choose-body-composition')),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.checkroom_outlined), findsOneWidget);
        expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
        expect(find.byIcon(Icons.phone_android), findsOneWidget);
        expect(find.byIcon(Icons.accessibility_new), findsOneWidget);
        expect(find.byKey(const ValueKey('save-photos')), findsNothing);
        expect(find.textContaining('US adults aged 18-59'), findsNothing);
        // The sample profile's sex is "prefer not to say", so the
        // composition step cannot run and the session cannot start.
        expect(
          find.byKey(const ValueKey('composition-blocker')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('choose-proportion-scan')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Body Scan'), findsOneWidget);

        // Back to the protocol, then back to the tabs.
        await tester.pageBack();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byKey(const ValueKey('start-guided-scan')), findsOneWidget);
        await tester.pageBack();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.widgetWithText(AppBar, 'Home'), findsOneWidget);
      },
    );

    testWidgets('the Scan button stays docked when a message appears', (
      tester,
    ) async {
      seedSavedProfile();
      useTallScreen(tester);
      await tester.pumpWidget(AnthrofitApp(authService: FakeAuthService()));
      await tester.pumpAndSettle();

      final scanButton = find.byTooltip('Body scan');
      final positionBefore = tester.getCenter(scanButton);
      ScaffoldMessenger.of(
        tester.element(find.byType(NavigationBar)),
      ).showSnackBar(const SnackBar(content: Text('Message')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.getCenter(scanButton), positionBefore);
    });
  });
}
