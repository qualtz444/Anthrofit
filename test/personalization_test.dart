import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/app.dart';
import 'package:anthrofit/data/exercise_library.dart';
import 'package:anthrofit/data/measurement_repository.dart';
import 'package:anthrofit/data/program_repository.dart';
import 'package:anthrofit/data/setup_options.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/recommendation/personalization_service.dart';
import 'package:anthrofit/recommendation/program_recommender.dart';
import 'package:anthrofit/recommendation/proportion_rules.dart';
import 'package:anthrofit/scan/mock_scan_source.dart';
import 'package:anthrofit/screens/program/program_detail_screen.dart';
import 'package:anthrofit/screens/scan/personalize_program_screen.dart';
import 'package:anthrofit/screens/scan/scan_result_screen.dart';
import 'package:anthrofit/state/measurement_scope.dart';

import 'test_helpers.dart';

TrainingProgram _programWithSetup({ProgramSetup? setup}) => TrainingProgram(
  id: 'mine',
  name: 'My Plan',
  setup: setup,
  workouts: [
    Workout(
      id: 'mine-w',
      name: 'Upper A',
      exercises: [testPlanned('mine-p', 'machine_chest_press')],
    ),
  ],
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

ProgramSetup _strengthSetup() => const ProgramSetup(
  goal: TrainingGoal.getStronger,
  sessionDuration: SessionDuration.min45,
  focus: TrainingFocus.upperBody,
  muscles: [MuscleGroup.chest, MuscleGroup.lats],
  equipmentCategories: {EquipmentCategory.smallGym},
  equipment: [EquipmentItem.dumbbell, EquipmentItem.barbell],
);

void main() {
  useExerciseLibrary();

  // ---------------------------------------------------------------------
  group('resolving the setup', () {
    test('the active program\'s setup is preferred over the profile', () {
      final resolved = resolveSetup(
        profile: sampleProfile, // build muscle, 60 min, machines and cables
        activeProgram: _programWithSetup(setup: _strengthSetup()),
      );
      expect(resolved.source, SetupSource.activeProgram);
      expect(resolved.setup.goal, TrainingGoal.getStronger);
      expect(resolved.setup.sessionDuration, SessionDuration.min45);
      expect(resolved.setup.focus, TrainingFocus.upperBody);
      expect(resolved.setup.muscles, [MuscleGroup.chest, MuscleGroup.lats]);
      expect(resolved.setup.equipment, [
        EquipmentItem.dumbbell,
        EquipmentItem.barbell,
      ]);
    });

    test('the profile is used when there is no active program', () {
      final resolved = resolveSetup(profile: sampleProfile);
      expect(resolved.source, SetupSource.profile);
      expect(resolved.setup.goal, sampleProfile.goal);
      expect(resolved.setup.sessionDuration, sampleProfile.sessionDuration);
      // Machines and cables map to a commercial gym, as in the wizard.
      expect(resolved.setup.equipmentCategories, {
        EquipmentCategory.commercialGym,
      });
      expect(
        resolved.setup.equipment,
        equipmentForCategories({EquipmentCategory.commercialGym}),
      );
    });

    test('a program with no setup, or an unusable one, falls back', () {
      // A program from the Library has no setup answers at all.
      expect(
        resolveSetup(
          profile: sampleProfile,
          activeProgram: _programWithSetup(),
        ).source,
        SetupSource.profile,
      );
      // One that names no equipment could only give an empty program.
      expect(
        resolveSetup(
          profile: sampleProfile,
          activeProgram: _programWithSetup(
            setup: _strengthSetup().copyWith(equipment: const []),
          ),
        ).source,
        SetupSource.profile,
      );
      expect(
        resolveSetup(
          profile: sampleProfile,
          activeProgram: _programWithSetup(
            setup: _strengthSetup().copyWith(muscles: const []),
          ),
        ).source,
        SetupSource.profile,
      );
    });

    test('the focus defaults to full body, covering every muscle', () {
      final setup = resolveSetup(profile: sampleProfile).setup;
      expect(setup.focus, TrainingFocus.fullBody);
      expect(setup.muscles, MuscleGroup.values);
    });
  });

  // ---------------------------------------------------------------------
  group('what the preview says about the scan', () {
    test('without proportions it says plainly that the scan was not used', () {
      final words = describeScanInfluence(usedProportions: false);
      expect(words.headline, "Your body scan wasn't used");
      expect(words.detail, contains('from your profile only'));
      expect(words.usedScan, isFalse);

      // And never hints that the scan mattered.
      final all = '${words.headline} ${words.detail}'.toLowerCase();
      expect(all, isNot(contains('considered')));
      expect(all, isNot(contains('used your scan')));
    });

    test('when the scan changed something, it says exactly what', () {
      final words = describeScanInfluence(
        usedProportions: true,
        tipExercises: ['Leg Press', 'Goblet Squat'],
        changedPicks: 1,
      );
      expect(words.headline, 'Used your scan');
      expect(
        words.detail,
        'Setup tips from your proportions for 2 exercises: Leg Press, '
        'Goblet Squat. 1 exercise differs from the program you would get '
        'without your scan.',
      );
      expect(words.usedScan, isTrue);
    });

    test('a scan that changed nothing says so, not that it was used', () {
      final words = describeScanInfluence(usedProportions: true);
      expect(words.headline, "Your scan didn't change this program");
      expect(words.detail, contains('same as it would be without a scan'));
    });

    test('the wording follows the recommender, not a hardcoded state', () {
      Measurement scan() => mockMeasurement();

      // With no thresholds, the scan changes nothing.
      final off = personalizeProgram(
        profile: sampleProfile,
        measurement: scan(),
        recommender: const ProgramRecommender(),
      );
      expect(off.succeeded, isTrue);
      expect(off.recommended!.usedProportions, isFalse);
      expect(
        describeScanInfluence(
          usedProportions: off.recommended!.usedProportions,
        ).headline,
        "Your body scan wasn't used",
      );
      // The program itself records it, for its page later.
      expect(off.recommended!.program.usedScan, isFalse);
      expect(off.recommended!.program.scanTakenAt, isNull);

      // Later: thresholds exist, and the same call reports it.
      const thresholds = ProportionThresholds({
        RatioKeys.femurToTorso: RatioThreshold(low: 0.95, high: 1.05),
      });
      final on = personalizeProgram(
        profile: sampleProfile,
        measurement: scan(),
        recommender: const ProgramRecommender(thresholds: thresholds),
      );
      expect(on.recommended!.usedProportions, isTrue);
      // The headline follows what the scan actually changed.
      final r = on.recommended!;
      expect(
        describeScanInfluence(
          usedProportions: true,
          tipExercises: r.scanTipExercises,
          changedPicks: r.scanChangedPicks,
        ).headline,
        r.scanChangedProgram
            ? 'Used your scan'
            : "Your scan didn't change this program",
      );
      expect(r.program.scanChanged, r.scanChangedProgram);
      final saved = TrainingProgram.fromJson(
        on.recommended!.program.toJson(),
      );
      expect(saved.usedScan, isTrue);
      expect(saved.scanTakenAt, isNotNull);
    });

    test('a scan no rule has advice for changes nothing, and says so', () {
      // Every rule only has advice for a HIGH ratio. A femur:torso ratio
      // below these cut-offs is LOW, so no rule fires.
      const thresholds = ProportionThresholds({
        RatioKeys.femurToTorso: RatioThreshold(low: 1.5, high: 2.0),
      });
      final r = personalizeProgram(
        profile: sampleProfile,
        measurement: mockMeasurement(),
        recommender: const ProgramRecommender(thresholds: thresholds),
      ).recommended!;
      expect(r.usedProportions, isTrue);
      expect(r.scanTipExercises, isEmpty);
      expect(r.scanChangedPicks, 0);
      expect(r.scanChangedProgram, isFalse);
      expect(r.program.scanChanged, isFalse);
    });
  });

  // ---------------------------------------------------------------------
  group('building the program', () {
    test('a profile alone is enough, with no scan', () {
      final outcome = personalizeProgram(profile: sampleProfile);
      expect(outcome.succeeded, isTrue);
      expect(outcome.source, SetupSource.profile);
      expect(outcome.recommended!.program.workouts, isNotEmpty);
      expect(outcome.recommended!.usedProportions, isFalse);
    });

    test('an incomplete profile fails with a message, not an exception', () {
      final outcome = personalizeProgram(profile: null);
      expect(outcome.succeeded, isFalse);
      expect(outcome.failure, contains('profile'));
    });

    test('a missing catalogue fails gracefully, with no fallback list', () {
      ExerciseLibrary.clear();
      expect(ExerciseLibrary.isLoaded, isFalse);

      final outcome = personalizeProgram(profile: sampleProfile);
      expect(outcome.succeeded, isFalse);
      expect(outcome.failure, kCatalogUnavailable);

      // The controller's own message wins when it has one.
      expect(
        personalizeProgram(
          profile: sampleProfile,
          catalogError: 'Offline catalogue',
        ).failure,
        'Offline catalogue',
      );
    });

    test(
      'equipment that allows nothing fails rather than saving an empty one',
      () {
        final outcome = personalizeProgram(
          profile: sampleProfile,
          activeProgram: _programWithSetup(
            setup: _strengthSetup().copyWith(
              focus: TrainingFocus.chooseMuscles,
              muscles: const [MuscleGroup.traps],
              equipment: const [EquipmentItem.smithMachine],
            ),
          ),
        );
        expect(outcome.succeeded, isFalse);
        expect(outcome.failure, isNotEmpty);
      },
    );
  });

  // ---------------------------------------------------------------------
  group('the flow on screen', () {
    void useTallScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Future<void> launch(WidgetTester tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(AnthrofitApp(authService: FakeAuthService()));
      await tester.pumpAndSettle();
    }

    BuildContext appContext(WidgetTester tester) =>
        // skipOffstage: false, because a pushed screen (Program detail)
        // covers the shell and hides its NavigationBar from the finder.
        tester.element(find.byType(NavigationBar, skipOffstage: false));

    /// Shows the scan result the way the scan screen does.
    Future<void> openResult(WidgetTester tester) async {
      Navigator.of(appContext(tester)).push(
        MaterialPageRoute<void>(
          builder: (_) => ScanResultScreen(measurement: mockMeasurement()),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Taps the button and lets the route settle, but not the transition's
    /// own timer: a spinner never lets pumpAndSettle finish.
    Future<void> tapPersonalize(WidgetTester tester) async {
      await tester.tap(find.text('Personalize My Program'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// Runs out the transition and lets the preview appear.
    Future<void> finishTransition(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    }

    testWidgets('the result offers it, but nothing starts by itself', (
      tester,
    ) async {
      seedSavedProfile();
      await launch(tester);
      await openResult(tester);

      expect(find.text('Personalize My Program'), findsOneWidget);
      expect(find.text('Building your personalized plan…'), findsNothing);
      final saved = await tester.runAsync(() => ProgramRepository().load());
      expect(saved!.programs, isEmpty);
    });

    testWidgets('tapping it starts the workflow with a transition', (
      tester,
    ) async {
      seedSavedProfile();
      await launch(tester);
      await openResult(tester);

      await tapPersonalize(tester);
      expect(find.text('Building your personalized plan…'), findsOneWidget);
      expect(
        find.text(
          'A training program from your current setup, and nutrition '
          'targets from your profile.',
        ),
        findsOneWidget,
      );
      // Still nothing saved: the transition builds, it does not store.
      final saved = await tester.runAsync(() => ProgramRepository().load());
      expect(saved!.programs, isEmpty);

      await finishTransition(tester);
      expect(find.text('Your personalized plan'), findsOneWidget);
    });

    testWidgets('after a scan, the preview says the scan was used', (
      tester,
    ) async {
      // The app's recommender has the participant cut-offs, so a scan
      // personalizes the program.
      seedSavedProfile();
      await launch(tester);
      await openResult(tester);
      await tapPersonalize(tester);
      await finishTransition(tester);

      // Used: either it changed something, or it says it changed nothing.
      expect(
        find.textContaining(
          RegExp(r"^(Used your scan|Your scan didn't change this program)$"),
        ),
        findsOneWidget,
      );
      expect(find.text("Your body scan wasn't used"), findsNothing);
      expect(find.text('Using your profile settings.'), findsOneWidget);
    });

    test('the app uses the participant cut-offs', () {
      expect(kAppRecommender.thresholds, ProportionThresholds.participants);
      final none = personalizeProgram(profile: sampleProfile);
      expect(none.recommended!.usedProportions, isFalse); // no scan, no use
    });

    testWidgets('when proportions are used, the preview says so', (
      tester,
    ) async {
      seedSavedProfile();
      await launch(tester);

      const thresholds = ProportionThresholds({
        RatioKeys.femurToTorso: RatioThreshold(low: 0.95, high: 1.05),
      });
      Navigator.of(appContext(tester)).push(
        MaterialPageRoute<void>(
          builder: (_) => PersonalizeProgramScreen(
            measurement: mockMeasurement(),
            recommender: const ProgramRecommender(thresholds: thresholds),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await finishTransition(tester);

      // Used: either it changed something, or it says it changed nothing.
      expect(
        find.textContaining(
          RegExp(r"^(Used your scan|Your scan didn't change this program)$"),
        ),
        findsOneWidget,
      );
      expect(find.text("Your body scan wasn't used"), findsNothing);
    });

    testWidgets('proceeding saves the program, activates it and opens it', (
      tester,
    ) async {
      seedSavedProfile();
      await launch(tester);
      await openResult(tester);
      await tapPersonalize(tester);
      await finishTransition(tester);
      expect(find.text('It will become your active program.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('plan-confirm')));
      await tester.pumpAndSettle();

      // Confirmed, and still on the plan until the user leaves it.
      expect(find.byKey(const ValueKey('plan-confirmed')), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-confirm')), findsNothing);
      expect(find.byType(ProgramDetailScreen), findsNothing);
      final saved = await tester.runAsync(() => ProgramRepository().load());
      expect(saved!.programs.length, 1);
      expect(saved.activeProgramId, saved.programs.single.id);
      expect(saved.programs.single.workouts, isNotEmpty);
      expect(saved.programs.single.setup, isNotNull);

      await tester.tap(find.byKey(const ValueKey('plan-open-program')));
      await tester.pumpAndSettle();
      expect(find.byType(ProgramDetailScreen), findsOneWidget);
    });

    testWidgets('the plan has Training and Nutrition tabs, before and after '
        'confirming', (tester) async {
      seedSavedProfile();
      await launch(tester);
      await openResult(tester);
      await tapPersonalize(tester);
      await finishTransition(tester);

      // Training: the week, and each exercise's sets, reps and swaps.
      expect(find.byKey(const ValueKey('weekly-schedule')), findsOneWidget);
      expect(find.text('Rest'), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('prescription-'),
        ),
        findsWidgets,
      );
      expect(find.textContaining('Swap for: '), findsWidgets);

      Future<void> openTab(String key) async {
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
      }

      // Nutrition: the targets card and example meals, on the same page.
      await openTab('plan-tab-nutrition');
      expect(find.byKey(const ValueKey('nutrition-targets')), findsOneWidget);
      expect(find.text('Sample meals'), findsOneWidget);
      expect(find.text('Breakfast'), findsOneWidget);
      expect(find.byKey(const ValueKey('sample-day')), findsNothing);
      // The daily targets appear once, in the card, not again with the meals.
      expect(
        find.text('DAILY MACROS').evaluate().length,
        lessThanOrEqualTo(1),
      );

      // Confirm from the Nutrition tab; both tabs are still there after.
      await tester.tap(find.byKey(const ValueKey('plan-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plan-confirmed')), findsOneWidget);
      expect(find.byKey(const ValueKey('nutrition-targets')), findsOneWidget);
      await openTab('plan-tab-training');
      expect(find.byKey(const ValueKey('weekly-schedule')), findsOneWidget);
      expect(find.byKey(const ValueKey('save-mode-note')), findsNothing);
      await openTab('plan-tab-nutrition');
      expect(find.text('Sample meals'), findsOneWidget);
      expect(find.text('Your personalized plan'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('plan-done')));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('an active program stays active when another is added', (
      tester,
    ) async {
      seedProfileAndPrograms([
        _programWithSetup(setup: _strengthSetup()),
      ], activeProgramId: 'mine');
      await launch(tester);
      await openResult(tester);
      await tapPersonalize(tester);
      await finishTransition(tester);

      // The existing program's setup is the one reused.
      expect(
        find.text('Using the settings from your current program.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('My Plan stays your active program'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('plan-confirm')));
      await tester.pumpAndSettle();

      final saved = await tester.runAsync(() => ProgramRepository().load());
      expect(saved!.programs.length, 2);
      expect(saved.activeProgramId, 'mine'); // not silently replaced
      // The existing program is untouched.
      final mine = saved.programs.firstWhere((p) => p.id == 'mine');
      expect(mine.workouts.single.exercises.length, 1);
    });

    testWidgets('Replace current makes the new program active and archives '
        'the old one', (tester) async {
      seedProfileAndPrograms([
        _programWithSetup(setup: _strengthSetup()),
      ], activeProgramId: 'mine');
      await launch(tester);
      await openResult(tester);
      await tapPersonalize(tester);
      await finishTransition(tester);

      final choice = find.text('Replace current');
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('save-mode-note')))
            .data,
        contains('archived, not deleted'),
      );

      await tester.tap(find.byKey(const ValueKey('plan-confirm')));
      await tester.pumpAndSettle();

      final saved = await tester.runAsync(() => ProgramRepository().load());
      expect(saved!.programs.length, 2);
      final added = saved.programs.firstWhere((p) => p.id != 'mine');
      expect(saved.activeProgramId, added.id);
      final mine = saved.programs.firstWhere((p) => p.id == 'mine');
      expect(mine.archived, isTrue); // kept, not deleted
    });

    testWidgets('a program can be rebuilt in place from the latest scan', (
      tester,
    ) async {
      seedProfileAndPrograms([
        _programWithSetup(setup: _strengthSetup()),
      ], activeProgramId: 'mine');
      await launch(tester);

      // Without a scan, it says to scan first.
      Navigator.of(appContext(tester)).push(
        MaterialPageRoute<void>(
          builder: (_) => const ProgramDetailScreen(programId: 'mine'),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('personalize-with-scan'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.textContaining('Do a body proportion scan first'), findsOneWidget);

      // With one, it previews and updates the same program.
      await MeasurementScope.of(
        appContext(tester),
        listen: false,
      ).add(mockMeasurement());
      await tester.pumpAndSettle();
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      await finishTransition(tester);

      expect(find.byKey(const ValueKey('update-note')), findsOneWidget);
      expect(find.byKey(const ValueKey('save-mode')), findsNothing);
      await tester.tap(find.text('Update My Plan'));
      await tester.pumpAndSettle();

      final saved = await tester.runAsync(() => ProgramRepository().load());
      expect(saved!.programs.length, 1); // no new program
      final mine = saved.programs.single;
      expect(mine.id, 'mine');
      expect(mine.name, 'My Plan');
      expect(saved.activeProgramId, 'mine');
      // The hand-built single workout was replaced by the rebuilt ones.
      expect(mine.workouts.any((w) => w.id == 'mine-w'), isFalse);
      expect(mine.workouts, isNotEmpty);
      expect(find.text('My Plan updated.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('plan-open-program')));
      await tester.pumpAndSettle();
      expect(find.byType(ProgramDetailScreen), findsOneWidget);
    });

    testWidgets('Back to Home keeps the scan and saves no program', (
      tester,
    ) async {
      seedSavedProfile();
      await launch(tester);

      // A saved scan, as the scan screen would have left it.
      final scan = mockMeasurement();
      await MeasurementScope.of(appContext(tester), listen: false).add(scan);

      await openResult(tester);
      await tapPersonalize(tester);
      await finishTransition(tester);
      await tester.tap(find.text('Back to Home'));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Your personalized plan'), findsNothing);

      final scans = await tester.runAsync(() => MeasurementRepository().load());
      expect(scans!.single.id, scan.id);
      final programs = await tester.runAsync(() => ProgramRepository().load());
      expect(programs!.programs, isEmpty);
    });

    testWidgets('backing out mid-transition cancels cleanly', (tester) async {
      seedSavedProfile();
      await launch(tester);
      await openResult(tester);
      await tapPersonalize(tester);
      expect(find.text('Building your personalized plan…'), findsOneWidget);

      await tester.tap(find.byTooltip('Back').last);
      await tester.pumpAndSettle();
      // The timer is gone, so nothing appears later and nothing throws.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.text('Your personalized plan'), findsNothing);
      expect(find.text('Scan result'), findsOneWidget);
      final saved = await tester.runAsync(() => ProgramRepository().load());
      expect(saved!.programs, isEmpty);
    });

    testWidgets('a missing catalogue shows a message and a way home', (
      tester,
    ) async {
      seedSavedProfile();
      await launch(tester);
      await openResult(tester);

      // The catalogue disappears after the app has started.
      ExerciseLibrary.clear();
      await tester.tap(find.text('Personalize My Program'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't build a program"), findsOneWidget);
      expect(find.text(kCatalogUnavailable), findsOneWidget);
      expect(find.text('Building your personalized plan…'), findsNothing);

      await tester.tap(find.text('Back to Home'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('an empty scan does not offer to personalize', (tester) async {
      seedSavedProfile();
      await launch(tester);
      Navigator.of(appContext(tester)).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ScanResultScreen(measurement: Measurement.fromNative(const {})),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Personalize My Program'), findsNothing);
      expect(find.text('Done'), findsOneWidget);
    });
  });
}
