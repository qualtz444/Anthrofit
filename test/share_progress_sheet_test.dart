import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:anthrofit/community/community_models.dart';
import 'package:anthrofit/community/community_service.dart';
import 'package:anthrofit/composition/composition_visuals.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/photos/progress_photo.dart';
import 'package:anthrofit/photos/progress_photo_store.dart';
import 'package:anthrofit/screens/progress/share_progress_sheet.dart';

/// A colour JPEG: red on the left, blue on the right. A stand-in photo.
Uint8List _jpeg() {
  final image = img.Image(width: 60, height: 80);
  for (var y = 0; y < 80; y++) {
    for (var x = 0; x < 60; x++) {
      image.setPixelRgb(x, y, x < 30 ? 240 : 10, 10, x < 30 ? 10 : 240);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
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

class _MemoryStore extends CompositionVisualStore {
  _MemoryStore(this.byId)
    : super(baseDirectory: () async => Directory.systemTemp);

  final Map<String, CompositionVisuals> byId;

  @override
  Future<CompositionVisuals> load(String recordId) async =>
      byId[recordId] ?? CompositionVisuals.none;
}

class _MemoryPhotoStore extends ProgressPhotoStore {
  _MemoryPhotoStore(this.photos, this.byId)
    : super(baseDirectory: () async => Directory.systemTemp);

  final List<ProgressPhoto> photos;
  final Map<String, Uint8List> byId;

  @override
  Future<List<ProgressPhoto>> load() async => photos;

  @override
  Future<Uint8List?> bytes(String id) async => byId[id];
}

class _Community implements CommunityService {
  WorkoutPost? post;
  List<Uint8List> photos = const [];

  @override
  Future<List<String>> friendUids(String uid) async => ['friend-1'];

  @override
  Future<String?> share(
    WorkoutPost post, {
    List<Uint8List> photos = const [],
  }) async {
    this.post = post;
    this.photos = photos;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  const me = CommunityProfile(uid: 'me', handle: 'me', displayName: 'Me');
  final older = _record('old', DateTime(2026, 9, 1), 22);
  final newer = _record('new', DateTime(2026, 10, 1), 20);
  late CommunityService original;
  late _Community community;

  setUp(() {
    original = communityService;
    community = _Community();
    communityService = community;
  });
  tearDown(() => communityService = original);

  Future<void> pump(
    WidgetTester tester,
    Map<String, CompositionVisuals> visuals, {
    ShareTopic initialTopic = ShareTopic.photos,
    List<BodyWeightEntry> weightLog = const [],
    double? currentBodyWeightKg,
    List<CompositionRecord>? scans,
    ProgressPhotoStore? photoStore,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShareProgressSheet(
            me: me,
            scans: scans ?? [older, newer],
            photoStore: photoStore ?? _MemoryPhotoStore(const [], const {}),
            initialTopic: initialTopic,
            weightLog: weightLog,
            currentBodyWeightKg: currentBodyWeightKg,
            visualStore: _MemoryStore(visuals),
            picker: ImagePicker(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('starts with the newest scan photos ticked, with scan info', (
    tester,
  ) async {
    final jpeg = _jpeg();
    await pump(tester, {
      'old': CompositionVisuals(frontPhoto: jpeg),
      'new': CompositionVisuals(frontPhoto: jpeg, sidePhoto: jpeg),
    });

    expect(
      find.byKey(const ValueKey('share-progress-info-scan-new-front')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('share-progress-info-scan-new-side')),
      findsOneWidget,
    );
    expect(
      find.textContaining('body fat 20.0% (17.0–23.0%)'),
      findsNWidgets(2),
    );
    expect(
      find.byKey(const ValueKey('share-progress-info-scan-old-front')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('share-photos')),
        matching: find.byType(Image),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('opens photo selection before community account validation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final jpeg = _jpeg();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showShareProgressSheet(
                context,
                scans: [newer],
                visualStore: _MemoryStore({
                  'new': CompositionVisuals(frontPhoto: jpeg),
                }),
                photoStore: _MemoryPhotoStore(const [], const {}),
                picker: ImagePicker(),
              ),
              child: const Text('Share scan'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Share scan'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Share your progress'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('share-progress-scan-new-front')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('share-progress-confirm')),
    );
    await tester.tap(find.byKey(const ValueKey('share-progress-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to share with friends.'), findsOneWidget);
    expect(find.text('Share your progress'), findsOneWidget);
  });

  testWidgets('shows saved progress photos in the photo preview', (
    tester,
  ) async {
    final jpeg = _jpeg();
    final saved = ProgressPhoto(
      id: 'saved-photo',
      takenAt: DateTime(2026, 10, 5),
      pose: PhotoPose.front,
    );
    await pump(
      tester,
      const {},
      scans: const [],
      photoStore: _MemoryPhotoStore([saved], {saved.id: jpeg}),
    );

    expect(
      find.byKey(const ValueKey('share-progress-progress-saved-photo')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('share-photos')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows selected photo in a non-photo progress preview', (
    tester,
  ) async {
    final jpeg = _jpeg();
    final saved = ProgressPhoto(
      id: 'saved-photo',
      takenAt: DateTime(2026, 10, 5),
      pose: PhotoPose.front,
    );
    await pump(
      tester,
      const {},
      initialTopic: ShareTopic.bodyWeight,
      scans: const [],
      photoStore: _MemoryPhotoStore([saved], {saved.id: jpeg}),
    );

    await tester.tap(
      find.byKey(const ValueKey('share-progress-progress-saved-photo')),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('share-photos')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
  });

  testWidgets('sharing posts the original colour scan photos with scan info', (
    tester,
  ) async {
    final jpeg = _jpeg();
    await pump(tester, {
      'new': CompositionVisuals(frontPhoto: jpeg, sidePhoto: jpeg),
    });

    await tester.tap(find.byKey(const ValueKey('share-progress-confirm')));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 50 && community.post == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });

    final post = community.post!;
    expect(post.share!.topic, ShareTopic.photos);
    expect(post.share!.photos, hasLength(2));
    expect(post.share!.photos.first.bodyFatPct, 20);
    expect(post.share!.photos.first.takenAt, newer.takenAt);
    expect(post.audience, containsAll(['me', 'friend-1']));

    expect(community.photos, hasLength(2));
    final shared = img.decodeImage(community.photos.first)!;
    final left = shared.getPixel(8, 20);
    final right = shared.getPixel(50, 20);
    expect(left.r, greaterThan(left.b));
    expect(right.b, greaterThan(right.r));
  });

  testWidgets('without scan photos it says so and cannot share', (
    tester,
  ) async {
    await pump(tester, const {});

    expect(
      find.byKey(const ValueKey('share-progress-no-scan-photos')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('share-progress-selfie')), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('share-progress-confirm')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('switching the scan result off shares photos without it', (
    tester,
  ) async {
    final jpeg = _jpeg();
    await pump(tester, {
      'new': CompositionVisuals(frontPhoto: jpeg, sidePhoto: jpeg),
    });

    await tester.ensureVisible(
      find.byKey(const ValueKey('share-progress-selfie-scan')),
    );
    await tester.tap(find.byKey(const ValueKey('share-progress-selfie-scan')));
    await tester.pump();
    expect(
      find.textContaining('body fat 20.0%'),
      findsNWidgets(1),
    ); // switch subtitle only

    await tester.tap(find.byKey(const ValueKey('share-progress-confirm')));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 50 && community.post == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });

    final photos = community.post!.share!.photos;
    expect(photos, hasLength(2));
    expect(photos.every((p) => p.bodyFatPct == null), isTrue);
  });

  testWidgets('shares body-weight progress without requiring a photo', (
    tester,
  ) async {
    await pump(
      tester,
      const {},
      initialTopic: ShareTopic.bodyWeight,
      weightLog: [
        BodyWeightEntry(date: DateTime(2026, 9, 1), weightKg: 72),
        BodyWeightEntry(date: DateTime(2026, 10, 1), weightKg: 70.5),
      ],
      currentBodyWeightKg: 70.5,
    );

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('share-progress-topic-bodyWeight')),
          )
          .selected,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('share-progress-confirm')));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 50 && community.post == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });

    expect(community.post!.share!.topic, ShareTopic.bodyWeight);
    expect(community.post!.share!.bodyWeightKg, 70.5);
    expect(
      community.post!.share!.charts.single.kind,
      ShareChartKind.bodyWeight,
    );
    expect(community.photos, isEmpty);
  });
}
