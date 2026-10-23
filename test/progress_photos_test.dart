import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anthrofit/community/community_models.dart';
import 'package:anthrofit/community/share_builder.dart';
import 'package:anthrofit/data/storage_scope.dart';
import 'package:anthrofit/data/training_stats.dart';
import 'package:anthrofit/photos/progress_photo.dart';
import 'package:anthrofit/photos/progress_photo_store.dart';

/// A colour JPEG of the given size: a stand-in, not a real photo.
Uint8List _jpeg(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(
        x,
        y,
        x < width ~/ 2 ? 240 : 10,
        10,
        x < width ~/ 2 ? 10 : 240,
      );
    }
  }
  return img.encodeJpg(image, quality: 90);
}

void main() {
  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('photos_test');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ProgressPhotoStore store([StorageScope scope = StorageScope.guest]) =>
      ProgressPhotoStore(scope: scope, baseDirectory: () async => dir);

  group('progress photo records', () {
    test('a photo survives saving and reading back', () {
      final photo = ProgressPhoto(
        id: 'p1',
        takenAt: DateTime(2026, 10, 1, 8),
        pose: PhotoPose.side,
        note: 'Week 4',
      );
      final back = ProgressPhoto.fromJson(photo.toJson())!;
      expect(back.id, 'p1');
      expect(back.takenAt, DateTime(2026, 10, 1, 8));
      expect(back.pose, PhotoPose.side);
      expect(back.note, 'Week 4');
      expect(ProgressPhoto.fromJson({'id': ''}), isNull);
    });

    test('add, list newest first, read, edit and delete', () async {
      final s = store();
      final older = await s.add(
        _jpeg(30, 40),
        pose: PhotoPose.front,
        takenAt: DateTime(2026, 9, 1),
      );
      final newer = await s.add(
        _jpeg(30, 40),
        pose: PhotoPose.back,
        takenAt: DateTime(2026, 10, 1),
        note: '  after  ',
      );

      var all = await s.load();
      expect(all.map((p) => p.id), [newer.id, older.id]);
      expect(all.first.note, 'after');
      expect(await s.bytes(older.id), isNotNull);

      await s.update(older.copyWith(pose: PhotoPose.side));
      all = await s.load();
      expect(all.last.pose, PhotoPose.side);

      await s.delete(older.id);
      all = await s.load();
      expect(all.map((p) => p.id), [newer.id]);
      expect(await s.bytes(older.id), isNull, reason: 'the file is gone');
    });

    test('each owner has their own photos', () async {
      await store().add(_jpeg(10, 10), pose: PhotoPose.front);
      expect(await store(StorageScope.user('abc')).load(), isEmpty);
    });

    test('a photo for sharing is upright, at most 720 px and small', () async {
      final small = await shrinkForSharing(_jpeg(1440, 1080));
      expect(small, isNotNull);
      expect(small!.length, lessThanOrEqualTo(kSharedPhotoMaxBytes));
      final decoded = img.decodeImage(small)!;
      expect(decoded.width, kSharedPhotoMaxSide);
      expect(decoded.height, 540);
      expect(
        decoded.getPixel(150, 250).r,
        greaterThan(decoded.getPixel(150, 250).b),
      );
      expect(
        decoded.getPixel(570, 250).b,
        greaterThan(decoded.getPixel(570, 250).r),
      );
    });
  });

  group('sharing photos', () {
    final a = ProgressPhoto(
      id: 'a',
      takenAt: DateTime(2026, 10, 1),
      pose: PhotoPose.front,
    );
    final b = ProgressPhoto(
      id: 'b',
      takenAt: DateTime(2026, 8, 1),
      pose: PhotoPose.front,
    );
    final c = ProgressPhoto(
      id: 'c',
      takenAt: DateTime(2026, 9, 1),
      pose: PhotoPose.side,
    );

    test('the post lists the picked photos oldest first, two at most', () {
      final share = buildShare(
        topic: ShareTopic.photos,
        items: const {},
        range: ProgressRange.allTime,
        sessions: const [],
        photos: [a, b, c],
      );
      expect(share.photos.map((p) => p.takenAt), [
        DateTime(2026, 8, 1),
        DateTime(2026, 9, 1),
      ]);
      expect(share.isEmpty, isFalse);
    });

    test('with no photos picked there is nothing to share', () {
      final share = buildShare(
        topic: ShareTopic.photos,
        items: const {},
        range: ProgressRange.allTime,
        sessions: const [],
      );
      expect(share.isEmpty, isTrue);
    });

    test('photo details survive saving and reading back', () {
      final share = ProgressShare(
        topic: ShareTopic.photos,
        title: 'Progress photos',
        photos: [
          SharedPhotoInfo(
            takenAt: DateTime(2026, 8, 1),
            pose: 'front',
            bodyFatPct: 21.5,
            bodyFatLow: 19,
            bodyFatHigh: 24,
            fatFreeMassKg: 55.2,
          ),
        ],
      );
      final back = ProgressShare.fromJson(share.toJson());
      expect(back.topic, ShareTopic.photos);
      expect(back.photos.single.pose, 'front');
      expect(back.photos.single.takenAt, DateTime(2026, 8, 1));
      expect(back.photos.single.bodyFatPct, 21.5);
      expect(back.photos.single.bodyFatLow, 19);
      expect(back.photos.single.bodyFatHigh, 24);
      expect(back.photos.single.fatFreeMassKg, 55.2);
    });

    test('scan photo metadata is included in the share', () {
      final photo = SharedPhotoInfo(
        takenAt: DateTime(2026, 8, 1),
        pose: 'side',
        bodyFatPct: 21.5,
        fatFreeMassKg: 55.2,
      );
      final share = buildShare(
        topic: ShareTopic.photos,
        items: const {},
        range: ProgressRange.allTime,
        sessions: const [],
        photoInfos: [photo],
      );

      expect(share.photos.single.pose, 'side');
      expect(share.photos.single.takenAt, DateTime(2026, 8, 1));
      expect(share.photos.single.bodyFatPct, 21.5);
      expect(share.photos.single.fatFreeMassKg, 55.2);
    });
  });
}
