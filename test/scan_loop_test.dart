import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/screens/scan/scan_change_card.dart';

// Test fixtures only, not reference values.
CompositionRecord _record(String id, DateTime takenAt, double bodyFat) =>
    CompositionRecord(
      id: id,
      takenAt: takenAt,
      weightKg: 70,
      bodyFatPct: bodyFat,
      bodyFatLow: bodyFat - 3,
      bodyFatHigh: bodyFat + 3,
      leanLimbKg: 22,
      fatFreeMassKg: 55,
      fatMassKg: 15,
      waistCm: 80,
      chestCm: 95,
      hipCm: 94,
      thighCm: 54,
      upperArmCm: 29,
      frameCount: 3,
    );

void main() {
  final first = _record('a', DateTime(2026, 8, 1), 22);
  final second = _record('b', DateTime(2026, 9, 1), 21);
  final third = _record('c', DateTime(2026, 10, 1), 20);

  test('a new scan is compared with the latest one before it', () {
    final pair = ScanChangeCard.pairFor([third, first, second], 'c')!;
    expect(pair.current.id, 'c');
    expect(pair.previous!.id, 'b');
  });

  test('an older scan is compared with the one before it, not a later one',
      () {
    final pair = ScanChangeCard.pairFor([first, second, third], 'b')!;
    expect(pair.previous!.id, 'a');
  });

  test('the first scan has nothing before it', () {
    final pair = ScanChangeCard.pairFor([first, second], 'a')!;
    expect(pair.previous, isNull);
  });

  test('an unsaved scan shows nothing', () {
    expect(ScanChangeCard.pairFor([first], 'missing'), isNull);
  });
}
