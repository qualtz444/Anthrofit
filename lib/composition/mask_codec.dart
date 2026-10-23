import 'dart:typed_data';

import 'silhouette_features.dart';

/// Decodes a silhouette sent from the Android capture.
///
/// Layout, matching MaskOps.encodeRuns in Kotlin:
///   [width, height, then for each row: runCount, (start, length) × runCount]
///
/// Returns null when the data is not exactly one whole mask, so a damaged
/// message is dropped rather than half-read.
SilhouetteMask? decodeRunMask(List<int> data) {
  if (data.length < 2) return null;
  final width = data[0];
  final height = data[1];
  if (width <= 0 || height <= 0) return null;

  final mask = Uint8List(width * height);
  var i = 2;
  for (var y = 0; y < height; y++) {
    if (i >= data.length) return null;
    final count = data[i++];
    if (count < 0) return null;
    for (var r = 0; r < count; r++) {
      if (i + 1 >= data.length) return null;
      final start = data[i++];
      final length = data[i++];
      if (start < 0 || length < 0 || start + length > width) return null;
      mask.fillRange(y * width + start, y * width + start + length, 1);
    }
  }
  if (i != data.length) return null;
  return SilhouetteMask(mask: mask, width: width, height: height);
}

/// Encodes [mask] in the same layout [decodeRunMask] reads, so an outline can
/// be stored compactly and drawn again later.
List<int> encodeRunMask(SilhouetteMask mask) {
  final out = <int>[mask.width, mask.height];
  for (var y = 0; y < mask.height; y++) {
    final row = y * mask.width;
    final runs = <int>[];
    var x = 0;
    while (x < mask.width) {
      if (mask.mask[row + x] == 0) {
        x++;
        continue;
      }
      final start = x;
      while (x < mask.width && mask.mask[row + x] != 0) {
        x++;
      }
      runs
        ..add(start)
        ..add(x - start);
    }
    out
      ..add(runs.length ~/ 2)
      ..addAll(runs);
  }
  return out;
}
