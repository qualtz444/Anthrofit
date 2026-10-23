import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:anthrofit/photos/progress_photo_store.dart';

Uint8List _jpeg(int w, int h) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgb(x, y, x < w ~/ 2 ? 240 : 10, 10, x < w ~/ 2 ? 10 : 240);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

void main() {
  test('shrinks every photo, in order, keeping colour', () async {
    final prep = SharePhotoPrep();
    final big = _jpeg(1440, 1080);
    final small = _jpeg(60, 80);
    final out = await prep.collect([
      (id: 'a', jpeg: big),
      (id: 'b', jpeg: small),
    ]);

    expect(out, isNotNull);
    expect(out, hasLength(2));
    final first = img.decodeImage(out![0])!;
    expect(first.width, kSharedPhotoMaxSide);
    final left = first.getPixel(10, 10);
    final right = first.getPixel(first.width - 10, 10);
    expect(left.r, greaterThan(left.b));
    expect(right.b, greaterThan(right.r));
    expect(img.decodeImage(out[1])!.width, 60);
  });

  test('a photo prepared earlier is reused, not shrunk again', () async {
    final prep = SharePhotoPrep();
    final jpeg = _jpeg(1440, 1080);
    prep.prepare('a', jpeg);
    final first = await prep.collect([(id: 'a', jpeg: jpeg)]);
    final second = await prep.collect([(id: 'a', jpeg: jpeg)]);
    expect(identical(first![0], second![0]), isTrue);
  });

  test('a photo that cannot be read gives null and is tried again', () async {
    final prep = SharePhotoPrep();
    final junk = Uint8List.fromList([1, 2, 3]);
    expect(await prep.collect([(id: 'x', jpeg: junk)]), isNull);
    // Forgotten after the failure, so a good photo under the same id works.
    final good = _jpeg(60, 80);
    expect(await prep.collect([(id: 'x', jpeg: good)]), isNotNull);
  });
}
