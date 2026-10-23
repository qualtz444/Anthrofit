import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/app.dart';
import 'package:anthrofit/data/exercise_library.dart';
import 'package:anthrofit/data/exercise_library_repository.dart';
import 'package:anthrofit/data/storage_scope.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/state/exercise_library_controller.dart';

import 'test_helpers.dart';

Exercise _draft({String name = 'My Exercise'}) => Exercise(
  id: '',
  name: name,
  exerciseType: ExerciseType.freeWeight,
  movementPattern: MovementPattern.isolation,
  primaryMuscles: const [MuscleGroup.biceps],
  secondaryMuscles: const [MuscleGroup.forearms],
  equipment: const [EquipmentItem.dumbbell],
  experienceLevel: ExperienceLevel.beginner,
  complexity: Complexity.low,
  instructions: const ['Curl it.'],
);

Future<ExerciseLibraryController> _controller() async {
  final c = ExerciseLibraryController(ExerciseLibraryRepository());
  await c.load();
  return c;
}

void main() {
  useExerciseLibrary();

  group('the Exercise model round-trips', () {
    test('every field survives JSON', () {
      final back = Exercise.fromJson(
        jsonDecode(jsonEncode(_draft().toJson())) as Map<String, dynamic>,
      );
      expect(back.name, 'My Exercise');
      expect(back.exerciseType, ExerciseType.freeWeight);
      expect(back.movementPattern, MovementPattern.isolation);
      expect(back.primaryMuscles, [MuscleGroup.biceps]);
      expect(back.secondaryMuscles, [MuscleGroup.forearms]);
      expect(back.equipment, [EquipmentItem.dumbbell]);
      expect(back.experienceLevel, ExperienceLevel.beginner);
      expect(back.complexity, Complexity.low);
      expect(back.instructions, ['Curl it.']);
    });

    test('copyWith never changes the id', () {
      final original = ExerciseLibrary.byId('lat_pulldown')!;
      final copy = original.copyWith(name: 'Renamed');
      expect(copy.id, original.id);
      expect(copy.name, 'Renamed');
      expect(copy.primaryMuscles, original.primaryMuscles);
    });
  });

  group('the built-in catalogue is fixed', () {
    test('it starts as the built-in catalogue', () async {
      seedNoProfile();
      final c = await _controller();
      expect(c.all.length, ExerciseLibrary.builtIn.length);
      expect(ExerciseLibrary.byId('lat_pulldown'), isNotNull);
    });

    test('an added exercise appears everywhere the library is read', () async {
      seedNoProfile();
      final c = await _controller();
      final created = await c.add(_draft(name: 'Zottman Curl'));

      expect(created.id, startsWith('custom_'));
      expect(c.isCustom(created.id), isTrue);
      expect(c.isBuiltIn(created.id), isFalse);
      // Static reads see it too, which is what the rest of the app uses.
      expect(ExerciseLibrary.byId(created.id)!.name, 'Zottman Curl');
      expect(ExerciseLibrary.all.length, ExerciseLibrary.builtIn.length + 1);
      expect(ExerciseLibrary.filter(query: 'zottman').single.id, created.id);
    });

    test(
      'editing a built-in makes a copy and leaves the original alone',
      () async {
        seedNoProfile();
        final c = await _controller();
        final original = ExerciseLibrary.byId('lat_pulldown')!;

        final saved = await c.update(
          original.copyWith(name: 'Lat Pulldown wide'),
        );

        // A new exercise, owned by the user.
        expect(saved.id, isNot('lat_pulldown'));
        expect(saved.id, startsWith('custom_'));
        expect(saved.name, 'Lat Pulldown wide');
        expect(c.isCustom(saved.id), isTrue);

        // The built-in is untouched, so existing programs mean what they meant.
        expect(ExerciseLibrary.byId('lat_pulldown')!.name, 'Lat Pulldown');
        expect(ExerciseLibrary.all.length, ExerciseLibrary.builtIn.length + 1);
      },
    );

    test(
      'a built-in copy saved without renaming is marked as custom',
      () async {
        seedNoProfile();
        final c = await _controller();
        final original = ExerciseLibrary.byId('leg_press')!;
        final saved = await c.update(
          original.copyWith(experienceLevel: ExperienceLevel.advanced),
        );
        expect(saved.name, 'Leg Press (custom)');
        expect(saved.experienceLevel, ExperienceLevel.advanced);
        expect(
          ExerciseLibrary.byId('leg_press')!.experienceLevel,
          original.experienceLevel,
        );
      },
    );

    test(
      'editing one of your own changes it in place, keeping its id',
      () async {
        seedNoProfile();
        final c = await _controller();
        final created = await c.add(_draft(name: 'Mine'));

        final saved = await c.update(created.copyWith(name: 'Mine renamed'));

        expect(saved.id, created.id); // programs using it follow the change
        expect(ExerciseLibrary.byId(created.id)!.name, 'Mine renamed');
        expect(ExerciseLibrary.all.length, ExerciseLibrary.builtIn.length + 1);
      },
    );

    test('a duplicate is a separate exercise the user owns', () async {
      seedNoProfile();
      final c = await _controller();
      final original = ExerciseLibrary.byId('lat_pulldown')!;
      final copy = await c.duplicate(original);

      expect(copy.id, isNot(original.id));
      expect(copy.name, 'Lat Pulldown copy');
      expect(c.isCustom(copy.id), isTrue);
      await c.update(copy.copyWith(name: 'Changed'));
      expect(ExerciseLibrary.byId('lat_pulldown')!.name, 'Lat Pulldown');
    });

    test('a built-in cannot be removed', () async {
      seedNoProfile();
      final c = await _controller();
      await c.remove('lat_pulldown');
      expect(ExerciseLibrary.byId('lat_pulldown'), isNotNull);
      expect(ExerciseLibrary.all.length, ExerciseLibrary.builtIn.length);
    });

    test('your own exercise can be deleted', () async {
      seedNoProfile();
      final c = await _controller();
      final created = await c.add(_draft());
      await c.remove(created.id);
      expect(ExerciseLibrary.byId(created.id), isNull);
      expect(ExerciseLibrary.all.length, ExerciseLibrary.builtIn.length);
    });
  });

  group('the changes are saved', () {
    test('they survive a restart', () async {
      seedNoProfile();
      final c = await _controller();
      final created = await c.add(_draft(name: 'Zottman Curl'));
      final copy = await c.update(
        ExerciseLibrary.byId('leg_press')!.copyWith(name: 'Leg Press v2'),
      );

      // A fresh start, as if the app had been reopened.
      ExerciseLibrary.reset();
      final reloaded = await _controller();

      expect(ExerciseLibrary.byId(created.id)!.name, 'Zottman Curl');
      expect(ExerciseLibrary.byId(copy.id)!.name, 'Leg Press v2');
      expect(ExerciseLibrary.byId('leg_press')!.name, 'Leg Press');
      expect(reloaded.isCustom(created.id), isTrue);
    });

    test('one owner never sees another owner\'s exercises', () async {
      seedNoProfile();
      final guest = await _controller();
      await guest.add(_draft(name: 'Guest Curl'));

      final account = ExerciseLibraryController(
        ExerciseLibraryRepository(scope: StorageScope.user('uid_ann')),
      );
      await account.load();
      expect(ExerciseLibrary.all.length, ExerciseLibrary.builtIn.length);
      expect(ExerciseLibrary.filter(query: 'guest curl'), isEmpty);
    });

    test(
      'unreadable saved data falls back to the built-in catalogue',
      () async {
        seedNoProfile();
        final c = ExerciseLibraryController(ExerciseLibraryRepository());
        ExerciseLibrary.applyCustomisations(
          ExerciseLibraryData.fromJson({'custom': 'not a list'}),
        );
        await c.load();
        expect(ExerciseLibrary.all.length, ExerciseLibrary.builtIn.length);
      },
    );
  });

  // ---------------------------------------------------------------------
  group('managing exercises on screen', () {
    void useTallScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> openManage(WidgetTester tester) async {
      seedSavedProfile();
      useTallScreen(tester);
      await tester.pumpWidget(AnthrofitApp(authService: FakeAuthService()));
      await tester.pumpAndSettle();
      await tapAndSettle(
        tester,
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Program'),
        ),
      );
      await tapAndSettle(tester, find.text('Manage exercises'));
      expect(find.widgetWithText(AppBar, 'Manage exercises'), findsOneWidget);
    }

    testWidgets('the Program tab offers Manage exercises', (tester) async {
      await openManage(tester);
      expect(find.text('Lat Pulldown'), findsOneWidget);
      expect(find.text('Add exercise'), findsOneWidget);
    });

    testWidgets('an exercise can be added with chips, not typing', (
      tester,
    ) async {
      await openManage(tester);
      await tapAndSettle(tester, find.text('Add exercise'));
      expect(find.text('New exercise'), findsOneWidget);

      // Name is typed; everything else is chosen.
      await tester.enterText(find.byType(TextFormField).first, 'Zottman Curl');
      await tapAndSettle(
        tester,
        find.widgetWithText(ChoiceChip, 'Free weight'),
      );
      await tapAndSettle(tester, find.widgetWithText(ChoiceChip, 'Isolation'));
      await tapAndSettle(
        tester,
        find.widgetWithText(FilterChip, 'Biceps').first,
      );
      await tapAndSettle(
        tester,
        find.widgetWithText(FilterChip, 'Dumbbell').first,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('save-exercise')));
      await tapAndSettle(tester, find.byKey(const ValueKey('save-exercise')));

      expect(find.text('New exercise'), findsNothing);
      // The list is long and lazy, so search for it rather than scrolling.
      await tester.enterText(find.byType(TextField).first, 'Zottman');
      await tester.pumpAndSettle();
      expect(find.text('Zottman Curl'), findsOneWidget);
      expect(ExerciseLibrary.filter(query: 'zottman'), hasLength(1));
    });

    testWidgets('a new exercise needs a name, a muscle and equipment', (
      tester,
    ) async {
      await openManage(tester);
      await tapAndSettle(tester, find.text('Add exercise'));
      await tester.ensureVisible(find.byKey(const ValueKey('save-exercise')));
      await tapAndSettle(tester, find.byKey(const ValueKey('save-exercise')));

      expect(find.text('Enter a name'), findsOneWidget);
      expect(find.text('Choose at least one primary muscle'), findsOneWidget);
      expect(
        find.text('Choose at least one piece of equipment'),
        findsOneWidget,
      );
      expect(find.text('New exercise'), findsOneWidget); // did not save
    });

    testWidgets('a built-in offers no Delete, and editing says it copies', (
      tester,
    ) async {
      await openManage(tester);

      await tapAndSettle(tester, find.byTooltip('Exercise options').first);
      expect(find.text('Edit as a copy'), findsOneWidget);
      expect(find.text('Duplicate'), findsOneWidget);
      expect(find.text('Delete'), findsNothing); // built-ins are fixed

      await tapAndSettle(tester, find.text('Edit as a copy'));
      expect(find.widgetWithText(AppBar, 'Edit as a copy'), findsOneWidget);
      expect(find.textContaining('create your own copy'), findsOneWidget);
      expect(find.text('Save as my copy'), findsOneWidget);
    });
  });
}
