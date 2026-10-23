import 'dart:convert';

import 'package:flutter/services.dart';

import 'tree_model.dart';

/// Where the bundled models live (declared in pubspec.yaml).
const String kCompositionAssetDir = 'assets/composition';

/// One Stage 2 target: a point model and the two interval models, plus the
/// conformal width added to each side and the model's own measured accuracy.
class CompositionTarget {
  const CompositionTarget({
    required this.point,
    required this.lo,
    required this.hi,
    required this.q,
    required this.mae,
    required this.coverage80,
  });

  final TreeModel point;
  final TreeModel lo;
  final TreeModel hi;

  /// Conformal correction: the interval is [lo - q, hi + q].
  final double q;

  /// Mean absolute error on the held-out DXA test set, in the target's unit.
  final double mae;

  /// Share of held-out people inside the 80% interval, in percent.
  final double coverage80;
}

/// Every model the pipeline needs, loaded once and reused.
class CompositionModels {
  const CompositionModels({
    required this.stage1,
    required this.stage2,
    required this.stage1Features,
    required this.stage2Features,
  });

  /// Circumference models by name: waist, bicep, hip, chest, thigh.
  final Map<String, TreeModel> stage1;

  /// Body-composition targets by name: bodyfat_pct, alm_kg.
  final Map<String, CompositionTarget> stage2;

  final List<String> stage1Features;
  final List<String> stage2Features;

  /// Builds the models from the manifest text and a file loader. The loader
  /// gets each file name in the manifest and returns its bytes, so the same
  /// code serves the app (assets) and tests (plain files).
  static Future<CompositionModels> load({
    required String manifestJson,
    required Future<Uint8List> Function(String file) readFile,
  }) async {
    final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;
    final stage1Files = (manifest['stage1'] as Map).cast<String, String>();
    final stage2Info = (manifest['stage2'] as Map).cast<String, dynamic>();

    Future<TreeModel> model(String file) async =>
        TreeModel.fromBytes(await readFile(file));

    final stage1 = <String, TreeModel>{};
    for (final e in stage1Files.entries) {
      stage1[e.key] = await model(e.value);
    }

    final stage2 = <String, CompositionTarget>{};
    for (final e in stage2Info.entries) {
      final info = (e.value as Map).cast<String, dynamic>();
      stage2[e.key] = CompositionTarget(
        point: await model(info['point'] as String),
        lo: await model(info['lo'] as String),
        hi: await model(info['hi'] as String),
        q: (info['q'] as num).toDouble(),
        mae: (info['mae'] as num).toDouble(),
        coverage80: (info['coverage80'] as num).toDouble(),
      );
    }

    return CompositionModels(
      stage1: stage1,
      stage2: stage2,
      stage1Features: (manifest['s1_features'] as List).cast<String>(),
      stage2Features: (manifest['s2_features'] as List).cast<String>(),
    );
  }

  /// Loads the models bundled with the app.
  static Future<CompositionModels> loadFromAssets([AssetBundle? bundle]) {
    final b = bundle ?? rootBundle;
    return () async {
      final manifest = await b.loadString(
        '$kCompositionAssetDir/manifest.json',
      );
      return load(
        manifestJson: manifest,
        readFile: (file) async {
          final data = await b.load('$kCompositionAssetDir/$file');
          return data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
        },
      );
    }();
  }
}
