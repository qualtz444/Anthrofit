import 'dart:typed_data';

/// A gradient-boosted tree ensemble, read from the compact binary the
/// bodycomp project exports (MIT, see assets/composition/LICENSE-bodycomp.txt).
///
/// Layout, little-endian:
///   int32 numTrees, int32 numInternal, int32 numLeaves
///   int32   roots[numTrees]
///   int16   feature[numInternal]
///   float64 threshold[numInternal]
///   int32   left[numInternal]
///   int32   right[numInternal]
///   uint8   defaultLeft[numInternal]
///   float64 leafValue[numLeaves]
///
/// A child index >= 0 is another internal node; a negative one is leaf
/// `-index - 1`.
class TreeModel {
  TreeModel._({
    required this.numTrees,
    required this.roots,
    required this.feature,
    required this.threshold,
    required this.left,
    required this.right,
    required this.defaultLeft,
    required this.leafValue,
  });

  final int numTrees;
  final Int32List roots;
  final Int16List feature;
  final Float64List threshold;
  final Int32List left;
  final Int32List right;
  final Uint8List defaultLeft;
  final Float64List leafValue;

  /// Reads a packed model. Throws [FormatException] when the bytes are not a
  /// whole model, rather than predicting from a truncated one.
  factory TreeModel.fromBytes(Uint8List bytes) {
    if (bytes.lengthInBytes < 12) {
      throw const FormatException('model file is too short');
    }
    // Read through a ByteData: the float64 sections are not guaranteed to be
    // 8-byte aligned in the packed file, and an unaligned typed-array view
    // would throw.
    final data = ByteData.sublistView(bytes);
    final numTrees = data.getInt32(0, Endian.little);
    final numInternal = data.getInt32(4, Endian.little);
    final numLeaves = data.getInt32(8, Endian.little);
    if (numTrees < 0 || numInternal < 0 || numLeaves < 0) {
      throw const FormatException('model header is corrupt');
    }

    final expected =
        12 + numTrees * 4 + numInternal * (2 + 8 + 4 + 4 + 1) + numLeaves * 8;
    if (expected != bytes.lengthInBytes) {
      throw FormatException(
        'model size mismatch: expected $expected bytes, got '
        '${bytes.lengthInBytes}',
      );
    }

    var o = 12;
    Int32List ints(int n) {
      final a = Int32List(n);
      for (var i = 0; i < n; i++, o += 4) {
        a[i] = data.getInt32(o, Endian.little);
      }
      return a;
    }

    Float64List doubles(int n) {
      final a = Float64List(n);
      for (var i = 0; i < n; i++, o += 8) {
        a[i] = data.getFloat64(o, Endian.little);
      }
      return a;
    }

    final roots = ints(numTrees);
    final feature = Int16List(numInternal);
    for (var i = 0; i < numInternal; i++, o += 2) {
      feature[i] = data.getInt16(o, Endian.little);
    }
    final threshold = doubles(numInternal);
    final left = ints(numInternal);
    final right = ints(numInternal);
    final defaultLeft = Uint8List(numInternal);
    for (var i = 0; i < numInternal; i++, o++) {
      defaultLeft[i] = data.getUint8(o);
    }
    final leafValue = doubles(numLeaves);

    return TreeModel._(
      numTrees: numTrees,
      roots: roots,
      feature: feature,
      threshold: threshold,
      left: left,
      right: right,
      defaultLeft: defaultLeft,
      leafValue: leafValue,
    );
  }

  /// The ensemble's prediction for [x], indexed the way the model was trained.
  /// A NaN follows the direction learned in training, as LightGBM does.
  double predict(List<double> x) {
    var sum = 0.0;
    for (var t = 0; t < numTrees; t++) {
      var node = roots[t];
      while (node >= 0) {
        final v = x[feature[node]];
        final goLeft = v.isNaN ? defaultLeft[node] == 1 : v <= threshold[node];
        node = goLeft ? left[node] : right[node];
      }
      sum += leafValue[-node - 1];
    }
    return sum;
  }
}
