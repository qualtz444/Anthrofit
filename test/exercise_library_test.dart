import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/data/exercise_library.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/screens/exercises/exercise_library_screen.dart';
import 'package:anthrofit/screens/widgets/muscle_image.dart';

import 'test_helpers.dart';

const _requiredNames = [
  'Bodyweight Squat',
  'Leg Press',
  'Barbell Back Squat',
  'Goblet Squat',
  'Leg Extension',
  'Romanian Deadlift',
  'Barbell Hip Thrust',
  'Cable Pull-Through',
  'Dumbbell Romanian Deadlift',
  'Seated Leg Curl',
  'Push-Up',
  'Machine Chest Press',
  'Barbell Bench Press',
  'Dumbbell Bench Press',
  'Cable Chest Press',
  'Machine Shoulder Press',
  'Dumbbell Shoulder Press',
  'Barbell Overhead Press',
  'Cable Shoulder Press',
  'Pike Push-Up',
  'Seated Cable Row',
  'Machine Row',
  'Chest-Supported Dumbbell Row',
  'Barbell Row',
  'Inverted Row',
  'Lat Pulldown',
  'Assisted Pull-Up',
  'Pull-Up',
  'Chin-Up',
  'Single-Arm Cable Pulldown',
];

List<String> _names(List<Exercise> list) => list.map((e) => e.name).toList();

void main() {
  // The exercise catalogue is an asset now, so it has to be loaded.
  useExerciseLibrary();

  group('ExerciseLibrary data', () {
    test('ids are unique', () {
      final ids = ExerciseLibrary.all.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every muscle group has a corresponding asset path', () {
      for (final muscle in MuscleGroup.values) {
        final path = muscleAsset(muscle);
        expect(path, 'assets/muscles/${muscle.name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}')}.png');
      }
      expect(muscleAsset(MuscleGroup.sideDelts), 'assets/muscles/side_delts.png');
      expect(muscleAsset(MuscleGroup.upperBack), 'assets/muscles/upper_back.png');
    });

    test('contains every required exercise', () {
      final names = _names(ExerciseLibrary.all);
      for (final required in _requiredNames) {
        expect(names, contains(required));
      }
    });

    test('every muscle has at least one exercise that trains it', () {
      for (final muscle in MuscleGroup.values) {
        expect(
          ExerciseLibrary.all.any((e) => e.primaryMuscles.contains(muscle)),
          isTrue,
          reason: muscle.label,
        );
      }
    });

    test('every muscle has at least one exercise that trains it', () {
      for (final muscle in MuscleGroup.values) {
        expect(
          ExerciseLibrary.all.any((e) => e.primaryMuscles.contains(muscle)),
          isTrue,
          reason: muscle.label,
        );
      }
    });

    test('every exercise is complete', () {
      for (final e in ExerciseLibrary.all) {
        expect(e.primaryMuscles, isNotEmpty, reason: e.name);
        expect(e.equipment, isNotEmpty, reason: e.name);
        expect(e.instructions, isNotEmpty, reason: e.name);
      }
    });

    test('every pattern and every type is covered', () {
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

    test('byId finds an exercise and returns null for unknown ids', () {
      expect(
        ExerciseLibrary.byId('machine_chest_press')?.name,
        'Machine Chest Press',
      );
      expect(ExerciseLibrary.byId('nope'), isNull);
    });
  });

  group('ExerciseLibrary.filter', () {
    test('search "chest" finds the chest exercises', () {
      final names = _names(ExerciseLibrary.filter(query: 'chest'));
      expect(
        names,
        containsAll([
          'Machine Chest Press',
          'Barbell Bench Press',
          'Dumbbell Bench Press',
          'Cable Chest Press',
          'Push-Up',
        ]),
      );
      expect(names, isNot(contains('Leg Press')));
    });

    test('search is case-insensitive and trims spaces', () {
      expect(_names(ExerciseLibrary.filter(query: '  LEG PRESS ')), [
        'Leg Press',
      ]);
    });

    test('type filter only returns that type', () {
      final result = ExerciseLibrary.filter(
        exerciseType: ExerciseType.bodyweight,
      );
      expect(result, isNotEmpty);
      expect(
        result.every((e) => e.exerciseType == ExerciseType.bodyweight),
        isTrue,
      );
    });

    test('pattern filter only returns that pattern', () {
      final result = ExerciseLibrary.filter(
        movementPattern: MovementPattern.hipDominant,
      );
      expect(result, isNotEmpty);
      expect(
        result.every((e) => e.movementPattern == MovementPattern.hipDominant),
        isTrue,
      );
    });

    test('Machine + Horizontal Push combine', () {
      final names = _names(
        ExerciseLibrary.filter(
          exerciseType: ExerciseType.machine,
          movementPattern: MovementPattern.horizontalPush,
        ),
      );
      expect(names.toSet(), {'Machine Chest Press', 'Cable Chest Press'});
    });

    test('filters and search combine', () {
      final names = _names(
        ExerciseLibrary.filter(
          query: 'press',
          exerciseType: ExerciseType.freeWeight,
          movementPattern: MovementPattern.verticalPush,
        ),
      );
      expect(names.toSet(), {
        'Dumbbell Shoulder Press',
        'Barbell Overhead Press',
      });
    });
  });

  group('Exercise Library screen', () {
    Future<void> openLibrary(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: ExerciseLibraryScreen()));
    }

    testWidgets('search narrows the list', (tester) async {
      await openLibrary(tester);
      expect(find.text('Leg Press'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'chest');
      await tester.pump();

      expect(find.text('Machine Chest Press'), findsOneWidget);
      expect(find.text('Leg Press'), findsNothing);
    });

    testWidgets('type and pattern chips combine', (tester) async {
      await openLibrary(tester);

      await tester.tap(find.text('Machine'));
      await tester.pump();
      await tester.tap(find.text('Horizontal Push'));
      await tester.pump();

      expect(find.text('Machine Chest Press'), findsOneWidget);
      expect(find.text('Cable Chest Press'), findsOneWidget);
      expect(find.text('Barbell Bench Press'), findsNothing);
      expect(find.text('Leg Press'), findsNothing);
    });

    testWidgets('tapping a card opens the detail screen', (tester) async {
      await openLibrary(tester);

      await tester.enterText(find.byType(TextField), 'machine chest');
      await tester.pump();
      await tester.tap(find.text('Machine Chest Press'));
      await tester.pumpAndSettle();

      expect(find.text('Primary muscles'), findsOneWidget);
      expect(find.text('Secondary muscles'), findsOneWidget);
      expect(find.text('Equipment'), findsOneWidget);
      expect(find.text('Instructions'), findsOneWidget);
      // Planning data must never appear on the exercise definition.
      expect(find.textContaining('sets'), findsNothing);
      expect(find.textContaining('rest'), findsNothing);
    });
  });
}
