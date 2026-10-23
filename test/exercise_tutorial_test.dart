import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/coaching/exercise_tutorial.dart';
import 'package:anthrofit/data/exercise_library.dart';
import 'package:anthrofit/models/models.dart';

import 'test_helpers.dart';

void main() {
  useExerciseLibrary();

  test('a main lift for strength gets the 2–3 min rest reason', () {
    final text = prescriptionRationale(
      TrainingGoal.getStronger,
      ExerciseLibrary.byId('barbell_bench_press')!,
    );
    expect(text, contains('strength model'));
    expect(text, contains('2–3 min'));
    expect(text, contains("app's choice"));
  });

  test('muscle-building goals use the hypertrophy model', () {
    final text = prescriptionRationale(
      TrainingGoal.loseFat,
      ExerciseLibrary.byId('machine_chest_press')!,
    );
    expect(text, contains('muscle-building model'));
  });

  test('the saved note carries the reason and the setup tip', () {
    expect(recommendationNote('Recommended because it trains Chest.', null),
        'Recommended because it trains Chest.');
    expect(
      recommendationNote('Why.', 'Take a wider stance.'),
      'Why.\nSetup tip: Take a wider stance.',
    );
  });
}
