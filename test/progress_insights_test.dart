import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/progress/muscle_exposure.dart';
import 'package:anthrofit/progress/progress_insights.dart';

CompositionRecord _scan(String id, DateTime when, double bf, double half) =>
    CompositionRecord(
      id: id,
      takenAt: when,
      weightKg: 70,
      bodyFatPct: bf,
      bodyFatLow: bf - half,
      bodyFatHigh: bf + half,
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

void main() {
  group('composition insight', () {
    test('one scan says nothing', () {
      expect(compositionInsight([_scan('a', DateTime(2026, 9, 1), 22, 3)]),
          isNull);
    });

    test('overlapping ranges: not a confirmed change', () {
      final text = compositionInsight([
        _scan('b', DateTime(2026, 10, 1), 20, 3),
        _scan('a', DateTime(2026, 9, 1), 22, 3),
      ])!;
      expect(text, contains('22.0% to 20.0%'));
      expect(text, contains('−2.0 pts'));
      expect(text, contains('over 30 days'));
      expect(text, contains('may not be a real change'));
    });

    test('separate ranges: still called an estimate', () {
      final text = compositionInsight([
        _scan('a', DateTime(2026, 9, 1), 25, 1),
        _scan('b', DateTime(2026, 10, 1), 20, 1),
      ])!;
      expect(text, contains('do not overlap'));
      expect(text, contains('camera estimate'));
    });
  });

  test('no program or no workouts: no gap insight', () {
    const empty = MuscleDistribution(
      workouts: 0,
      involved: [],
      notRecorded: [],
    );
    expect(programGapInsight(null, empty), isNull);
  });
}
