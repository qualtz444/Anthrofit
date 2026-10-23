import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/app.dart';
import 'package:anthrofit/data/program_repository.dart';
import 'package:anthrofit/data/setup_options.dart';
import 'package:anthrofit/data/workout_templates.dart';
import 'package:anthrofit/models/models.dart';

import 'test_helpers.dart';

void main() {
  // The exercise catalogue is an asset now, so it has to be loaded.
  useExerciseLibrary();

  // ---------------------------------------------------------------------
  group('muscle classification', () {
    test('region and movement group are independent', () {
      expect(MuscleGroup.chest.region, MuscleRegion.upper);
      expect(MuscleGroup.chest.movementGroup, MovementGroup.push);
      expect(MuscleGroup.lats.region, MuscleRegion.upper);
      expect(MuscleGroup.lats.movementGroup, MovementGroup.pull);
      expect(MuscleGroup.quads.region, MuscleRegion.lower);
      expect(MuscleGroup.quads.movementGroup, MovementGroup.push);
      expect(MuscleGroup.hamstrings.region, MuscleRegion.lower);
      expect(MuscleGroup.hamstrings.movementGroup, MovementGroup.pull);
      expect(MuscleGroup.core.region, MuscleRegion.core);
      expect(MuscleGroup.core.movementGroup, MovementGroup.neither);
    });

    test('every muscle is classified on both dimensions', () {
      for (final muscle in MuscleGroup.values) {
        expect(muscle.region, isNotNull, reason: muscle.name);
        expect(muscle.movementGroup, isNotNull, reason: muscle.name);
      }
      // Both dimensions are really used, so neither is a stand-in for the other.
      final regions = MuscleGroup.values.map((m) => m.region).toSet();
      final groups = MuscleGroup.values.map((m) => m.movementGroup).toSet();
      expect(regions, MuscleRegion.values.toSet());
      expect(groups, MovementGroup.values.toSet());
    });

    test('muscles are found by their stable id, not their label', () {
      expect(MuscleGroup.byId('chest'), MuscleGroup.chest);
      expect(MuscleGroup.byId('Chest'), isNull); // the label is not the id
      expect(MuscleGroup.byId('gone'), isNull);
    });
  });

  group('muscles for a focus', () {
    test('full body and choose muscles cover everything', () {
      expect(musclesForFocus(TrainingFocus.fullBody), MuscleGroup.values);
      expect(musclesForFocus(TrainingFocus.chooseMuscles), MuscleGroup.values);
    });

    test('push and pull filter by movement group, across both regions', () {
      final push = musclesForFocus(TrainingFocus.push);
      expect(push, contains(MuscleGroup.chest)); // upper
      expect(push, contains(MuscleGroup.quads)); // lower
      expect(push, isNot(contains(MuscleGroup.lats)));
      expect(push.every((m) => m.movementGroup == MovementGroup.push), isTrue);

      final pull = musclesForFocus(TrainingFocus.pull);
      expect(pull, contains(MuscleGroup.lats));
      expect(pull, contains(MuscleGroup.hamstrings));
      expect(pull, isNot(contains(MuscleGroup.chest)));
      expect(pull.every((m) => m.movementGroup == MovementGroup.pull), isTrue);
    });

    test('upper and lower filter by region, across both movement groups', () {
      final upper = musclesForFocus(TrainingFocus.upperBody);
      expect(
        upper,
        containsAll([
          MuscleGroup.chest, // push
          MuscleGroup.lats, // pull
          MuscleGroup.biceps,
          MuscleGroup.triceps,
        ]),
      );
      expect(upper, isNot(contains(MuscleGroup.quads)));
      expect(upper.every((m) => m.region == MuscleRegion.upper), isTrue);

      final lower = musclesForFocus(TrainingFocus.lowerBody);
      expect(
        lower,
        containsAll([
          MuscleGroup.quads, // push
          MuscleGroup.hamstrings, // pull
        ]),
      );
      expect(lower.every((m) => m.region == MuscleRegion.lower), isTrue);
    });

    test(
      'a named focus starts fully selected; choose muscles starts empty',
      () {
        expect(
          defaultMusclesForFocus(TrainingFocus.upperBody),
          musclesForFocus(TrainingFocus.upperBody),
        );
        expect(defaultMusclesForFocus(TrainingFocus.chooseMuscles), isEmpty);
      },
    );
  });

  group('equipment for a category', () {
    test('only equipment from the chosen places is offered', () {
      final home = equipmentForCategories({EquipmentCategory.home});
      expect(home, contains(EquipmentItem.dumbbell));
      expect(home, isNot(contains(EquipmentItem.cable)));
      expect(home, isNot(contains(EquipmentItem.barbell)));

      final calisthenics = equipmentForCategories({
        EquipmentCategory.calisthenics,
      });
      expect(calisthenics, contains(EquipmentItem.pullUpBar));
      expect(calisthenics, contains(EquipmentItem.dipStation));
      expect(calisthenics, isNot(contains(EquipmentItem.dumbbell)));

      final commercial = equipmentForCategories({
        EquipmentCategory.commercialGym,
      });
      expect(commercial, contains(EquipmentItem.cable));
      expect(commercial, contains(EquipmentItem.machine));
      expect(commercial, contains(EquipmentItem.dumbbell)); // has it all
    });

    test('categories combine, without repeats', () {
      final both = equipmentForCategories({
        EquipmentCategory.home,
        EquipmentCategory.calisthenics,
      });
      expect(both, contains(EquipmentItem.dumbbell)); // home
      expect(both, contains(EquipmentItem.dipStation)); // calisthenics
      expect(both.toSet().length, both.length);
      expect(equipmentForCategories({}), isEmpty);
    });

    test('"None" is never offered: it means an exercise needs nothing', () {
      for (final category in EquipmentCategory.values) {
        expect(
          equipmentForCategories({category}),
          isNot(contains(EquipmentItem.none)),
        );
      }
    });

    test('the profile suggests a starting set of places', () {
      expect(categoriesFromProfile(null), isEmpty);
      expect(
        categoriesFromProfile(sampleProfile), // machines + cables
        {EquipmentCategory.commercialGym},
      );
      expect(
        categoriesFromProfile(
          sampleProfile.copyWith(
            equipment: [
              EquipmentAccess.bodyweight,
              EquipmentAccess.freeWeights,
            ],
          ),
        ),
        {EquipmentCategory.calisthenics, EquipmentCategory.smallGym},
      );
    });
  });

  group('ProgramSetup', () {
    ProgramSetup setup() => ProgramSetup(
      goal: TrainingGoal.getStronger,
      sessionDuration: SessionDuration.min45,
      focus: TrainingFocus.upperBody,
      muscles: musclesForFocus(TrainingFocus.upperBody),
      equipmentCategories: const {EquipmentCategory.smallGym},
      equipment: equipmentForCategories({EquipmentCategory.smallGym}),
    );

    test('every answer survives JSON', () {
      final back = ProgramSetup.fromJson(
        jsonDecode(jsonEncode(setup().toJson())) as Map<String, dynamic>,
      );
      expect(back.goal, TrainingGoal.getStronger);
      expect(back.sessionDuration, SessionDuration.min45);
      expect(back.focus, TrainingFocus.upperBody);
      expect(back.muscles, musclesForFocus(TrainingFocus.upperBody));
      expect(back.equipmentCategories, {EquipmentCategory.smallGym});
      expect(back.equipment, isNotEmpty);
    });

    test('muscles and equipment are stored as ids, not labels', () {
      final json = setup().toJson();
      expect(json['muscles'], contains('chest'));
      expect(json['muscles'], isNot(contains('Chest')));
      expect(json['focus'], 'upperBody');
    });

    test('unknown ids from a newer version are dropped, not fatal', () {
      final back = ProgramSetup.fromJson({
        'goal': 'buildMuscle',
        'sessionDuration': 'min60',
        'focus': 'fullBody',
        'muscles': ['chest', 'somethingNew'],
        'equipmentCategories': ['home', 'spaceStation'],
        'equipment': ['dumbbell', 'jetpack'],
      });
      expect(back.muscles, [MuscleGroup.chest]);
      expect(back.equipmentCategories, {EquipmentCategory.home});
      expect(back.equipment, [EquipmentItem.dumbbell]);
    });

    test('a program keeps its setup, and older programs simply have none', () {
      final program = TrainingProgram(
        id: 'p1',
        name: 'Plan',
        goal: TrainingGoal.getStronger,
        setup: setup(),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final back = TrainingProgram.fromJson(
        jsonDecode(jsonEncode(program.toJson())) as Map<String, dynamic>,
      );
      expect(back.setup!.focus, TrainingFocus.upperBody);
      expect(back.setup!.sessionDuration, SessionDuration.min45);

      // A duplicate carries the same answers.
      expect(program.duplicate().setup!.focus, TrainingFocus.upperBody);

      // Saved before setup existed.
      final old = TrainingProgram.fromJson({'id': 'old', 'name': 'Old'});
      expect(old.setup, isNull);
    });
  });

  // ---------------------------------------------------------------------
  group('the setup wizard', () {
    void useTallScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    /// Opens the wizard and takes the highlighted "Follow a training plan",
    /// leaving it on the first question.
    Future<void> openSetup(WidgetTester tester) async {
      seedAppData();
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
      await tapAndSettle(tester, find.byKey(const ValueKey('create-program')));
      expect(find.text('Set up program'), findsOneWidget);
      expect(find.text('Choose how to start'), findsOneWidget);
      await tapSetupContinue(tester);
    }

    /// Moves forward to the step whose title is [title].
    Future<void> goToStep(WidgetTester tester, String title) =>
        advanceSetupTo(tester, find.text(title));

    /// Opens the picker from a long-press and confirms it after [edit].
    Future<void> customise(
      WidgetTester tester,
      TrainingFocus focus,
      Future<void> Function() edit,
    ) async {
      await tester.longPress(setupFocusChip(focus));
      await tester.pumpAndSettle();
      await edit();
      await tapAndSettle(
        tester,
        find.byKey(const ValueKey('muscle-picker-done')),
      );
    }

    bool chipSelected(WidgetTester tester, Type chip, String label) {
      final widget = tester.widget(find.widgetWithText(chip, label).first);
      return widget is ChoiceChip
          ? widget.selected
          : (widget as FilterChip).selected;
    }

    String included(int count) => '$count muscles included';
    String includedOf(int count, int total) =>
        '$count muscles included of $total';

    const goalStep = 'What is the main goal for this program?';
    const durationStep = 'How long should a session be?';
    const focusStep = 'What should this program train?';
    const placesStep = 'What equipment can you train with?';
    const itemsStep = 'Which of these do you have?';

    final allMuscles = MuscleGroup.values.length;
    final upperCount = musclesForFocus(TrainingFocus.upperBody).length;
    final lowerCount = musclesForFocus(TrainingFocus.lowerBody).length;
    final pullCount = musclesForFocus(TrainingFocus.pull).length;

    testWidgets('one question per page, in order, starting from the profile', (
      tester,
    ) async {
      await openSetup(tester);

      expect(find.text(goalStep), findsOneWidget);
      expect(find.text(durationStep), findsNothing);
      expect(find.text('Step 1 of 7'), findsOneWidget);
      expect(chipSelected(tester, ChoiceChip, 'Build muscle'), isTrue);

      await tapSetupContinue(tester);
      expect(find.text(durationStep), findsOneWidget);
      expect(find.text(goalStep), findsNothing);
      expect(chipSelected(tester, ChoiceChip, '60 min'), isTrue);

      await tapSetupContinue(tester);
      expect(find.text(focusStep), findsOneWidget);
      expect(chipSelected(tester, ChoiceChip, 'Full body'), isTrue);
      expect(find.text(included(allMuscles)), findsOneWidget);

      await tapSetupContinue(tester);
      expect(find.text(placesStep), findsOneWidget);
      expect(chipSelected(tester, FilterChip, 'Commercial gym'), isTrue);
      expect(chipSelected(tester, FilterChip, 'Home equipment'), isFalse);

      await tapSetupContinue(tester);
      expect(find.text(itemsStep), findsOneWidget);

      await tapSetupContinue(tester);
      expect(find.text('Program structure'), findsOneWidget);

      // The structure step will not let you past until one is chosen.
      await tapAndSettle(tester, setupStructureTile(ProgramTemplate.custom));
      await tapSetupContinue(tester);
      expect(find.text('Name this program'), findsOneWidget);
      expect(find.text('Step 7 of 7'), findsOneWidget);
    });

    testWidgets('the session length step offers 15 minutes upward', (
      tester,
    ) async {
      await openSetup(tester);
      await goToStep(tester, durationStep);
      for (final label in ['15 min', '30 min', '45 min', '60 min', '90+ min']) {
        expect(
          find.widgetWithText(ChoiceChip, label),
          findsOneWidget,
          reason: label,
        );
      }
    });

    testWidgets('a tap picks a focus and takes all of its muscles', (
      tester,
    ) async {
      await openSetup(tester);
      await goToStep(tester, focusStep);

      await tapAndSettle(tester, find.widgetWithText(ChoiceChip, 'Upper body'));
      expect(chipSelected(tester, ChoiceChip, 'Upper body'), isTrue);
      expect(find.text(included(upperCount)), findsOneWidget);
      expect(find.textContaining('Chest'), findsWidgets);
      expect(find.textContaining('Quads'), findsNothing); // not upper body

      await tapAndSettle(tester, find.widgetWithText(ChoiceChip, 'Lower body'));
      expect(find.text(included(lowerCount)), findsOneWidget);
      expect(find.textContaining('Quads'), findsWidgets);
    });

    testWidgets(
      'long-pressing a focus opens its muscles and keeps the choice',
      (tester) async {
        await openSetup(tester);
        await goToStep(tester, focusStep);

        // Long-pressing Pull selects it as well as opening the picker.
        await tester.longPress(setupFocusChip(TrainingFocus.pull));
        await tester.pumpAndSettle();
        expect(find.text('Pull muscles'), findsOneWidget); // the sheet's title
        expect(find.widgetWithText(FilterChip, 'Biceps'), findsOneWidget);
        expect(find.widgetWithText(FilterChip, 'Chest'), findsNothing);

        await tapAndSettle(tester, find.widgetWithText(FilterChip, 'Biceps'));
        await tapAndSettle(
          tester,
          find.byKey(const ValueKey('muscle-picker-done')),
        );

        // The setup now holds the remaining pull muscles, not just "Pull".
        expect(chipSelected(tester, ChoiceChip, 'Pull muscles'), isTrue);
        expect(find.text(includedOf(pullCount - 1, pullCount)), findsOneWidget);
        expect(find.textContaining('Lats'), findsWidgets);
        expect(find.textContaining('Biceps'), findsNothing);
      },
    );

    testWidgets('dismissing the picker changes nothing', (tester) async {
      await openSetup(tester);
      await goToStep(tester, focusStep);
      expect(find.text(included(allMuscles)), findsOneWidget);

      await tester.longPress(setupFocusChip(TrainingFocus.fullBody));
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.widgetWithText(FilterChip, 'Chest'));
      await tester.tapAt(const Offset(10, 10)); // dismiss without confirming
      await tester.pumpAndSettle();

      expect(find.text(included(allMuscles)), findsOneWidget);
    });

    testWidgets('Choose muscles opens the picker straight away', (
      tester,
    ) async {
      await openSetup(tester);
      await goToStep(tester, focusStep);

      await tapAndSettle(
        tester,
        find.widgetWithText(ChoiceChip, 'Choose muscles'),
      );
      expect(find.widgetWithText(FilterChip, 'Lats'), findsOneWidget);
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Lats'))
            .selected,
        isFalse, // nothing preselected: the user picks deliberately
      );

      await tapAndSettle(tester, find.widgetWithText(FilterChip, 'Lats'));
      await tapAndSettle(tester, find.widgetWithText(FilterChip, 'Chest'));
      await tapAndSettle(
        tester,
        find.byKey(const ValueKey('muscle-picker-done')),
      );

      expect(find.text(included(2)), findsOneWidget);
    });

    testWidgets('Select all and Clear all work inside the picker', (
      tester,
    ) async {
      await openSetup(tester);
      await goToStep(tester, focusStep);

      await tester.longPress(setupFocusChip(TrainingFocus.lowerBody));
      await tester.pumpAndSettle();
      await tapAndSettle(
        tester,
        find.byKey(const ValueKey('muscle-picker-toggle-all')),
      );
      expect(find.text('Done (0 selected)'), findsOneWidget);
      await tapAndSettle(
        tester,
        find.byKey(const ValueKey('muscle-picker-toggle-all')),
      );
      expect(find.text('Done ($lowerCount selected)'), findsOneWidget);
      await tapAndSettle(
        tester,
        find.byKey(const ValueKey('muscle-picker-done')),
      );
      expect(find.text(included(lowerCount)), findsOneWidget);
    });

    testWidgets('the focus can still be changed after customising', (
      tester,
    ) async {
      await openSetup(tester);
      await goToStep(tester, focusStep);

      await customise(tester, TrainingFocus.pull, () async {
        await tapAndSettle(tester, find.widgetWithText(FilterChip, 'Biceps'));
      });
      expect(chipSelected(tester, ChoiceChip, 'Pull muscles'), isTrue);

      // A normal tap on another focus takes all of its muscles.
      await tapAndSettle(tester, find.widgetWithText(ChoiceChip, 'Upper body'));
      expect(chipSelected(tester, ChoiceChip, 'Upper body'), isTrue);
      expect(find.text(included(upperCount)), findsOneWidget);
      expect(find.textContaining('Biceps'), findsWidgets); // included again
    });

    testWidgets('the equipment step lists only the places chosen before it', (
      tester,
    ) async {
      await openSetup(tester);
      await goToStep(tester, itemsStep);

      // Commercial gym, from the profile.
      expect(find.widgetWithText(FilterChip, 'Machine'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Cable'), findsOneWidget);

      // Back a step and swap it for calisthenics.
      await tapAndSettle(tester, setupBackButton);
      await tapAndSettle(
        tester,
        find.widgetWithText(FilterChip, 'Commercial gym'),
      );
      await tapAndSettle(
        tester,
        find.widgetWithText(FilterChip, 'Calisthenics equipment'),
      );
      await tapSetupContinue(tester);

      expect(find.widgetWithText(FilterChip, 'Machine'), findsNothing);
      expect(find.widgetWithText(FilterChip, 'Pull-up bar'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Dip station'), findsOneWidget);
      expect(chipSelected(tester, FilterChip, 'Pull-up bar'), isTrue);
    });

    testWidgets('every answer is kept when stepping back and forward', (
      tester,
    ) async {
      await openSetup(tester);

      await tapAndSettle(
        tester,
        find.widgetWithText(ChoiceChip, 'Get stronger'),
      );
      await tapSetupContinue(tester);
      await tapAndSettle(tester, find.widgetWithText(ChoiceChip, '45 min'));
      await tapSetupContinue(tester);
      await tapAndSettle(tester, find.widgetWithText(ChoiceChip, 'Lower body'));
      await customise(tester, TrainingFocus.lowerBody, () async {
        await tapAndSettle(tester, find.widgetWithText(FilterChip, 'Calves'));
      });
      expect(find.text(includedOf(lowerCount - 1, lowerCount)), findsOneWidget);

      // Walk all the way back: nothing was lost.
      await tapAndSettle(tester, setupBackButton);
      expect(chipSelected(tester, ChoiceChip, '45 min'), isTrue);
      await tapAndSettle(tester, setupBackButton);
      expect(chipSelected(tester, ChoiceChip, 'Get stronger'), isTrue);
      expect(find.text('Step 1 of 7'), findsOneWidget);

      // And forward again.
      await tapSetupContinue(tester);
      await tapSetupContinue(tester);
      expect(chipSelected(tester, ChoiceChip, 'Lower body'), isTrue);
      expect(find.text(includedOf(lowerCount - 1, lowerCount)), findsOneWidget);
      expect(find.textContaining('Quads'), findsWidgets);
      expect(find.textContaining('Calves'), findsNothing);
    });

    testWidgets('a training plan is the highlighted start, and freestyle '
        'asks only the goal and a name', (tester) async {
      await openSetup(tester);
      await tapAndSettle(tester, setupBackButton);

      Card tile(String key) => tester.widget<Card>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Card),
        ),
      );
      bool picked(String key) =>
          (tile(key).shape! as RoundedRectangleBorder).side.color !=
          Colors.transparent;
      expect(picked('start-plan'), isTrue);
      expect(picked('start-freestyle'), isFalse);

      await tapAndSettle(tester, find.byKey(const ValueKey('start-freestyle')));
      expect(picked('start-freestyle'), isTrue);
      await tapSetupContinue(tester);

      // The goal still starts from the profile.
      expect(find.text(goalStep), findsOneWidget);
      expect(find.text('Step 1 of 2'), findsOneWidget);
      expect(chipSelected(tester, ChoiceChip, 'Build muscle'), isTrue);
      await tapSetupContinue(tester);
      expect(find.text('Step 2 of 2'), findsOneWidget);
      expect(find.text(durationStep), findsNothing);
      await tapSetupContinue(tester); // Generate program

      // An empty program to fill in, with no setup answers recorded.
      expect(find.text('Set up program'), findsNothing);
      expect(find.text('My Program'), findsWidgets);
    });

    testWidgets('Back on the first step leaves setup', (tester) async {
      await openSetup(tester);
      await tapAndSettle(tester, setupBackButton); // to "how to start"
      expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
      await tapAndSettle(tester, setupBackButton);
      expect(find.text('Set up program'), findsNothing);
      // seedAppData() creates no programs, so the tab shows its empty state.
      expect(find.text('No program yet.'), findsOneWidget);
    });

    testWidgets('an unanswered step explains itself and does not move on', (
      tester,
    ) async {
      await openSetup(tester);

      // Choose muscles, then confirm the picker with nothing ticked.
      await goToStep(tester, focusStep);
      await tapAndSettle(
        tester,
        find.widgetWithText(ChoiceChip, 'Choose muscles'),
      );
      await tapAndSettle(
        tester,
        find.byKey(const ValueKey('muscle-picker-done')),
      );
      await tapSetupContinue(tester);
      expect(find.text('Choose at least one muscle'), findsOneWidget);
      expect(find.text(placesStep), findsNothing); // stayed put

      await tapAndSettle(tester, find.byKey(const ValueKey('edit-muscles')));
      await tapAndSettle(tester, find.widgetWithText(FilterChip, 'Chest'));
      await tapAndSettle(
        tester,
        find.byKey(const ValueKey('muscle-picker-done')),
      );
      await tapSetupContinue(tester);
      expect(find.text(placesStep), findsOneWidget);

      // Nowhere to train.
      await tapAndSettle(
        tester,
        find.widgetWithText(FilterChip, 'Commercial gym'),
      );
      await tapSetupContinue(tester);
      expect(find.text('Choose where you train'), findsOneWidget);
      expect(find.text(itemsStep), findsNothing);

      // No structure.
      await tapAndSettle(
        tester,
        find.widgetWithText(FilterChip, 'Home equipment'),
      );
      await tapSetupContinue(tester);
      await tapSetupContinue(tester);
      expect(find.text('Program structure'), findsOneWidget);
      await tapSetupContinue(tester);
      expect(find.text('Choose a program structure'), findsOneWidget);

      // No name.
      await tapAndSettle(tester, setupStructureTile(ProgramTemplate.custom));
      await tapSetupContinue(tester);
      await tester.enterText(find.byKey(const ValueKey('program-name')), '');
      await tapSetupContinue(tester);
      expect(find.text('Enter a program name'), findsOneWidget);
      expect(
        find.text('New program'),
        findsNothing,
      ); // never reached the planner
    });

    testWidgets('a customised focus is what gets saved, not just its name', (
      tester,
    ) async {
      await openSetup(tester);

      await tapAndSettle(
        tester,
        find.widgetWithText(ChoiceChip, 'Get stronger'),
      );
      await tapSetupContinue(tester);
      await tapAndSettle(tester, find.widgetWithText(ChoiceChip, '45 min'));
      await tapSetupContinue(tester);
      await customise(tester, TrainingFocus.pull, () async {
        await tapAndSettle(tester, find.widgetWithText(FilterChip, 'Biceps'));
      });
      await completeProgramSetup(tester, template: ProgramTemplate.upperLower);

      // Straight into the planner, as before.
      expect(find.text('New program'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilterChip, 'Mon'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterChip, 'Upper').last);
      await tester.pump();
      await tapAndSettle(tester, find.text('Save program'));

      final saved = await tester.runAsync(() => ProgramRepository().load());
      final setup = saved!.programs.single.setup!;
      expect(setup.goal, TrainingGoal.getStronger);
      expect(setup.sessionDuration, SessionDuration.min45);
      expect(setup.focus, TrainingFocus.pull);
      // The muscles actually chosen, with Biceps left out.
      expect(setup.muscles, isNot(contains(MuscleGroup.biceps)));
      expect(setup.muscles, contains(MuscleGroup.lats));
      expect(setup.muscles.length, pullCount - 1);
      expect(setup.equipment, isNotEmpty);

      // The program detail reports what it was set up for.
      await tapAndSettle(tester, find.text('Upper Lower Program'));
      expect(find.text('Focus'), findsOneWidget);
      expect(find.text('Pull muscles'), findsOneWidget);
      expect(find.text('Muscles'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'Lats'), findsOneWidget);
    });
  });
}
