import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anthrofit/app.dart';
import 'package:anthrofit/auth/auth_service.dart';
import 'package:anthrofit/data/profile_repository.dart';
import 'package:anthrofit/data/program_repository.dart';
import 'package:anthrofit/data/session_repository.dart';
import 'package:anthrofit/data/storage_scope.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/screens/profile/profile_setup_screen.dart';

import 'test_helpers.dart';

TrainingProgram _program(String id, String name) => TrainingProgram(
  id: id,
  name: name,
  goal: TrainingGoal.buildMuscle,
  workouts: [
    Workout(
      id: '$id-w',
      name: 'Upper A',
      exercises: [testPlanned('$id-p', 'machine_chest_press')],
    ),
  ],
  schedule: [ScheduledWorkout(day: Weekday.monday, workoutId: '$id-w')],
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

/// The raw saved entries for one owner (an account or the guest).
Map<String, Object> _entries(
  StorageScope scope, {
  required UserProfile profile,
  TrainingProgram? program,
  WorkoutSession? unfinished,
}) => {
  scope.key(ProfileRepository.storageKey): jsonEncode(profile.toJson()),
  if (program != null)
    scope.key(ProgramRepository.storageKey): jsonEncode({
      'activeProgramId': program.id,
      'programs': [program.toJson()],
    }),
  if (unfinished != null)
    scope.key(SessionRepository.storageKey): jsonEncode({
      'activeSession': unfinished.toJson(),
      'sessions': <dynamic>[],
    }),
};

WorkoutSession _unfinished(String workoutName) => WorkoutSession(
  id: 'active-$workoutName',
  programName: 'Plan',
  workoutId: 'w',
  workoutName: workoutName,
  startedAt: DateTime(2026, 1, 2, 9),
  exerciseLogs: [
    ExerciseLog.fromPlanned(testPlanned('p', 'leg_press'), 'Leg Press'),
  ],
);

void main() {
  // The exercise catalogue is an asset now, so it has to be loaded.
  useExerciseLibrary();

  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> launch(WidgetTester tester, FakeAuthService service) async {
    await tester.pumpWidget(AnthrofitApp(authService: service));
    await tester.pumpAndSettle();
  }

  Future<void> restart(WidgetTester tester, FakeAuthService service) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await launch(tester, service);
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String label) => tapAndSettle(
    tester,
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );

  Future<void> tapContinue(WidgetTester tester) =>
      tapAndSettle(tester, find.widgetWithText(FilledButton, 'Continue'));

  /// Create Account step 1: email, password, confirm password.
  Future<void> fillAccountStep(
    WidgetTester tester, {
    String email = 'ann@example.com',
    String password = 'S3cret!Pw',
    String? confirm,
  }) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), email);
    await tester.enterText(fields.at(1), password);
    await tester.enterText(fields.at(2), confirm ?? password);
    await tester.pump();
  }

  /// Create Account step 2: names and date of birth.
  Future<void> fillPersonalStep(
    WidgetTester tester, {
    String first = 'Ann',
    String last = 'Lee',
    bool dateOfBirth = true,
  }) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), first);
    await tester.enterText(fields.at(1), last);
    if (dateOfBirth) await pickDateOfBirth(tester, key: 'signup-dob-field');
  }

  /// Ticks the terms box, which opens both documents, then scrolls to the
  /// end and taps "I agree".
  Future<void> agreeToTerms(WidgetTester tester) async {
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('legal-scroll')),
      const Offset(0, -20000),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('legal-agree')));
    await tester.pumpAndSettle();
  }

  /// Welcome -> Create Account: steps 1 and 2, then ticks the terms on the
  /// review step. The caller taps Create Account.
  Future<void> fillSignUp(WidgetTester tester, {bool accept = true}) async {
    await fillAccountStep(tester);
    await tapContinue(tester);
    await fillPersonalStep(tester);
    await tapContinue(tester);
    if (accept) await agreeToTerms(tester);
  }

  // ---------------------------------------------------------------------
  group('Welcome and guest mode', () {
    testWidgets('a new install shows Welcome with the three choices', (
      tester,
    ) async {
      seedFreshInstall();
      useTallScreen(tester);
      await launch(tester, FakeAuthService());

      expect(find.text('Welcome to ANTHROFIT'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Create Account'), findsOneWidget);
      expect(find.text('or'), findsOneWidget);
      expect(find.text('Continue without an account'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('the logo is on Welcome, Sign In and Create Account', (
      tester,
    ) async {
      seedFreshInstall();
      useTallScreen(tester);
      await launch(tester, FakeAuthService());
      final logo = find.bySemanticsLabel('ANTHROFIT logo');
      expect(logo, findsOneWidget);
      expect(
        tester.getTopLeft(logo).dy <
            tester.getTopLeft(find.text('Welcome to ANTHROFIT')).dy,
        isTrue,
      ); // above the heading

      await tapAndSettle(tester, find.text('Sign In'));
      expect(logo, findsOneWidget);
      await tapAndSettle(tester, find.text('Create Account'));
      expect(find.text('Create your account'), findsOneWidget);
      expect(logo, findsOneWidget);
    });

    testWidgets(
      'Continue without an account: setup, then the app, no Firebase',
      (tester) async {
        seedFreshInstall();
        useTallScreen(tester);
        final service = FakeAuthService();
        await launch(tester, service);

        await tapAndSettle(tester, find.text('Continue without an account'));
        expect(find.byType(ProfileSetupScreen), findsOneWidget);
        expect(find.text('Set up your profile'), findsOneWidget);

        await fillProfileSetup(tester, name: 'Guest Gary');
        await tapAndSettle(tester, find.text('Save profile'));

        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.textContaining('Guest Gary'), findsOneWidget);
        expect(service.calls, isEmpty); // no sign-in, no anonymous account
      },
    );

    testWidgets('guest mode and guest data survive a restart', (tester) async {
      seedFreshInstall();
      useTallScreen(tester);
      final service = FakeAuthService();
      await launch(tester, service);
      await tapAndSettle(tester, find.text('Continue without an account'));
      await fillProfileSetup(tester, name: 'Guest Gary');
      await tapAndSettle(tester, find.text('Save profile'));

      await restart(tester, service);
      expect(find.text('Welcome to ANTHROFIT'), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.textContaining('Guest Gary'), findsOneWidget);
    });

    testWidgets('Guest Profile offers to create an account or sign in', (
      tester,
    ) async {
      seedSavedProfile();
      useTallScreen(tester);
      await launch(tester, FakeAuthService());
      await openTab(tester, 'Profile');

      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Guest Mode'), findsOneWidget);
      expect(find.text('Create Account'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Training profile'), findsOneWidget);
      expect(find.text('Sign Out'), findsNothing);
    });

    testWidgets('Firebase unavailable: Welcome says so and Guest still works', (
      tester,
    ) async {
      seedFreshInstall();
      useTallScreen(tester);
      await launch(tester, FakeAuthService(initializeFails: true));
      expect(find.textContaining('Accounts are unavailable'), findsOneWidget);
      await tapAndSettle(tester, find.text('Continue without an account'));
      expect(find.byType(ProfileSetupScreen), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------
  group('starting up in each state', () {
    testWidgets('signed in and unverified -> Verify your email', (
      tester,
    ) async {
      seedFreshInstall();
      useTallScreen(tester);
      final service = FakeAuthService()
        ..addAccount('ann@example.com', 's3cretPw', verified: false)
        ..startSignedIn('ann@example.com');
      await launch(tester, service);

      expect(find.text('Verify your email'), findsOneWidget);
      expect(find.text('ann@example.com'), findsOneWidget);
      expect(find.text('Welcome to ANTHROFIT'), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets(
      'signed in, verified, no profile yet -> Profile Setup with the name filled in',
      (tester) async {
        seedFreshInstall();
        useTallScreen(tester);
        final service = FakeAuthService()
          ..addAccount('ann@example.com', 's3cretPw', displayName: 'Ann Lee')
          ..startSignedIn('ann@example.com');
        await launch(tester, service);

        expect(find.byType(ProfileSetupScreen), findsOneWidget);
        final nameBox = tester.widget<TextFormField>(
          find.byType(TextFormField).first,
        );
        expect(nameBox.controller!.text, 'Ann Lee');
        // The date of birth from sign-up starts profile setup off.
        expect(
          tester
              .widget<ProfileSetupScreen>(find.byType(ProfileSetupScreen))
              .suggestedDateOfBirth,
          isNotNull,
        ); // not asked twice
      },
    );

    testWidgets('signed in, verified, with a profile -> Home', (tester) async {
      final scope = StorageScope.user('uid_ann');
      SharedPreferences.setMockInitialValues(
        _entries(scope, profile: sampleProfile.copyWith(name: 'Ann Lee')),
      );
      useTallScreen(tester);
      final service = FakeAuthService()
        ..addAccount('ann@example.com', 's3cretPw', displayName: 'Ann Lee')
        ..startSignedIn('ann@example.com');
      await launch(tester, service);

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.textContaining('Ann Lee'), findsOneWidget);
    });

    testWidgets('a loading screen is shown first, never the wrong screen', (
      tester,
    ) async {
      seedFreshInstall();
      useTallScreen(tester);
      await tester.pumpWidget(AnthrofitApp(authService: FakeAuthService()));
      // Before startup finishes: loading only.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Welcome to ANTHROFIT'), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('Welcome to ANTHROFIT'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------
  group('create account', () {
    Future<void> openSignUp(WidgetTester tester) async {
      seedFreshInstall();
      useTallScreen(tester);
    }

    testWidgets('each step checks its own fields before Continue', (
      tester,
    ) async {
      await openSignUp(tester);
      final service = FakeAuthService();
      await launch(tester, service);
      await tapAndSettle(tester, find.text('Create Account'));
      expect(find.text('Create your account'), findsOneWidget);
      expect(find.text('Step 1 of 3'), findsOneWidget);

      await tapContinue(tester);
      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Enter a password'), findsOneWidget);
      expect(find.text('Confirm your password'), findsOneWidget);
      expect(find.text('Step 1 of 3'), findsOneWidget); // did not move on

      await fillAccountStep(tester);
      await tapContinue(tester);
      expect(find.text('Step 2 of 3'), findsOneWidget);

      await tapContinue(tester);
      expect(find.text('Enter your first name'), findsOneWidget);
      expect(find.text('Enter your last name'), findsOneWidget);
      expect(find.text('Select your date of birth'), findsOneWidget);
      expect(find.text('Step 2 of 3'), findsOneWidget);

      await fillPersonalStep(tester);
      await tapContinue(tester);
      expect(find.text('Step 3 of 3'), findsOneWidget);

      await tapAndSettle(
        tester,
        find.widgetWithText(FilledButton, 'Create Account'),
      );
      expect(
        find.text('Please accept the Terms of Service and Privacy Policy'),
        findsOneWidget,
      );
      expect(service.calls, isEmpty); // nothing was sent to Firebase
    });

    testWidgets(
      'bad email, weak password and mismatched passwords are explained',
      (tester) async {
        await openSignUp(tester);
        final service = FakeAuthService();
        await launch(tester, service);
        await tapAndSettle(tester, find.text('Create Account'));

        await fillAccountStep(
          tester,
          email: 'not-an-email',
          password: 'abc',
          confirm: 'abcd',
        );
        await tapContinue(tester);
        expect(find.text('Enter a valid email address'), findsOneWidget);
        expect(
          find.text('Password does not meet all the requirements'),
          findsOneWidget,
        );
        expect(find.text('Passwords do not match'), findsOneWidget);
        expect(find.text('Step 1 of 3'), findsOneWidget);
        expect(service.calls, isEmpty);
      },
    );

    testWidgets('the password checklist ticks rules off as they are met', (
      tester,
    ) async {
      await openSignUp(tester);
      await launch(tester, FakeAuthService());
      await tapAndSettle(tester, find.text('Create Account'));

      Finder ticked(String label) => find.descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(Row)),
        matching: find.byIcon(Icons.check_circle),
      );
      const labels = [
        'At least 8 characters',
        'One uppercase letter',
        'One lowercase letter',
        'One number',
        'One special character',
      ];
      for (final label in labels) {
        expect(find.text(label), findsOneWidget);
        expect(ticked(label), findsNothing);
      }

      final password = find.byType(TextFormField).at(1);
      await tester.enterText(password, 'abc');
      await tester.pump();
      expect(ticked('One lowercase letter'), findsOneWidget);
      expect(ticked('One uppercase letter'), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      await tester.enterText(password, 'Abcdefg1!');
      await tester.pump();
      for (final label in labels) {
        expect(ticked(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('each password box has its own show/hide button', (
      tester,
    ) async {
      await openSignUp(tester);
      await launch(tester, FakeAuthService());
      await tapAndSettle(tester, find.text('Create Account'));

      bool obscured(int index) => tester
          .widget<EditableText>(
            find.descendant(
              of: find.byType(TextFormField).at(index),
              matching: find.byType(EditableText),
            ),
          )
          .obscureText;

      expect(obscured(1), isTrue);
      expect(obscured(2), isTrue);

      await tester.tap(find.byTooltip('Show password').first);
      await tester.pump();
      expect(obscured(1), isFalse);
      expect(obscured(2), isTrue); // the other box is unchanged

      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(obscured(2), isFalse);

      await tester.tap(find.byTooltip('Hide password').first);
      await tester.pump();
      expect(obscured(1), isTrue);
      expect(obscured(2), isFalse);
    });

    testWidgets('Back keeps everything that was entered', (tester) async {
      await openSignUp(tester);
      await launch(tester, FakeAuthService());
      await tapAndSettle(tester, find.text('Create Account'));

      await fillAccountStep(tester);
      await tapContinue(tester);
      await fillPersonalStep(tester);
      await tapContinue(tester);
      expect(find.text('ann@example.com'), findsOneWidget); // review
      expect(find.text('Ann Lee'), findsOneWidget);
      expect(find.textContaining('S3cret!Pw'), findsNothing); // never shown

      await tapAndSettle(tester, find.text('Back'));
      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(find.text('Ann'), findsOneWidget);
      expect(find.text('Lee'), findsOneWidget);
      expect(find.text('Select date of birth'), findsNothing); // still picked

      await tapAndSettle(tester, find.text('Back'));
      expect(find.text('Step 1 of 3'), findsOneWidget);
      expect(find.text('ann@example.com'), findsOneWidget);
      final password = tester.widget<TextFormField>(
        find.byType(TextFormField).at(1),
      );
      expect(password.controller!.text, 'S3cret!Pw');

      // Straight through again without retyping anything.
      await tapContinue(tester);
      await tapContinue(tester);
      expect(find.text('Step 3 of 3'), findsOneWidget);

      // Edit on the review jumps to that step.
      await tapAndSettle(tester, find.text('Edit Account'));
      expect(find.text('Step 1 of 3'), findsOneWidget);
    });

    testWidgets('terms must be accepted', (tester) async {
      await openSignUp(tester);
      final service = FakeAuthService();
      await launch(tester, service);
      await tapAndSettle(tester, find.text('Create Account'));

      await fillSignUp(tester, accept: false);
      await tapAndSettle(
        tester,
        find.widgetWithText(FilledButton, 'Create Account'),
      );
      expect(
        find.text('Please accept the Terms of Service and Privacy Policy'),
        findsOneWidget,
      );
      expect(service.calls, isEmpty);

      // Ticking opens the documents to read; leaving without agreeing
      // leaves the box unticked.
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(find.text('Terms and Privacy'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsWidgets);
      await tester.pageBack();
      await tester.pumpAndSettle();
      bool ticked() =>
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value ??
          false;
      expect(ticked(), isFalse);

      // Reading to the end and agreeing ticks it.
      await agreeToTerms(tester);
      expect(ticked(), isTrue);
    });

    testWidgets('an existing email is explained without raw Firebase text', (
      tester,
    ) async {
      await openSignUp(tester);
      final service = FakeAuthService()
        ..addAccount('ann@example.com', 'pw123456');
      await launch(tester, service);
      await tapAndSettle(tester, find.text('Create Account'));

      await fillSignUp(tester);
      await tapAndSettle(
        tester,
        find.widgetWithText(FilledButton, 'Create Account'),
      );
      expect(
        find.text('An account with this email already exists.'),
        findsOneWidget,
      );
      expect(
        find.text('Create your account'),
        findsOneWidget,
      ); // still on the form
    });

    testWidgets(
      'success: Firebase is called, then Verify your email, then Profile Setup',
      (tester) async {
        await openSignUp(tester);
        final service = FakeAuthService();
        await launch(tester, service);
        await tapAndSettle(tester, find.text('Create Account'));

        await fillSignUp(tester);
        await tapAndSettle(
          tester,
          find.widgetWithText(FilledButton, 'Create Account'),
        );

        expect(service.calls.first, 'signUp:ann@example.com:Ann:Lee');
        expect(service.verificationEmailsSent, 1);
        expect(find.text('Verify your email'), findsOneWidget);
        expect(find.text('ann@example.com'), findsOneWidget);
        expect(find.text('Create your account'), findsNothing); // form is gone

        // Not verified yet: stays, with a clear message.
        await tapAndSettle(tester, find.text("I've Verified My Email"));
        expect(find.text('Verify your email'), findsOneWidget);
        expect(find.textContaining('not verified yet'), findsOneWidget);
        expect(find.byType(ProfileSetupScreen), findsNothing);

        // Resend.
        await tapAndSettle(tester, find.text('Resend Verification Email'));
        expect(find.text('Verification email sent.'), findsOneWidget);
        expect(service.verificationEmailsSent, 2);

        // The user opens the link, then taps the button.
        service.markVerified('ann@example.com');
        await tapAndSettle(tester, find.text("I've Verified My Email"));
        expect(find.byType(ProfileSetupScreen), findsOneWidget);
        final nameBox = tester.widget<TextFormField>(
          find.byType(TextFormField).first,
        );
        expect(nameBox.controller!.text, 'Ann Lee');
      },
    );

    testWidgets('signing up does not ask for age, sex, height or goal', (
      tester,
    ) async {
      await openSignUp(tester);
      await launch(tester, FakeAuthService());
      await tapAndSettle(tester, find.text('Create Account'));
      const labels = ['Age', 'Sex', 'Height (cm)', 'Weight (kg)', 'Main goal'];
      void expectNone() {
        for (final label in labels) {
          expect(find.text(label), findsNothing);
        }
      }

      expectNone();
      await fillAccountStep(tester);
      await tapContinue(tester);
      expectNone();
      await fillPersonalStep(tester);
      await tapContinue(tester);
      expectNone();
    });

    testWidgets('Sign Out on the verification screen returns to Welcome', (
      tester,
    ) async {
      await openSignUp(tester);
      final service = FakeAuthService();
      await launch(tester, service);
      await tapAndSettle(tester, find.text('Create Account'));
      await fillSignUp(tester);
      await tapAndSettle(
        tester,
        find.widgetWithText(FilledButton, 'Create Account'),
      );

      await tapAndSettle(tester, find.text('Sign Out'));
      expect(find.text('Welcome to ANTHROFIT'), findsOneWidget);
      expect(service.currentUser, isNull);
    });
  });

  // ---------------------------------------------------------------------
  group('sign in and password reset', () {
    Future<void> openSignIn(
      WidgetTester tester,
      FakeAuthService service,
    ) async {
      useTallScreen(tester);
      await launch(tester, service);
      await tapAndSettle(tester, find.text('Sign In'));
      expect(find.text('Welcome back'), findsOneWidget);
    }

    Future<void> submit(
      WidgetTester tester,
      String email,
      String password,
    ) async {
      await tester.enterText(find.byType(TextFormField).at(0), email);
      await tester.enterText(find.byType(TextFormField).at(1), password);
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Sign In'));
    }

    testWidgets('fields are checked before anything is sent', (tester) async {
      seedFreshInstall();
      final service = FakeAuthService();
      await openSignIn(tester, service);
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Sign In'));
      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
      expect(service.calls, isEmpty);
    });

    testWidgets('the eye button shows and hides the password', (tester) async {
      seedFreshInstall();
      await openSignIn(tester, FakeAuthService());
      bool obscured() => tester
          .widget<EditableText>(
            find.descendant(
              of: find.byType(TextFormField).at(1),
              matching: find.byType(EditableText),
            ),
          )
          .obscureText;

      expect(obscured(), isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(obscured(), isFalse);
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump();
      expect(obscured(), isTrue);
    });

    testWidgets('wrong password and unknown email give one friendly message', (
      tester,
    ) async {
      seedFreshInstall();
      final service = FakeAuthService()
        ..addAccount('ann@example.com', 'rightPass1');
      await openSignIn(tester, service);

      await submit(tester, 'ann@example.com', 'wrong');
      expect(find.text('Incorrect email or password.'), findsOneWidget);

      await submit(tester, 'nobody@example.com', 'rightPass1');
      expect(find.text('Incorrect email or password.'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('network trouble is explained, not shown raw', (tester) async {
      seedFreshInstall();
      final service = FakeAuthService()
        ..addAccount('ann@example.com', 'rightPass1');
      await openSignIn(tester, service);
      service.nextError = const AuthException(AuthErrorCode.network);
      await submit(tester, 'ann@example.com', 'rightPass1');
      expect(
        find.text('Check your internet connection and try again.'),
        findsOneWidget,
      );
    });

    testWidgets('a verified account signs in and reaches its own Home', (
      tester,
    ) async {
      final scope = StorageScope.user('uid_ann');
      SharedPreferences.setMockInitialValues(
        _entries(scope, profile: sampleProfile.copyWith(name: 'Ann Lee')),
      );
      final service = FakeAuthService()
        ..addAccount('ann@example.com', 'rightPass1', displayName: 'Ann Lee');
      await openSignIn(tester, service);

      await submit(tester, 'ann@example.com', 'rightPass1');
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.textContaining('Ann Lee'), findsOneWidget);
      expect(find.text('Welcome back'), findsNothing);
    });

    testWidgets('an unverified account is sent to verification', (
      tester,
    ) async {
      seedFreshInstall();
      final service = FakeAuthService()
        ..addAccount('ann@example.com', 'rightPass1', verified: false);
      await openSignIn(tester, service);

      await submit(tester, 'ann@example.com', 'rightPass1');
      expect(find.text('Verify your email'), findsOneWidget);
      expect(
        find.text('Please verify your email before continuing.'),
        findsOneWidget,
      );
    });

    testWidgets('Forgot Password sends Firebase\'s reset email and confirms', (
      tester,
    ) async {
      seedFreshInstall();
      final service = FakeAuthService();
      await openSignIn(tester, service);

      await tapAndSettle(tester, find.text('Forgot Password?'));
      await tester.enterText(find.byType(TextFormField), 'ann@example.com');
      await tapAndSettle(tester, find.text('Send reset email'));

      expect(service.passwordResets, ['ann@example.com']);
      expect(find.text('Check your email'), findsOneWidget);
      expect(find.textContaining('ann@example.com'), findsOneWidget);
    });

    testWidgets('Forgot Password does not reveal whether an account exists', (
      tester,
    ) async {
      seedFreshInstall();
      final service = FakeAuthService();
      await openSignIn(tester, service);
      await tapAndSettle(tester, find.text('Forgot Password?'));
      service.nextError = const AuthException(AuthErrorCode.userNotFound);
      await tester.enterText(find.byType(TextFormField), 'ghost@example.com');
      await tapAndSettle(tester, find.text('Send reset email'));
      expect(find.text('Check your email'), findsOneWidget);
    });

    testWidgets('Forgot Password shows a failure plainly', (tester) async {
      seedFreshInstall();
      final service = FakeAuthService();
      await openSignIn(tester, service);
      await tapAndSettle(tester, find.text('Forgot Password?'));
      service.nextError = const AuthException(AuthErrorCode.network);
      await tester.enterText(find.byType(TextFormField), 'ann@example.com');
      await tapAndSettle(tester, find.text('Send reset email'));
      expect(
        find.text('Check your internet connection and try again.'),
        findsOneWidget,
      );
      expect(find.text('Check your email'), findsNothing);
    });

    testWidgets('Continue without an account works from Sign In too', (
      tester,
    ) async {
      seedFreshInstall();
      final service = FakeAuthService();
      await openSignIn(tester, service);
      await tapAndSettle(tester, find.text('Continue without an account'));
      expect(find.byType(ProfileSetupScreen), findsOneWidget);
      expect(service.calls, isEmpty);
    });
  });

  // ---------------------------------------------------------------------
  group('account section, sign out and data isolation', () {
    testWidgets('the Profile account section shows the account and Sign Out', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(
        _entries(
          StorageScope.user('uid_ann'),
          profile: sampleProfile.copyWith(name: 'Ann L.'),
        ),
      );
      useTallScreen(tester);
      final service = FakeAuthService()
        ..addAccount('ann@example.com', 's3cretPw', displayName: 'Ann Lee')
        ..startSignedIn('ann@example.com');
      await launch(tester, service);
      await openTab(tester, 'Profile');

      expect(find.text('Account'), findsOneWidget);
      expect(find.text('First Name'), findsOneWidget);
      expect(find.text('Ann'), findsOneWidget);
      expect(find.text('Last Name'), findsOneWidget);
      expect(find.text('Lee'), findsOneWidget);
      expect(find.text('ann@example.com'), findsOneWidget);
      expect(find.text('Email Verified'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('Guest Mode'), findsNothing);
      expect(find.text('Training profile'), findsOneWidget);
      expect(find.text('Ann L.'), findsOneWidget); // the profile's display name
    });

    testWidgets('Sign Out returns to Welcome and keeps the data', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(
        _entries(
          StorageScope.user('uid_ann'),
          profile: sampleProfile.copyWith(name: 'Ann'),
          program: _program('a', 'Ann Plan'),
        ),
      );
      useTallScreen(tester);
      final service = FakeAuthService()
        ..addAccount('ann@example.com', 's3cretPw')
        ..startSignedIn('ann@example.com');
      await launch(tester, service);
      await openTab(tester, 'Profile');

      await tapAndSettle(tester, find.text('Sign Out'));
      expect(find.text('Welcome to ANTHROFIT'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(service.currentUser, isNull);

      // Nothing was deleted.
      final saved = await tester.runAsync(
        () => ProgramRepository(scope: StorageScope.user('uid_ann')).load(),
      );
      expect(saved!.programs.single.name, 'Ann Plan');
    });

    testWidgets(
      'User B never sees User A\'s profile, programs, history or unfinished workout',
      (tester) async {
        final a = StorageScope.user('uid_ann');
        final b = StorageScope.user('uid_bob');
        SharedPreferences.setMockInitialValues({
          ..._entries(
            a,
            profile: sampleProfile.copyWith(name: 'Ann Lee'),
            program: _program('a', 'Ann Plan'),
            unfinished: _unfinished('Ann Unfinished'),
          ),
          ..._entries(b, profile: sampleProfile.copyWith(name: 'Bob Roe')),
        });
        useTallScreen(tester);
        final service = FakeAuthService()
          ..addAccount('ann@example.com', 'annPass12', displayName: 'Ann Lee')
          ..addAccount('bob@example.com', 'bobPass12', displayName: 'Bob Roe')
          ..startSignedIn('ann@example.com');
        await launch(tester, service);

        // A: sees her workout in progress and her program.
        expect(find.textContaining('Ann Lee'), findsOneWidget);
        expect(find.text('Ann Unfinished'), findsOneWidget);
        expect(find.text('Resume workout'), findsOneWidget);
        await openTab(tester, 'Program');
        expect(find.text('Ann Plan'), findsOneWidget);

        // A signs out; B signs in.
        await openTab(tester, 'Profile');
        await tapAndSettle(tester, find.text('Sign Out'));
        await tapAndSettle(tester, find.text('Sign In'));
        await tester.enterText(
          find.byType(TextFormField).at(0),
          'bob@example.com',
        );
        await tester.enterText(find.byType(TextFormField).at(1), 'bobPass12');
        await tapAndSettle(
          tester,
          find.widgetWithText(FilledButton, 'Sign In'),
        );

        // B: none of A's data anywhere.
        expect(find.textContaining('Bob Roe'), findsOneWidget);
        expect(find.text('Ann Unfinished'), findsNothing);
        expect(find.text('Resume workout'), findsNothing);
        expect(find.text('No active program'), findsOneWidget);
        await openTab(tester, 'Program');
        expect(find.text('Ann Plan'), findsNothing);
        expect(find.text('No program yet.'), findsOneWidget);
        await openTab(tester, 'Progress');
        expect(find.text('No workout data yet.'), findsOneWidget);
        await openTab(tester, 'Profile');
        expect(find.text('Bob Roe'), findsOneWidget);
        expect(find.text('Ann Lee'), findsNothing);

        // B signs out; A signs back in and gets her own data back.
        await tapAndSettle(tester, find.text('Sign Out'));
        await tapAndSettle(tester, find.text('Sign In'));
        await tester.enterText(
          find.byType(TextFormField).at(0),
          'ann@example.com',
        );
        await tester.enterText(find.byType(TextFormField).at(1), 'annPass12');
        await tapAndSettle(
          tester,
          find.widgetWithText(FilledButton, 'Sign In'),
        );

        expect(find.textContaining('Ann Lee'), findsOneWidget);
        expect(find.text('Ann Unfinished'), findsOneWidget);
        expect(find.text('Resume workout'), findsOneWidget);
        await openTab(tester, 'Program');
        expect(find.text('Ann Plan'), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------
  group('guest data and a new account', () {
    Future<FakeAuthService> guestWithProgramThenSignUp(
      WidgetTester tester,
    ) async {
      seedAppData(
        programs: [_program('g', 'Guest Plan')],
        activeProgramId: 'g',
      );
      useTallScreen(tester);
      final service = FakeAuthService();
      await launch(tester, service);

      await openTab(tester, 'Profile');
      await tapAndSettle(tester, find.text('Create Account'));
      await fillSignUp(tester);
      await tapAndSettle(
        tester,
        find.widgetWithText(FilledButton, 'Create Account'),
      );
      service.markVerified('ann@example.com');
      await tapAndSettle(tester, find.text("I've Verified My Email"));
      return service;
    }

    testWidgets('the user is asked before the guest data is touched', (
      tester,
    ) async {
      await guestWithProgramThenSignUp(tester);

      expect(
        find.text('Existing ANTHROFIT data found on this device.'),
        findsOneWidget,
      );
      expect(
        find.text('Would you like to keep it with your new account?'),
        findsOneWidget,
      );
      expect(find.text('Keep My Data'), findsOneWidget);
      expect(find.text('Start Fresh'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets(
      'Keep My Data: the same profile and program are in the account',
      (tester) async {
        await guestWithProgramThenSignUp(tester);
        await tapAndSettle(tester, find.text('Keep My Data'));

        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byType(ProfileSetupScreen), findsNothing);
        await openTab(tester, 'Program');
        expect(find.text('Guest Plan'), findsOneWidget);
        expect(find.text('1 workout'), findsOneWidget); // not duplicated
        await openTab(tester, 'Profile');
        expect(find.text('Ann'), findsOneWidget); // now shown as an account
        expect(
          find.text('Test User'),
          findsOneWidget,
        ); // the profile came along
      },
    );

    testWidgets(
      'Start Fresh: a clean account, and the guest data is still saved',
      (tester) async {
        await guestWithProgramThenSignUp(tester);
        await tapAndSettle(tester, find.text('Start Fresh'));

        expect(find.byType(ProfileSetupScreen), findsOneWidget);
        final nameBox = tester.widget<TextFormField>(
          find.byType(TextFormField).first,
        );
        expect(nameBox.controller!.text, 'Ann Lee');

        final guest = await tester.runAsync(() => ProgramRepository().load());
        expect(guest!.programs.single.name, 'Guest Plan'); // untouched
        final account = await tester.runAsync(
          () => ProgramRepository(scope: StorageScope.user('uid_ann')).load(),
        );
        expect(account!.programs, isEmpty);
      },
    );

    testWidgets('the answer is remembered after a restart', (tester) async {
      final service = await guestWithProgramThenSignUp(tester);
      await tapAndSettle(tester, find.text('Keep My Data'));

      await restart(tester, service);
      expect(
        find.text('Existing ANTHROFIT data found on this device.'),
        findsNothing,
      );
      expect(find.byType(NavigationBar), findsOneWidget);
      await openTab(tester, 'Program');
      expect(find.text('Guest Plan'), findsOneWidget);
    });
  });
}
