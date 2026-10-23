import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/data/exercise_catalog_repository.dart';
import 'package:anthrofit/data/exercise_library.dart';
import 'package:anthrofit/models/models.dart';

import 'test_helpers.dart';

void main() {
  useExerciseLibrary();

  group('the catalogue asset', () {
    test('it loads, and every exercise is complete', () async {
      await loadExerciseCatalog();
      final all = ExerciseLibrary.builtIn;

      expect(all.length, greaterThan(50));
      expect(all.map((e) => e.id).toSet().length, all.length); // unique ids
      for (final e in all) {
        expect(e.id, isNotEmpty);
        expect(e.name, isNotEmpty, reason: e.id);
        expect(e.primaryMuscles, isNotEmpty, reason: e.id);
        expect(e.equipment, isNotEmpty, reason: e.id);
        expect(e.instructions.length, greaterThanOrEqualTo(3), reason: e.id);
      }
    });

    test('the exercises programs refer to are all still there', () async {
      await loadExerciseCatalog();
      for (final id in [
        'machine_chest_press',
        'lat_pulldown',
        'leg_press',
        'push_up',
        'barbell_bench_press',
        'seated_cable_row',
        'treadmill_run',
      ]) {
        expect(ExerciseLibrary.byId(id), isNotNull, reason: id);
      }
    });

    test('every pattern and every type is represented', () async {
      await loadExerciseCatalog();
      for (final p in MovementPattern.values) {
        expect(
          ExerciseLibrary.filter(movementPattern: p),
          isNotEmpty,
          reason: p.label,
        );
      }
      for (final t in ExerciseType.values) {
        expect(
          ExerciseLibrary.filter(exerciseType: t),
          isNotEmpty,
          reason: t.label,
        );
      }
    });
  });

  group('parsing', () {
    String catalogue(List<Map<String, dynamic>> exercises) =>
        jsonEncode({'schemaVersion': 1, 'exercises': exercises});

    Map<String, dynamic> entry(String id) => {
      'id': id,
      'name': 'Test $id',
      'exerciseType': 'machine',
      'movementPattern': 'isolation',
      'primaryMuscles': ['chest'],
      'secondaryMuscles': <String>[],
      'equipment': ['machine'],
      'experienceLevel': 'beginner',
      'complexity': 'low',
      'instructions': ['Do it.'],
    };

    test('a well-formed catalogue round-trips through the model', () {
      final parsed = parseCatalog(catalogue([entry('a'), entry('b')]));
      expect(parsed.map((e) => e.id).toList(), ['a', 'b']);
      expect(parsed.first.primaryMuscles, [MuscleGroup.chest]);
      expect(parsed.first.exerciseType, ExerciseType.machine);
    });

    test('an exercise survives a round trip through its own JSON', () async {
      await loadExerciseCatalog();
      final original = ExerciseLibrary.byId('lat_pulldown')!;
      final back = Exercise.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(back.id, original.id);
      expect(back.name, original.name);
      expect(back.primaryMuscles, original.primaryMuscles);
      expect(back.secondaryMuscles, original.secondaryMuscles);
      expect(back.equipment, original.equipment);
      expect(back.experienceLevel, original.experienceLevel);
      expect(back.complexity, original.complexity);
      expect(back.instructions, original.instructions);
    });

    test('bad data is refused rather than loaded half-broken', () {
      expect(() => parseCatalog('not json'), throwsA(isA<FormatException>()));
      expect(() => parseCatalog('[]'), throwsA(isA<FormatException>()));
      expect(
        () => parseCatalog(catalogue([])),
        throwsA(isA<FormatException>()),
      );
      // A repeated id would make byId ambiguous.
      expect(
        () => parseCatalog(catalogue([entry('a'), entry('a')])),
        throwsA(isA<FormatException>()),
      );
      // An entry with no id could never be referred to by a program.
      expect(
        () => parseCatalog(
          catalogue([
            {...entry('a'), 'id': ''},
          ]),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('an unknown field or enum value does not break an older build', () {
      final parsed = parseCatalog(
        jsonEncode({
          'schemaVersion': 99,
          'exercises': [
            {...entry('a'), 'somethingNew': true, 'complexity': 'extreme'},
          ],
        }),
      );
      expect(parsed.single.id, 'a');
      expect(parsed.single.complexity, Complexity.low); // fell back
    });
  });
}
