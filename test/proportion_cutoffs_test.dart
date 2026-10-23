import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/recommendation/proportion_rules.dart';

ProportionClass _classify(String key, double value) =>
    ProportionThresholds.participants.classify(
      key,
      Measurement.fromNative({
        'ratios': {key: value},
      }),
    );

void main() {
  group('participant cut-offs', () {
    test('femur : torso splits at the median 0.720', () {
      expect(_classify(RatioKeys.femurToTorso, 0.70), ProportionClass.low);
      expect(_classify(RatioKeys.femurToTorso, 0.720), ProportionClass.low);
      expect(_classify(RatioKeys.femurToTorso, 0.75), ProportionClass.high);
    });

    test('arm : torso splits at the median 0.963', () {
      expect(_classify(RatioKeys.armToTorso, 0.95), ProportionClass.low);
      expect(_classify(RatioKeys.armToTorso, 0.97), ProportionClass.high);
    });

    test('upper body : stature uses Q1 0.481 and Q3 0.524', () {
      const key = RatioKeys.upperBodyToStature;
      expect(_classify(key, 0.481), ProportionClass.low);
      expect(_classify(key, 0.50), ProportionClass.typical);
      expect(_classify(key, 0.524), ProportionClass.high);
    });

    test('shoulder : hip uses Q1 1.610 and Q3 1.714', () {
      const key = RatioKeys.shoulderToHip;
      expect(_classify(key, 1.60), ProportionClass.low);
      expect(_classify(key, 1.65), ProportionClass.typical);
      expect(_classify(key, 1.72), ProportionClass.high);
    });

    test('a ratio the scan did not measure stays unknown', () {
      expect(
        ProportionThresholds.participants.classify(
          RatioKeys.femurToTorso,
          Measurement.fromNative(const {'ratios': <String, double>{}}),
        ),
        ProportionClass.unknown,
      );
    });
  });
}
