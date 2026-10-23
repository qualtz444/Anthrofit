import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:anthrofit/composition/composition_source.dart';
import 'package:anthrofit/composition/composition_visuals.dart';
import 'package:anthrofit/composition/mask_codec.dart';
import 'package:anthrofit/composition/silhouette_features.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/screens/composition/composition_compare_screen.dart';
import 'package:anthrofit/screens/composition/composition_record_screen.dart';
import 'package:anthrofit/screens/composition/outline_overlay.dart';
import 'package:anthrofit/data/measurement_repository.dart';
import 'package:anthrofit/data/profile_repository.dart';
import 'package:anthrofit/screens/body_analysis/body_analysis_screen.dart';
import 'package:anthrofit/state/measurement_controller.dart';
import 'package:anthrofit/state/measurement_scope.dart';
import 'package:anthrofit/state/profile_controller.dart';
import 'package:anthrofit/state/profile_scope.dart';

import 'test_helpers.dart';

SilhouetteMask _mask() {
  // 4 x 3: a two-pixel run in the middle row, one pixel on the others.
  final m = Uint8List.fromList([
    0, 1, 0, 0, //
    0, 1, 1, 0, //
    0, 1, 0, 0, //
  ]);
  return SilhouetteMask(mask: m, width: 4, height: 3);
}

CompositionRecord _record(String id, DateTime when, double bf) =>
    CompositionRecord(
      id: id,
      takenAt: when,
      weightKg: 70,
      bodyFatPct: bf,
      bodyFatLow: bf - 3,
      bodyFatHigh: bf + 3,
      leanLimbKg: 24,
      fatFreeMassKg: 70 * (1 - bf / 100),
      fatMassKg: 70 * bf / 100,
      waistCm: 80,
      chestCm: 95,
      hipCm: 95,
      thighCm: 55,
      upperArmCm: 30,
      frameCount: 3,
    );

/// Serves visuals from memory, so widget tests need no file system.
class _MemoryStore extends CompositionVisualStore {
  _MemoryStore(this.byId)
    : super(baseDirectory: () async => Directory.systemTemp);

  final Map<String, CompositionVisuals> byId;

  @override
  Future<CompositionVisuals> load(String recordId) async =>
      byId[recordId] ?? CompositionVisuals.none;

  @override
  Future<void> delete(String recordId) async {}
}

void main() {
  test('an outline survives encoding and decoding', () {
    final mask = _mask();
    final back = decodeRunMask(encodeRunMask(mask))!;
    expect(back.width, 4);
    expect(back.height, 3);
    expect(back.mask, mask.mask);
  });

  test('photos arrive with the done event', () {
    final state = CompositionCaptureState.fromEvent({
      'phase': 'done',
      'front': [encodeRunMask(_mask())],
      'side': [encodeRunMask(_mask())],
      'frontPhoto': Uint8List.fromList([1, 2, 3]),
    });
    expect(state.frontPhoto, [1, 2, 3]);
    expect(state.sidePhoto, isNull);
  });

  group('store', () {
    late Directory dir;
    late CompositionVisualStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('anthrofit_visuals');
      store = CompositionVisualStore(baseDirectory: () async => dir);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('saves, loads and deletes one scan', () async {
      await store.save(
        'scan-1',
        CompositionVisuals(
          frontOutline: _mask(),
          sideOutline: _mask(),
          frontPhoto: Uint8List.fromList([9, 9]),
        ),
      );
      final loaded = await store.load('scan-1');
      expect(loaded.frontOutline!.mask, _mask().mask);
      expect(loaded.sideOutline, isNotNull);
      expect(loaded.frontPhoto, [9, 9]);
      expect(loaded.sidePhoto, isNull);

      await store.deletePhotos('scan-1');
      final noPhotos = await store.load('scan-1');
      expect(noPhotos.hasPhotos, isFalse);
      expect(noPhotos.hasOutlines, isTrue);

      await store.delete('scan-1');
      expect((await store.load('scan-1')).isEmpty, isTrue);
    });

    test('nothing stored reads as none', () async {
      expect((await store.load('missing')).isEmpty, isTrue);
    });

    test('legacy photo files are not treated as verified originals', () async {
      await store.save(
        'legacy-scan',
        CompositionVisuals(frontOutline: _mask(), sideOutline: _mask()),
      );
      final legacyDir = Directory(
        '${dir.path}/${CompositionVisualStore.folder}/legacy-scan',
      );
      await File('${legacyDir.path}/front.jpg').writeAsBytes([1, 2, 3]);
      await File('${legacyDir.path}/side.jpg').writeAsBytes([4, 5, 6]);

      final loaded = await store.load('legacy-scan');
      expect(loaded.frontOutline, isNotNull);
      expect(loaded.sideOutline, isNotNull);
      expect(loaded.frontPhoto, isNull);
      expect(loaded.sidePhoto, isNull);
    });

    test('saved camera photos retain their original color', () async {
      final original = img.Image(width: 40, height: 20);
      for (var y = 0; y < original.height; y++) {
        for (var x = 0; x < original.width; x++) {
          original.setPixelRgb(x, y, x < 20 ? 240 : 10, 10, x < 20 ? 10 : 240);
        }
      }
      final jpeg = Uint8List.fromList(img.encodeJpg(original, quality: 90));

      await store.save(
        'color-scan',
        CompositionVisuals(frontPhoto: jpeg, sidePhoto: jpeg),
      );
      final loaded = await store.load('color-scan');
      final front = img.decodeImage(loaded.frontPhoto!)!;
      final left = front.getPixel(8, 10);
      final right = front.getPixel(32, 10);

      expect(left.r, greaterThan(left.b));
      expect(right.b, greaterThan(right.r));
      expect(loaded.sidePhoto, jpeg);
    });
  });

  group('compare screen', () {
    final older = _record('a', DateTime(2026, 9, 1), 22);
    final newer = _record('b', DateTime(2026, 10, 1), 20);

    Future<void> pump(
      WidgetTester tester,
      Map<String, CompositionVisuals> visuals,
    ) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: CompositionCompareScreen(
            records: [newer, older],
            visualStore: _MemoryStore(visuals),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('numbers, the change, and the overlap caution', (
      tester,
    ) async {
      await pump(tester, const {});
      expect(find.text('22.0%'), findsOneWidget);
      expect(find.text('20.0%'), findsOneWidget);
      expect(find.text('−2.0 pts'), findsOneWidget);
      // 19-25 and 17-23 overlap.
      expect(find.textContaining('may not be a real change'), findsOneWidget);
      expect(
        find.text('Original photos are unavailable for these scans.'),
        findsOneWidget,
      );
    });

    testWidgets('outlines overlay; photos only on request', (tester) async {
      final photo = Uint8List.fromList(_onePixelPng);
      await pump(tester, {
        'a': CompositionVisuals(
          frontOutline: _mask(),
          sideOutline: _mask(),
          frontPhoto: photo,
          sidePhoto: photo,
        ),
        'b': CompositionVisuals(
          frontOutline: _mask(),
          sideOutline: _mask(),
          frontPhoto: photo,
          sidePhoto: photo,
        ),
      });
      expect(find.byType(OutlineOverlay), findsNWidgets(2));
      expect(find.byType(Image), findsNothing);
      await tester.tap(find.byKey(const ValueKey('show-photos')));
      await tester.pump();
      expect(find.byType(Image), findsNWidgets(4));
    });

    testWidgets(
      'partial history photos stay private and missing views are explicit',
      (tester) async {
        final photo = Uint8List.fromList(_onePixelPng);
        await pump(tester, {
          'a': CompositionVisuals(),
          'b': CompositionVisuals(frontPhoto: photo),
        });

        expect(find.byType(Image), findsNothing);
        expect(find.byKey(const ValueKey('show-photos')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('show-photos')));
        await tester.pump();

        expect(find.byType(Image), findsOneWidget);
        expect(find.text('Original photo unavailable'), findsNWidgets(3));
      },
    );
  });

  group('saved scan screen', () {
    final older = _record('a', DateTime(2026, 9, 1), 22);
    final newer = _record('b', DateTime(2026, 10, 1), 20);

    testWidgets('shows its numbers, outline, and opens the comparison', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final store = _MemoryStore({
        'a': CompositionVisuals(frontOutline: _mask(), sideOutline: _mask()),
      });
      await tester.pumpWidget(
        MaterialApp(
          home: CompositionRecordScreen(
            record: older,
            allRecords: [older, newer],
            visualStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Laid out like the result screen: the ring and the breakdown.
      expect(find.byKey(const ValueKey('body-fat-ring')), findsOneWidget);
      expect(find.byKey(const ValueKey('summary-confidence')), findsOneWidget);
      expect(find.text('22.0%'), findsWidgets);
      expect(find.text('Body composition breakdown'), findsOneWidget);
      expect(find.byKey(const ValueKey('scan-outlines')), findsOneWidget);
      expect(find.byKey(const ValueKey('show-scan-photos')), findsNothing);
      expect(find.text('Original photo unavailable'), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('record-compare')));
      await tester.pumpAndSettle();
      expect(find.byType(CompositionCompareScreen), findsOneWidget);
      // Opened on this scan and the next one.
      expect(find.text('+0.0 pts'), findsNothing);
      expect(find.text('−2.0 pts'), findsOneWidget);
    });
  });

  group('Body analysis tabs', () {
    testWidgets('composition has a current analysis and a history; a scan '
        'opens like its result and can be deleted', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      seedNoProfile();
      final older = _record('a', DateTime(2026, 9, 1), 22);
      final newer = _record('b', DateTime(2026, 10, 1), 20);
      final profiles = ProfileController(ProfileRepository());
      final scans = MeasurementController(MeasurementRepository());
      await tester.runAsync(() async {
        await profiles.save(
          sampleProfile.copyWith(compositionLog: [older, newer]),
        );
        await scans.load();
      });
      await tester.pumpWidget(
        ProfileScope(
          controller: profiles,
          child: MeasurementScope(
            controller: scans,
            child: MaterialApp(
              home: BodyAnalysisScreen(visualStore: _MemoryStore(const {})),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Proportions first; nothing scanned there.
      expect(find.text('No scans yet.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tab-composition')));
      await tester.pumpAndSettle();
      expect(find.text('Current analysis'), findsOneWidget);
      expect(find.text('Scan history'), findsOneWidget);
      // The newest is current, the older one is in the history below it.
      final current = tester.getTopLeft(
        find.byKey(const ValueKey('composition-record-b')),
      );
      final earlier = tester.getTopLeft(
        find.byKey(const ValueKey('composition-record-a')),
      );
      expect(current.dy < earlier.dy, isTrue);

      // Opens laid out like the result screen.
      await tester.tap(find.byKey(const ValueKey('composition-record-b')));
      await tester.pumpAndSettle();
      expect(find.byType(CompositionRecordScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('body-fat-ring')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Delete the current one: the older one becomes current.
      await tester.tap(find.byTooltip('Delete body composition scan').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(profiles.profile!.compositionLog.map((r) => r.id), ['a']);
      expect(
        find.text('No earlier scans. When you scan again, this one moves '
            'here.'),
        findsOneWidget,
      );
    });

    testWidgets('scan history without saved visuals shows unavailable photos', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final record = _record('a', DateTime(2026, 9, 1), 22);
      await tester.pumpWidget(
        MaterialApp(
          home: CompositionRecordScreen(
            record: record,
            allRecords: [record],
            visualStore: _MemoryStore(const {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('body-fat-ring')), findsOneWidget);
      expect(
        find.text('Original scan photos are unavailable for this scan.'),
        findsOneWidget,
      );
      expect(find.text('Original photo unavailable'), findsNWidgets(2));
    });
  });
}

/// A valid 1x1 PNG, so Image.memory has something real to decode.
const List<int> _onePixelPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
