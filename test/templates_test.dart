import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/app.dart';
import 'package:anthrofit/data/exercise_library.dart';
import 'package:anthrofit/data/program_repository.dart';
import 'package:anthrofit/data/workout_templates.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/state/program_controller.dart';

import 'test_helpers.dart';

List<String> _names(Workout w) => [
  for (final p in w.exercises) ExerciseLibrary.byId(p.exerciseId)!.name,
];

Set<MovementPattern> _patterns(Workout w) => {
  for (final p in w.exercises)
    ExerciseLibrary.byId(p.exerciseId)!.movementPattern,
};

TrainingProgram _programFrom(ProgramTemplate t, {String? name}) {
  final workouts = buildWorkoutsForProgram(t);
  return TrainingProgram(
    id: 'prog-${name ?? t.label}',
    name: name ?? t.defaultName,
    workouts: workouts,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  // The exercise catalogue is an asset now, so it has to be loaded.
  useExerciseLibrary();

  // ---------------------------------------------------------------------
  group('templates only reference the global Exercise Library', () {
    test('every template ID is a real library exercise', () {
      for (final t in WorkoutTemplate.values) {
        for (final id in t.exerciseIds) {
          expect(
            ExerciseLibrary.byId(id),
            isNotNull,
            reason: '${t.label}: $id',
          );
        }
      }
    });

    test('no template repeats an exercise inside one workout', () {
      for (final t in WorkoutTemplate.values) {
        expect(
          t.exerciseIds.toSet().length,
          t.exerciseIds.length,
          reason: t.label,
        );
      }
    });

    test(
      'a built workout points at library IDs and never copies a definition',
      () {
        final w = buildWorkoutFromTemplate(WorkoutTemplate.push);
        expect(
          w.exercises.map((p) => p.exerciseId).toList(),
          WorkoutTemplate.push.exerciseIds,
        );
        for (final p in w.exercises) {
          expect(
            identical(
              ExerciseLibrary.byId(p.exerciseId),
              ExerciseLibrary.byId(p.exerciseId),
            ),
            isTrue,
          );
        }
      },
    );

    test('the same template always gives the same exercises, in order', () {
      final a = buildWorkoutFromTemplate(WorkoutTemplate.legs);
      final b = buildWorkoutFromTemplate(WorkoutTemplate.legs);
      expect(
        a.exercises.map((p) => p.exerciseId).toList(),
        b.exercises.map((p) => p.exerciseId).toList(),
      );
      expect(a.id, isNot(b.id)); // but they are separate workouts
    });
  });

  group('workout templates', () {
    test('default names', () {
      expect(WorkoutTemplate.values.map((t) => t.label).toList(), [
        'Push',
        'Pull',
        'Legs',
        'Upper',
        'Lower',
        'Full Body',
        'Cardio',
        'Custom',
      ]);
      expect(WorkoutTemplate.push.defaultName, 'Push');
      expect(WorkoutTemplate.fullBody.defaultName, 'Full Body');
      expect(WorkoutTemplate.cardio.defaultName, 'Cardio');
      expect(WorkoutTemplate.custom.defaultName, ''); // the user names it
    });

    test('Push, Pull and Legs seed the expected exercises in order', () {
      expect(_names(buildWorkoutFromTemplate(WorkoutTemplate.push)), [
        'Barbell Bench Press',
        'Machine Chest Press',
        'Dumbbell Shoulder Press',
        'Dumbbell Lateral Raise',
        'Cable Triceps Pushdown',
      ]);
      expect(_names(buildWorkoutFromTemplate(WorkoutTemplate.pull)), [
        'Lat Pulldown',
        'Seated Cable Row',
        'Chest-Supported Dumbbell Row',
        'Face Pull',
        'Dumbbell Biceps Curl',
      ]);
      expect(_names(buildWorkoutFromTemplate(WorkoutTemplate.legs)), [
        'Leg Press',
        'Romanian Deadlift',
        'Seated Leg Curl',
        'Leg Extension',
        'Standing Calf Raise',
      ]);
    });

    test('Upper trains upper-body muscles; Lower trains leg muscles', () {
      final upper = buildWorkoutFromTemplate(WorkoutTemplate.upper);
      expect(
        _patterns(upper),
        containsAll({
          MovementPattern.horizontalPush,
          MovementPattern.verticalPull,
        }),
      );
      for (final planned in upper.exercises) {
        for (final m in ExerciseLibrary.byId(
          planned.exerciseId,
        )!.primaryMuscles) {
          expect(m.region, MuscleRegion.upper, reason: m.label);
        }
      }

      final lower = buildWorkoutFromTemplate(WorkoutTemplate.lower);
      expect(
        _patterns(lower),
        containsAll({
          MovementPattern.kneeDominant,
          MovementPattern.hipDominant,
        }),
      );
      for (final planned in lower.exercises) {
        for (final m in ExerciseLibrary.byId(
          planned.exerciseId,
        )!.primaryMuscles) {
          expect(m.region, MuscleRegion.lower, reason: m.label);
        }
      }
    });

    test('Full Body covers knee, hip, horizontal push and horizontal pull', () {
      final patterns = _patterns(
        buildWorkoutFromTemplate(WorkoutTemplate.fullBody),
      );
      expect(
        patterns,
        containsAll({
          MovementPattern.kneeDominant,
          MovementPattern.hipDominant,
          MovementPattern.horizontalPush,
          MovementPattern.horizontalPull,
        }),
      );
    });

    test('Cardio is cardio exercises only; Custom starts empty', () {
      final cardio = buildWorkoutFromTemplate(WorkoutTemplate.cardio);
      expect(cardio.exercises, isNotEmpty);
      for (final planned in cardio.exercises) {
        expect(
          ExerciseLibrary.byId(planned.exerciseId)!.exerciseType,
          ExerciseType.cardio,
        );
      }
      expect(
        buildWorkoutFromTemplate(WorkoutTemplate.custom).exercises,
        isEmpty,
      );
    });

    test(
      'every seeded exercise gets the default prescription, with no load',
      () {
        for (final t in WorkoutTemplate.values) {
          for (final p in buildWorkoutFromTemplate(t).exercises) {
            final isCardio =
                ExerciseLibrary.byId(p.exerciseId)!.exerciseType ==
                ExerciseType.cardio;
            if (isCardio) {
              // Cardio is prescribed as time: one set, no rep target, no rest.
              expect(p.plannedSets.length, 1, reason: t.label);
              final s = p.plannedSets.single;
              expect(s.targetDurationSeconds, isNotNull);
              expect(s.targetRepMin, isNull);
              expect(s.targetLoadKg, isNull);
              expect(s.restSeconds, 0);
            } else {
              expect(p.plannedSets.length, 3, reason: t.label);
              for (final s in p.plannedSets) {
                expect(s.setType, SetType.working);
                expect(s.targetRepMin, 8);
                expect(s.targetRepMax, 12);
                expect(s.targetLoadKg, isNull);
                expect(s.restSeconds, 90);
              }
            }
            expect(p.note, '');
          }
        }
      },
    );
  });

  group('program templates', () {
    test('which workouts are created, and none get weekdays', () {
      List<String> names(ProgramTemplate t) =>
          buildWorkoutsForProgram(t).map((w) => w.name).toList();

      expect(names(ProgramTemplate.pushPullLegs), ['Push', 'Pull', 'Legs']);
      expect(names(ProgramTemplate.upperLower), ['Upper', 'Lower']);
      expect(names(ProgramTemplate.fullBody), ['Full Body']);
      expect(names(ProgramTemplate.custom), isEmpty);

      expect(_programFrom(ProgramTemplate.pushPullLegs).schedule, isEmpty);
    });

    test('default program names', () {
      expect(
        ProgramTemplate.pushPullLegs.defaultName,
        'Push Pull Legs Program',
      );
      expect(ProgramTemplate.upperLower.defaultName, 'Upper Lower Program');
      expect(ProgramTemplate.fullBody.defaultName, 'Full Body Program');
    });

    test('two programs from one template never share workouts', () {
      final a = _programFrom(ProgramTemplate.pushPullLegs, name: 'A');
      final b = _programFrom(ProgramTemplate.pushPullLegs, name: 'B');
      final aIds = {
        for (final w in a.workouts) w.id,
        for (final w in a.workouts) ...w.exercises.map((p) => p.id),
      };
      final bIds = {
        for (final w in b.workouts) w.id,
        for (final w in b.workouts) ...w.exercises.map((p) => p.id),
      };
      expect(aIds.intersection(bIds), isEmpty);
      // ...but they reference the same global exercises.
      expect(
        a.workouts.first.exercises.first.exerciseId,
        b.workouts.first.exercises.first.exerciseId,
      );
    });

    test('editing one program leaves the other unchanged', () async {
      seedNoProfile();
      final c = ProgramController(ProgramRepository());
      await c.load();
      final a = _programFrom(ProgramTemplate.pushPullLegs, name: 'A');
      final b = _programFrom(ProgramTemplate.pushPullLegs, name: 'B');
      await c.saveProgram(a);
      await c.saveProgram(b);

      final before = c.programById('prog-B')!.workouts.first.exercises.length;
      final edited = a.copyWith(
        workouts: [
          a.workouts.first.copyWith(
            name: 'Renamed',
            exercises: [a.workouts.first.exercises.first],
          ),
          ...a.workouts.skip(1),
        ],
      );
      await c.saveProgram(edited);

      expect(c.programById('prog-A')!.workouts.first.name, 'Renamed');
      expect(c.programById('prog-B')!.workouts.first.name, 'Push');
      expect(c.programById('prog-B')!.workouts.first.exercises.length, before);
    });

    test(
      'generated programs, workouts and exercises survive a restart',
      () async {
        seedNoProfile();
        final c = ProgramController(ProgramRepository());
        await c.load();
        final program = _programFrom(ProgramTemplate.upperLower);
        await c.saveProgram(program);

        final reloaded = ProgramController(ProgramRepository());
        await reloaded.load();
        final saved = reloaded.programs.single;
        expect(saved.name, 'Upper Lower Program');
        expect(saved.workouts.map((w) => w.name).toList(), ['Upper', 'Lower']);
        expect(
          saved.workouts.first.exercises.map((p) => p.exerciseId).toList(),
          WorkoutTemplate.upper.exerciseIds,
        );
        final first = saved.workouts.first.exercises.first;
        expect(first.plannedSets.length, 3);
        expect(first.plannedSets.first.repRangeLabel, '8–12');
        expect(first.plannedSets.first.restSeconds, 90);
      },
    );
  });

  // ---------------------------------------------------------------------
  group('creation screens', () {
    void useTallScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Future<void> launchApp(WidgetTester tester) async {
      await tester.pumpWidget(AnthrofitApp(authService: FakeAuthService()));
      await tester.pumpAndSettle();
    }

    Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> openProgramTypePicker(WidgetTester tester) async {
      seedAppData();
      useTallScreen(tester);
      await launchApp(tester);
      await tapAndSettle(
        tester,
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Program'),
        ),
      );
      await tapAndSettle(tester, find.byKey(const ValueKey('create-program')));
      expect(find.text('Set up program'), findsOneWidget);
    }

    /// Chooses [template] and generates, landing in the planner.
    Future<void> generateFrom(
      WidgetTester tester,
      ProgramTemplate template,
    ) async {
      await completeProgramSetup(tester, template: template);
    }

    Future<void> openWorkoutTypePicker(WidgetTester tester) async {
      await openProgramTypePicker(tester);
      await generateFrom(tester, ProgramTemplate.custom);
      await tapAndSettle(tester, find.text('Add workout'));
      expect(find.text('Choose a workout type'), findsOneWidget);
    }

    String nameFieldText(WidgetTester tester) => tester
        .widget<TextFormField>(find.byType(TextFormField).first)
        .controller!
        .text;

    testWidgets('Push Pull Legs creates Push, Pull and Legs, with no days', (
      tester,
    ) async {
      await openProgramTypePicker(tester);
      await advanceSetupTo(
        tester,
        setupStructureTile(ProgramTemplate.pushPullLegs),
      );
      expect(find.text('Creates Push · Pull · Legs'), findsOneWidget);
      expect(find.text('Creates Upper · Lower'), findsOneWidget);
      expect(find.text('Creates Full Body'), findsOneWidget);
      await tapAndSettle(
        tester,
        setupStructureTile(ProgramTemplate.pushPullLegs),
      );
      await tapSetupContinue(tester); // to the name step
      await tapSetupContinue(tester); // generate

      expect(find.text('New program'), findsOneWidget);
      expect(nameFieldText(tester), 'Push Pull Legs Program');
      expect(find.text('Push'), findsOneWidget);
      expect(find.text('Pull'), findsOneWidget);
      expect(find.text('Legs'), findsOneWidget);
      expect(find.text('Schedule'), findsNothing); // no days were chosen
      for (final chip in tester.widgetList<FilterChip>(
        find.byType(FilterChip),
      )) {
        expect(chip.selected, isFalse);
      }
    });

    testWidgets('Upper Lower creates Upper and Lower', (tester) async {
      await openProgramTypePicker(tester);
      await generateFrom(tester, ProgramTemplate.upperLower);

      expect(nameFieldText(tester), 'Upper Lower Program');
      expect(find.text('Upper'), findsOneWidget);
      expect(find.text('Lower'), findsOneWidget);
    });

    testWidgets('Full Body creates one Full Body workout', (tester) async {
      await openProgramTypePicker(tester);
      await generateFrom(tester, ProgramTemplate.fullBody);

      expect(nameFieldText(tester), 'Full Body Program');
      expect(find.text('Full Body'), findsOneWidget);
      expect(find.text('6 exercises · 18 sets'), findsOneWidget);
    });

    testWidgets('Custom creates no workouts', (tester) async {
      await openProgramTypePicker(tester);
      await generateFrom(tester, ProgramTemplate.custom);

      expect(find.text('New program'), findsOneWidget);
      expect(find.text('Add workout'), findsOneWidget);
      expect(find.byTooltip('Remove workout'), findsNothing);
    });

    testWidgets(
      'generated workouts can be renamed, trimmed, extended and removed',
      (tester) async {
        await openProgramTypePicker(tester);
        await generateFrom(tester, ProgramTemplate.pushPullLegs);

        // Open Push: three seeded exercises.
        await tapAndSettle(tester, find.text('Push'));
        expect(find.text('Edit workout'), findsOneWidget);
        expect(find.text('Barbell Bench Press'), findsOneWidget);

        // Rename, remove one exercise, add another.
        await tester.enterText(find.byType(TextFormField).first, 'Push Day');
        await tapAndSettle(tester, find.byTooltip('Remove exercise').first);
        expect(find.text('Barbell Bench Press'), findsNothing);
        await tapAndSettle(tester, find.text('Add exercises'));
        await tester.tap(find.text('Push-Up'));
        await tester.pump();
        await tapAndSettle(tester, find.text('Add 1 exercise'));
        expect(find.text('Push-Up'), findsOneWidget);
        await tapAndSettle(tester, find.text('Done'));

        expect(find.text('Push Day'), findsOneWidget);
        expect(find.text('Push'), findsNothing);
        // Push Day, Pull and Legs all have five exercises now.
        expect(find.text('5 exercises · 15 sets'), findsNWidgets(3));

        // Remove Legs entirely.
        await tapAndSettle(tester, find.byTooltip('Remove workout').last);
        expect(find.text('Legs'), findsNothing);
        expect(find.text('Pull'), findsOneWidget);
      },
    );

    testWidgets('workouts in the planner can be reordered', (tester) async {
      await openProgramTypePicker(tester);
      await generateFrom(tester, ProgramTemplate.pushPullLegs);

      double y(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(y('Push') < y('Pull'), isTrue);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.drag_handle).first),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.moveBy(const Offset(0, 250));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(y('Pull') < y('Push'), isTrue);
      expect(y('Push') < y('Legs'), isTrue);
    });

    testWidgets('a Push workout is named and seeded automatically', (
      tester,
    ) async {
      await openWorkoutTypePicker(tester);
      for (final label in [
        'Push',
        'Pull',
        'Legs',
        'Upper',
        'Lower',
        'Full Body',
        'Cardio',
        'Custom',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tapAndSettle(tester, find.text('Push'));

      expect(find.text('New workout'), findsOneWidget);
      expect(nameFieldText(tester), 'Push');
      expect(find.text('Barbell Bench Press'), findsOneWidget);
      expect(find.text('Machine Chest Press'), findsOneWidget);
      expect(find.text('Dumbbell Shoulder Press'), findsOneWidget);
      expect(find.text('Dumbbell Lateral Raise'), findsOneWidget);
      expect(find.text('Cable Triceps Pushdown'), findsOneWidget);

      // Saving it puts it in the program draft.
      await tapAndSettle(tester, find.text('Done'));
      expect(find.text('5 exercises · 15 sets'), findsOneWidget);
    });

    testWidgets('Custom asks for a name and inserts no exercises', (
      tester,
    ) async {
      await openWorkoutTypePicker(tester);
      await tapAndSettle(tester, find.text('Custom'));

      expect(nameFieldText(tester), '');
      expect(find.text('No exercises yet.'), findsOneWidget);
      await tapAndSettle(tester, find.text('Done'));
      expect(find.text('Enter a workout name'), findsOneWidget);
    });

    testWidgets('Cardio is seeded with cardio exercises', (tester) async {
      await openWorkoutTypePicker(tester);
      await tapAndSettle(tester, find.text('Cardio'));

      expect(nameFieldText(tester), 'Cardio');
      expect(find.text('Rowing Machine'), findsOneWidget);
      expect(find.text('Stationary Bike'), findsOneWidget);
      expect(find.text('Treadmill Run'), findsOneWidget);
      expect(find.text('No exercises yet.'), findsNothing);
    });
  });
}
