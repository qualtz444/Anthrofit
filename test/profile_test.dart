import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anthrofit/app.dart';
import 'package:anthrofit/data/profile_repository.dart';
import 'package:anthrofit/screens/profile/profile_setup_screen.dart';

import 'test_helpers.dart';

/// Tall test screen so the whole form is on screen and every field is tappable.
void useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> launchApp(WidgetTester tester) async {
  await tester.pumpWidget(AnthrofitApp(authService: FakeAuthService()));
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  // The edit form is taller than the test screen now (health, injury and
  // food questions), so scroll the target into view first.
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pump();
}


void main() {
  // The exercise catalogue is an asset now, so it has to be loaded.
  useExerciseLibrary();

  group('ProfileRepository', () {
    test('returns null when nothing is saved', () async {
      seedNoProfile();
      expect(await ProfileRepository().load(), isNull);
    });

    test('saves and loads every field', () async {
      seedNoProfile();
      final repo = ProfileRepository();
      await repo.save(sampleProfile);

      final loaded = await repo.load();
      expect(loaded, isNotNull);
      expect(loaded!.name, sampleProfile.name);
      expect(loaded.age, sampleProfile.age);
      expect(loaded.sex, sampleProfile.sex);
      expect(loaded.heightCm, sampleProfile.heightCm);
      expect(loaded.weightKg, sampleProfile.weightKg);
      expect(loaded.goal, sampleProfile.goal);
      expect(loaded.experience, sampleProfile.experience);
      expect(loaded.trainingFrequency, sampleProfile.trainingFrequency);
      expect(loaded.sessionDuration, sampleProfile.sessionDuration);
      expect(loaded.equipment, sampleProfile.equipment);
    });

    test('returns null for unreadable saved data', () async {
      SharedPreferences.setMockInitialValues({
        ProfileRepository.storageKey: 'not json',
      });
      expect(await ProfileRepository().load(), isNull);
    });
  });

  group('Profile setup', () {
    testWidgets('first launch shows setup instead of the app', (tester) async {
      seedNoProfile();
      useTallScreen(tester);
      await launchApp(tester);

      expect(find.byType(ProfileSetupScreen), findsOneWidget);
      expect(find.text('Set up your profile'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('setup asks one question per page, like program setup', (
      tester,
    ) async {
      seedNoProfile();
      useTallScreen(tester);
      await launchApp(tester);

      expect(find.textContaining('Step 1 of 15'), findsOneWidget);
      expect(find.text('What should we call you?'), findsOneWidget);
      expect(find.text('Main goal'), findsNothing); // a later page
      expect(find.byKey(const ValueKey('wizard-back')), findsNothing);

      await tester.enterText(find.byType(TextFormField).first, 'Test User');
      await tapSetupContinue(tester);
      expect(find.textContaining('Step 2 of 15'), findsOneWidget);
      expect(find.text('When were you born?'), findsOneWidget);
      expect(find.text('Age'), findsNothing); // asked as a date of birth only
    });

    testWidgets('Continue stops on an unanswered page and explains why', (
      tester,
    ) async {
      seedNoProfile();
      useTallScreen(tester);
      await launchApp(tester);

      await tapSetupContinue(tester);
      expect(find.text('Enter your name'), findsOneWidget);
      expect(find.textContaining('Step 1 of 15'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, 'Test User');
      await tapSetupContinue(tester);
      await tapSetupContinue(tester);
      expect(find.text('Select your date of birth'), findsOneWidget);
      expect(find.textContaining('Step 2 of 15'), findsOneWidget);

      await pickDateOfBirth(tester);
      await tapSetupContinue(tester);
      await tapSetupContinue(tester);
      expect(find.text('Choose one'), findsOneWidget);
      expect(find.textContaining('Step 3 of 15'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('Back keeps the answers already given', (tester) async {
      seedNoProfile();
      useTallScreen(tester);
      await launchApp(tester);

      await fillProfileSetup(tester, name: 'Ann');
      expect(find.textContaining('Step 15 of 15'), findsOneWidget);
      expect(find.text('Review your profile'), findsOneWidget);
      for (var i = 0; i < 14; i++) {
        await tester.tap(find.byKey(const ValueKey('wizard-back')));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('Step 1 of 15'), findsOneWidget);
      expect(find.text('Ann'), findsOneWidget);

      // Straight through again without answering anything twice.
      for (var i = 0; i < 8; i++) {
        await tapSetupContinue(tester);
      }
      expect(find.textContaining('Step 9 of 15'), findsOneWidget);
      final machines = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, 'Machines'),
      );
      expect(machines.selected, isTrue);
    });

    testWidgets('a completed form opens the app and is remembered on restart', (
      tester,
    ) async {
      seedNoProfile();
      useTallScreen(tester);
      await launchApp(tester);

      await fillProfileSetup(tester);
      await tapText(tester, 'Save profile');
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(ProfileSetupScreen), findsNothing);

      // "Restart": tear the app down and launch it again.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await launchApp(tester);

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(ProfileSetupScreen), findsNothing);
    });
  });

  group('Profile tab', () {
    testWidgets('shows the saved profile and lets the user edit it', (
      tester,
    ) async {
      seedSavedProfile();
      useTallScreen(tester);
      await launchApp(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Profile'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test User'), findsOneWidget);
      expect(find.text('65.5 kg'), findsOneWidget);
      expect(find.text('Machines · Cables'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Edit profile'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Edit profile'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, 'Changed Name');
      await tapText(tester, 'Save profile');
      await tester.pumpAndSettle();

      // Back on the Profile tab: the form is gone, but its own button remains.
      expect(find.widgetWithText(AppBar, 'Edit profile'), findsNothing);
      expect(find.text('Changed Name'), findsOneWidget);
    });
  });

  group('Profile page', () {
    Future<void> openProfile(WidgetTester tester) async {
      seedSavedProfile();
      useTallScreen(tester);
      await launchApp(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Profile'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a header with stats, and units that change every weight', (
      tester,
    ) async {
      await openProfile(tester);
      expect(find.byKey(const ValueKey('profile-header')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('profile-change-avatar')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('profile-stats')), findsOneWidget);
      expect(find.text('Workouts'), findsOneWidget);
      expect(find.text('Programs'), findsOneWidget);
      expect(find.text('Scans'), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-community')), findsOneWidget);
      expect(find.textContaining('ready to grow'), findsNothing);

      // Units: pounds for body weight and lifted weights alike.
      expect(find.text('65.5 kg'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('units-setting')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('units-weight')),
          matching: find.text('lb'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('units-save')));
      await tester.pumpAndSettle();
      expect(find.text('144.4 lb'), findsOneWidget);
      expect(find.textContaining('Weights in lb'), findsOneWidget);
    });

    testWidgets('Edit profile is sectioned, and opens the tapped section', (
      tester,
    ) async {
      await openProfile(tester);

      // Tapping the goal opens Edit profile on Goals and training.
      await tester.tap(find.text('Build muscle'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Edit profile'), findsOneWidget);
      for (final section in ProfileEditSection.values) {
        expect(
          find.byKey(ValueKey('edit-section-${section.name}')),
          findsOneWidget,
          reason: section.label,
        );
      }
      // Basic information is folded; Goals and training is open.
      expect(find.byType(TextFormField), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Get stronger'), findsOneWidget);
      // Save is always on screen.
      expect(find.widgetWithText(FilledButton, 'Save profile'), findsOneWidget);
    });
  });
}
