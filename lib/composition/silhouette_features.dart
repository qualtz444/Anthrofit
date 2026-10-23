import 'dart:math' as math;
import 'dart:typed_data';

/// How many heights the body is sampled at, top of head to sole.
const int kSilhouetteLevels = 48;

/// A person-versus-background mask, row-major; any non-zero byte is person.
class SilhouetteMask {
  SilhouetteMask({
    required this.mask,
    required this.width,
    required this.height,
  }) : assert(mask.length == width * height);

  final Uint8List mask;
  final int width;
  final int height;
}

/// Ramanujan's approximation to an ellipse's perimeter, accurate to about
/// 1e-5 for human proportions. Takes the two semi-axes.
double ellipseCircumference(double aSemi, double bSemi) {
  final a = math.max(aSemi, 1e-6);
  final b = math.max(bSemi, 1e-6);
  return math.pi * (3 * (a + b) - math.sqrt((3 * a + b) * (a + 3 * b)));
}

/// Body widths, in centimetres, at each of [kSilhouetteLevels] heights.
class SilhouetteProfile {
  const SilhouetteProfile({required this.central, required this.total});

  /// Width of the run nearest the body's centre line: the torso, not an arm
  /// held away from it.
  final Float64List central;

  /// Width of everything marked as person at that height.
  final Float64List total;
}

/// Ported literally from the bodycomp project's extract_silhouette.py,
/// including numpy's truncation (not rounding) when picking rows and the
/// centre column, because the models were trained on those exact features.
///
/// Returns null when the mask is too small to be a standing person.
SilhouetteProfile? silhouetteProfile(
  Uint8List mask,
  int width,
  int height,
  double heightCm,
) {
  var top = -1;
  var bot = -1;
  for (var y = 0; y < height; y++) {
    final off = y * width;
    var any = false;
    for (var x = 0; x < width; x++) {
      if (mask[off + x] != 0) {
        any = true;
        break;
      }
    }
    if (any) {
      if (top < 0) top = y;
      bot = y;
    }
  }
  if (top < 0 || bot - top + 1 < 20) return null;

  // Columns occupied anywhere between the top and the bottom of the body.
  final colUsed = Uint8List(width);
  var nCols = 0;
  for (var y = top; y <= bot; y++) {
    final off = y * width;
    for (var x = 0; x < width; x++) {
      if (mask[off + x] != 0 && colUsed[x] == 0) {
        colUsed[x] = 1;
        nCols++;
      }
    }
  }
  if (nCols < 5) return null;

  final cols = Int32List(nCols);
  for (var x = 0, i = 0; x < width; x++) {
    if (colUsed[x] != 0) cols[i++] = x;
  }
  // numpy: int(np.median(...)): the mean of the two middle values, truncated.
  final mid = nCols >> 1;
  final double medianCol = nCols.isOdd
      ? cols[mid].toDouble()
      : (cols[mid - 1] + cols[mid]) / 2;
  final centre = medianCol.truncate();

  final pxPerCm = (bot - top + 1) / heightCm;
  final central = Float64List(kSilhouetteLevels);
  final total = Float64List(kSilhouetteLevels);

  for (var i = 0; i < kSilhouetteLevels; i++) {
    // numpy linspace(top, bot, LEVELS).astype(int): truncation, not rounding.
    final yf = top + (bot - top) * i / (kSilhouetteLevels - 1);
    final y = yf.truncate();
    final off = y * width;

    var count = 0;
    for (var x = 0; x < width; x++) {
      if (mask[off + x] != 0) count++;
    }
    total[i] = count / pxPerCm;
    if (count == 0) {
      central[i] = 0;
      continue;
    }

    // Walk the contiguous runs; keep the one nearest the body's centre line.
    var bestScore = double.infinity;
    var bestStart = 0;
    var bestEnd = 0;
    var x = 0;
    while (x < width) {
      if (mask[off + x] == 0) {
        x++;
        continue;
      }
      final start = x;
      while (x < width && mask[off + x] != 0) {
        x++;
      }
      final end = x - 1;
      final int score = (start <= centre && centre <= end)
          ? 0
          : math.min((start - centre).abs(), (end - centre).abs());
      if (score < bestScore) {
        bestScore = score.toDouble();
        bestStart = start;
        bestEnd = end;
      }
    }
    central[i] = (bestEnd - bestStart + 1) / pxPerCm;
  }
  return SilhouetteProfile(central: central, total: total);
}

/// The inputs to Stage 1, named, and in the order the models expect.
class SilhouetteFeatures {
  const SilhouetteFeatures({required this.named, required this.vector});

  final Map<String, double> named;
  final List<double> vector;
}

String _two(int i) => i.toString().padLeft(2, '0');

/// Builds the Stage 1 feature vector from a front and a side silhouette.
/// [featureNames] is the model's own feature list (manifest `s1_features`),
/// so the vector is always in training order. Returns null if either mask is
/// not a usable standing body.
SilhouetteFeatures? silhouetteFeatures(
  SilhouetteMask front,
  SilhouetteMask side, {
  required double heightCm,
  required double weightKg,
  required int sex,
  required List<String> featureNames,
}) {
  final f = silhouetteProfile(front.mask, front.width, front.height, heightCm);
  final s = silhouetteProfile(side.mask, side.width, side.height, heightCm);
  if (f == null || s == null) return null;

  final circ = Float64List(kSilhouetteLevels);
  for (var i = 0; i < kSilhouetteLevels; i++) {
    circ[i] = ellipseCircumference(f.central[i] / 2, s.central[i] / 2);
  }

  final d = <String, double>{};
  for (var i = 0; i < kSilhouetteLevels; i++) {
    d['front_w${_two(i)}'] = f.central[i];
    d['side_w${_two(i)}'] = s.central[i];
    d['circ${_two(i)}'] = circ[i];
  }

  double sum(Iterable<double> a) => a.fold(0.0, (p, c) => p + c);
  double maxOf(Iterable<double> a) => a.reduce(math.max);
  double minOf(Iterable<double> a) => a.reduce(math.min);

  d['front_area'] = sum(f.total);
  d['side_area'] = sum(s.total);
  d['front_max_w'] = maxOf(f.central);
  d['side_max_w'] = maxOf(s.central);

  final lo = (kSilhouetteLevels * 0.25).truncate();
  final hi = (kSilhouetteLevels * 0.60).truncate();
  final band = circ.sublist(lo, hi);
  d['torso_circ_min'] = minOf(band);
  d['torso_circ_max'] = maxOf(band);
  d['torso_circ_mean'] = sum(band) / band.length;

  d['sex'] = sex.toDouble();
  d['height_cm'] = heightCm;
  d['weight_kg'] = weightKg;
  d['bmi'] = weightKg / math.pow(heightCm / 100, 2);

  return SilhouetteFeatures(
    named: d,
    vector: [
      for (final n in featureNames)
        d[n] ?? (throw StateError('model expects an unknown feature: $n')),
    ],
  );
}
