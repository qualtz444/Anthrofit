import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/composition/body_composition.dart';
import 'package:anthrofit/composition/composition_models.dart';
import 'package:anthrofit/composition/mask_codec.dart';
import 'package:anthrofit/composition/profile_input.dart';
import 'package:anthrofit/composition/silhouette_features.dart';
import 'package:anthrofit/composition/tree_model.dart';
import 'package:anthrofit/models/models.dart';

import 'test_helpers.dart';

// The reference implementation (the bodycomp project) is the oracle. Its
// fixtures were produced by LightGBM and by its own silhouette code; these
// tests require the Dart port to reproduce them, because a port that is
// "close" silently ships wrong numbers.

const _models = 'assets/composition';
const _fixtures = 'test/fixtures/composition';

Map<String, dynamic> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

Uint8List _bytes(String file) => File('$_models/$file').readAsBytesSync();

Future<CompositionModels> _load() => CompositionModels.load(
  manifestJson: File('$_models/manifest.json').readAsStringSync(),
  readFile: (file) async => _bytes(file),
);

SilhouetteMask _mask(Map<String, dynamic> m) {
  final w = m['w'] as int;
  final h = m['h'] as int;
  final out = Uint8List(w * h);
  final rows = m['rows'] as List;
  for (var y = 0; y < h; y++) {
    final runs = (rows[y] as List).cast<int>();
    for (var i = 0; i < runs.length; i += 2) {
      out.fillRange(y * w + runs[i], y * w + runs[i] + runs[i + 1], 1);
    }
  }
  return SilhouetteMask(mask: out, width: w, height: h);
}

List<double> _row(Object? r) => [
  for (final v in r as List) v == null ? double.nan : (v as num).toDouble(),
];

void main() {
  group('tree models', () {
    test('every model reproduces the LightGBM predictions', () {
      final manifest = _json('$_models/manifest.json');
      final cases = _json('$_fixtures/parity_cases.json');
      var checked = 0;

      void check(
        String name,
        String file,
        Map<String, dynamic> stage,
        String key,
      ) {
        final model = TreeModel.fromBytes(_bytes(file));
        final rows = stage['rows'] as List;
        final expected = (stage['expected'] as Map)[key] as List;
        expect(rows.length, expected.length, reason: name);
        for (var i = 0; i < rows.length; i++) {
          expect(
            model.predict(_row(rows[i])),
            closeTo((expected[i] as num).toDouble(), 1e-9),
            reason: '$name row $i',
          );
          checked++;
        }
      }

      for (final e in (manifest['stage1'] as Map).entries) {
        check(
          'stage1 ${e.key}',
          e.value as String,
          cases['stage1'] as Map<String, dynamic>,
          e.key as String,
        );
      }
      for (final e in (manifest['stage2'] as Map).entries) {
        final info = e.value as Map;
        for (final part in ['point', 'lo', 'hi']) {
          check(
            'stage2 ${e.key}/$part',
            info[part] as String,
            cases['stage2'] as Map<String, dynamic>,
            '${e.key}_$part',
          );
        }
      }
      // 5 stage-1 models and 6 stage-2 models, 40 rows each.
      expect(checked, 11 * 40);
    });

    test('a truncated or padded file is refused, not half-read', () {
      final good = _bytes('s1_waist.bin');
      expect(
        () => TreeModel.fromBytes(
          Uint8List.sublistView(good, 0, good.length - 1),
        ),
        throwsFormatException,
      );
      expect(
        () => TreeModel.fromBytes(Uint8List.fromList([...good, 0])),
        throwsFormatException,
      );
      expect(() => TreeModel.fromBytes(Uint8List(4)), throwsFormatException);
    });

    test('a missing value follows the direction learned in training', () {
      final model = TreeModel.fromBytes(_bytes('s2_bodyfat_pct_point.bin'));
      final row = _row(
        (_json('$_fixtures/parity_cases.json')['stage2'] as Map)['rows'][0],
      );
      final withGap = [...row]..[5] = double.nan; // waist_cm
      final p = model.predict(withGap);
      expect(p.isFinite, isTrue);
    });
  });

  group('silhouette features', () {
    test(
      'match the reference on bodies with arms apart, shifts and gaps',
      () async {
        final models = await _load();
        final cases =
            (_json('$_fixtures/silhouette_cases.json')['cases'] as List)
                .cast<Map<String, dynamic>>();
        expect(cases, isNotEmpty);
        for (var c = 0; c < cases.length; c++) {
          final kase = cases[c];
          final got = silhouetteFeatures(
            _mask(kase['front'] as Map<String, dynamic>),
            _mask(kase['side'] as Map<String, dynamic>),
            heightCm: (kase['height_cm'] as num).toDouble(),
            weightKg: (kase['weight_kg'] as num).toDouble(),
            sex: kase['sex'] as int,
            featureNames: models.stage1Features,
          )!;
          final expected = (kase['expected'] as Map).cast<String, num>();
          expect(got.named.length, expected.length);
          for (final e in expected.entries) {
            expect(
              got.named[e.key],
              closeTo(e.value.toDouble(), 1e-9),
              reason: 'case $c ${e.key}',
            );
          }
        }
      },
    );

    test('a mask that is not a standing body is rejected', () {
      final empty = SilhouetteMask(
        mask: Uint8List(50 * 100),
        width: 50,
        height: 100,
      );
      expect(silhouetteProfile(empty.mask, 50, 100, 170), isNull);

      // 10 rows tall: shorter than any person could be in frame.
      final short = Uint8List(50 * 100);
      for (var y = 0; y < 10; y++) {
        short.fillRange(y * 50 + 20, y * 50 + 30, 1);
      }
      expect(silhouetteProfile(short, 50, 100, 170), isNull);
    });

    test('ellipse perimeter: a circle is 2πr', () {
      expect(ellipseCircumference(10, 10), closeTo(62.8318530718, 1e-6));
    });
  });

  group('pipeline', () {
    late BodyCompositionPipeline pipeline;
    late Map<String, dynamic> expected;
    late CompositionInput input;
    late SilhouetteMask front;
    late SilhouetteMask side;

    setUpAll(() async {
      pipeline = BodyCompositionPipeline(await _load());
      expected = _json('$_fixtures/sample_expected.json');
      final masks = _json('$_fixtures/sample_masks.json');
      front = _mask(masks['front'] as Map<String, dynamic>);
      side = _mask(masks['side'] as Map<String, dynamic>);
      input = CompositionInput(
        heightCm: (expected['height_cm'] as num).toDouble(),
        weightKg: (expected['weight_kg'] as num).toDouble(),
        age: expected['age'] as int,
        isMale: expected['sex'] == 1,
      );
    });

    test('a real body reproduces the reference result', () {
      final got = pipeline.analyse(front, side, input);
      final m = expected['measurements'] as Map<String, dynamic>;
      expect(
        got.measurements.waist,
        closeTo((m['waist'] as num).toDouble(), 0.05),
      );
      expect(
        got.measurements.bicep,
        closeTo((m['bicep'] as num).toDouble(), 0.05),
      );
      expect(got.measurements.hip, closeTo((m['hip'] as num).toDouble(), 0.05));
      expect(
        got.measurements.chest,
        closeTo((m['chest'] as num).toDouble(), 0.05),
      );
      expect(
        got.measurements.thigh,
        closeTo((m['thigh'] as num).toDouble(), 0.05),
      );

      final c = expected['composition'] as Map<String, dynamic>;
      void same(CompositionEstimate e, Map<String, dynamic> x) {
        expect(e.value, closeTo((x['estimate'] as num).toDouble(), 0.05));
        expect(e.low, closeTo((x['low'] as num).toDouble(), 0.05));
        expect(e.high, closeTo((x['high'] as num).toDouble(), 0.05));
      }

      same(got.bodyFatPct, c['bodyfat_pct'] as Map<String, dynamic>);
      same(got.appendicularLeanKg, c['alm_kg'] as Map<String, dynamic>);
    });

    test('the interval brackets the estimate and the masses add up', () {
      final got = pipeline.analyse(front, side, input);
      expect(got.bodyFatPct.low, lessThanOrEqualTo(got.bodyFatPct.value));
      expect(got.bodyFatPct.high, greaterThanOrEqualTo(got.bodyFatPct.value));
      expect(got.fatMassKg + got.fatFreeMassKg, closeTo(input.weightKg, 0.11));
      expect(got.frameCount, 1);
    });

    test('several frames are combined by the median', () {
      Uint8List erode(SilhouetteMask m) {
        final out = Uint8List(m.width * m.height);
        for (var y = 1; y < m.height - 1; y++) {
          for (var x = 1; x < m.width - 1; x++) {
            final i = y * m.width + x;
            if (m.mask[i] != 0 &&
                m.mask[i - 1] != 0 &&
                m.mask[i + 1] != 0 &&
                m.mask[i - m.width] != 0 &&
                m.mask[i + m.width] != 0) {
              out[i] = 1;
            }
          }
        }
        return out;
      }

      SilhouetteMask eroded(SilhouetteMask m) =>
          SilhouetteMask(mask: erode(m), width: m.width, height: m.height);

      final f1 = eroded(front);
      final s1 = eroded(side);
      final f2 = eroded(f1);
      final s2 = eroded(s1);

      final waists = [
        pipeline.analyse(front, side, input).measurements.waist,
        pipeline.analyse(f1, s1, input).measurements.waist,
        pipeline.analyse(f2, s2, input).measurements.waist,
      ]..sort();

      final many = pipeline.analyseMany([
        (front: front, side: side),
        (front: f1, side: s1),
        (front: f2, side: s2),
      ], input);
      expect(many.frameCount, 3);
      expect(many.measurements.waist, closeTo(waists[1], 0.1));
      expect(many.waistSpreadCm, closeTo(waists[2] - waists[0], 0.11));
    });

    test('a frame that cannot be read is skipped, not fatal', () {
      final blank = SilhouetteMask(
        mask: Uint8List(front.width * front.height),
        width: front.width,
        height: front.height,
      );
      final got = pipeline.analyseMany([
        (front: blank, side: blank),
        (front: front, side: side),
      ], input);
      expect(got.frameCount, 1);
    });

    test('no readable frame at all is an error the screen can show', () {
      final blank = SilhouetteMask(
        mask: Uint8List(100 * 200),
        width: 100,
        height: 200,
      );
      expect(
        () => pipeline.analyse(blank, blank, input),
        throwsA(isA<CompositionException>()),
      );
    });

    test('unusable inputs are refused before any model runs', () {
      CompositionInput withInput({double h = 170, double w = 65, int a = 30}) =>
          CompositionInput(heightCm: h, weightKg: w, age: a, isMale: true);
      expect(withInput(h: 80).problem, isNotNull);
      expect(withInput(w: 10).problem, isNotNull);
      expect(withInput(a: 15).problem, isNotNull);
      expect(withInput().problem, isNull);
      expect(
        () => pipeline.analyse(front, side, withInput(a: 15)),
        throwsA(isA<CompositionException>()),
      );
    });

    test('ages beyond the training range are flagged', () {
      const older = CompositionInput(
        heightCm: 170,
        weightKg: 70,
        age: 65,
        isMale: false,
      );
      expect(older.problem, isNull);
      expect(older.isInTrainingRange, isFalse);
      expect(older.sexCode, 0);
    });
  });

  group('mask codec (the Kotlin capture contract)', () {
    test('decodes what MaskOps.encodeRuns produces', () {
      // The same literal the Kotlin test pins: "##.#." over an empty row.
      final m = decodeRunMask([5, 2, 2, 0, 2, 3, 1, 0])!;
      expect(m.width, 5);
      expect(m.height, 2);
      expect(m.mask.toList(), [1, 1, 0, 1, 0, 0, 0, 0, 0, 0]);
    });

    test('damaged or padded data is dropped, not half-read', () {
      expect(decodeRunMask([5, 2, 2, 0, 2, 3, 1]), isNull); // truncated
      expect(decodeRunMask([5, 2, 2, 0, 2, 3, 1, 0, 0]), isNull); // padded
      expect(decodeRunMask([5, 2, 1, 4, 3, 0]), isNull); // run past the edge
      expect(decodeRunMask([5]), isNull);
      expect(decodeRunMask([0, 2, 0, 0]), isNull);
    });

    test('a decoded mask goes straight into the pipeline', () async {
      final masks = _json('$_fixtures/sample_masks.json');
      List<int> encode(Map<String, dynamic> m) {
        final out = <int>[m['w'] as int, m['h'] as int];
        for (final row in m['rows'] as List) {
          final runs = (row as List).cast<int>();
          out
            ..add(runs.length ~/ 2)
            ..addAll(runs);
        }
        return out;
      }

      final front = decodeRunMask(
        encode(masks['front'] as Map<String, dynamic>),
      )!;
      final direct = _mask(masks['front'] as Map<String, dynamic>);
      expect(front.mask, direct.mask);
    });
  });

  group('profile input', () {
    test('uses the date of birth for age and the profile sex', () {
      final p = sampleProfile.copyWith(
        sex: Sex.female,
        dateOfBirth: DateTime(DateTime.now().year - 30, 1, 1),
      );
      final input = compositionInputFrom(p)!;
      expect(input.isMale, isFalse);
      expect(input.age, 30);
      expect(input.heightCm, p.heightCm);
      expect(input.weightKg, p.weightKg);
    });

    test('"prefer not to say" gets no estimate rather than a guess', () {
      expect(compositionInputFrom(sampleProfile), isNull);
    });
  });
}
