import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/community/community_models.dart';
import 'package:anthrofit/community/share_builder.dart';
import 'package:anthrofit/data/training_stats.dart';
import 'package:anthrofit/models/models.dart';

CompositionRecord _scan(DateTime when, double bf) => CompositionRecord(
  id: 's',
  takenAt: when,
  weightKg: 70,
  bodyFatPct: bf,
  bodyFatLow: bf - 3,
  bodyFatHigh: bf + 3,
  leanLimbKg: 24,
  fatFreeMassKg: 56,
  fatMassKg: 14,
  waistCm: 80,
  chestCm: 95,
  hipCm: 95,
  thighCm: 55,
  upperArmCm: 30,
  frameCount: 3,
);

void main() {
  final infos = [
    SharedPhotoInfo(
      takenAt: DateTime(2026, 10, 1),
      pose: 'front',
      bodyFatPct: 20,
      bodyFatLow: 17,
      bodyFatHigh: 23,
      fatFreeMassKg: 56,
    ),
    SharedPhotoInfo(takenAt: DateTime(2026, 10, 2), pose: 'other'),
    SharedPhotoInfo(takenAt: DateTime(2026, 10, 3), pose: 'side'),
  ];

  test('a body post can carry attached photos, at most the limit', () {
    final share = buildShare(
      topic: ShareTopic.body,
      items: {ShareItem.bodyFat},
      range: ProgressRange.allTime,
      sessions: const [],
      scans: [_scan(DateTime(2026, 10, 1), 20)],
      photoInfos: infos,
      today: DateTime(2026, 10, 5),
    );
    expect(share.bodyFatPct, 20);
    expect(share.photos, hasLength(ProgressShare.maxPhotos));
    expect(share.photos.first.bodyFatPct, 20);
    expect(share.isEmpty, isFalse);
  });

  test('photos alone make an overall post worth sharing', () {
    final share = buildShare(
      topic: ShareTopic.overall,
      items: const {},
      range: ProgressRange.allTime,
      sessions: const [],
      photoInfos: infos.take(1).toList(),
    );
    expect(share.photos, hasLength(1));
    expect(share.isEmpty, isFalse);
  });

  test('no photos attached leaves other topics unchanged', () {
    final share = buildShare(
      topic: ShareTopic.overall,
      items: const {},
      range: ProgressRange.allTime,
      sessions: const [],
    );
    expect(share.photos, isEmpty);
    expect(share.isEmpty, isTrue);
  });

  test('attached photos survive the post JSON round trip', () {
    final share = buildShare(
      topic: ShareTopic.exercise,
      items: const {},
      range: ProgressRange.allTime,
      sessions: const [],
      photoInfos: infos.take(2).toList(),
    );
    final back = ProgressShare.fromJson(share.toJson());
    expect(back.photos, hasLength(2));
    expect(back.photos.first.bodyFatPct, 20);
    expect(back.photos.last.pose, 'other');
  });
}
