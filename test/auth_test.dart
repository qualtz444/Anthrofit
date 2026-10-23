import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anthrofit/auth/account.dart';
import 'package:anthrofit/auth/account_store.dart';
import 'package:anthrofit/auth/auth_controller.dart';
import 'package:anthrofit/auth/auth_errors.dart';
import 'package:anthrofit/auth/auth_service.dart';
import 'package:anthrofit/auth/auth_validators.dart';
import 'package:anthrofit/composition/composition_visuals.dart';
import 'package:anthrofit/data/profile_repository.dart';
import 'package:anthrofit/data/program_repository.dart';
import 'package:anthrofit/data/session_repository.dart';
import 'package:anthrofit/data/storage_scope.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/photos/avatar_store.dart';
import 'package:anthrofit/photos/progress_photo.dart';
import 'package:anthrofit/photos/progress_photo_store.dart';

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

WorkoutSession _completed(String id) => WorkoutSession(
  id: id,
  programName: 'Prog',
  workoutId: 'w',
  workoutName: 'Upper A',
  startedAt: DateTime(2026, 1, 1, 9),
  completedAt: DateTime(2026, 1, 1, 9, 40),
  exerciseLogs: [
    testLog('machine_chest_press', 'Machine Chest Press', [(40.0, 10)]),
  ],
);

WorkoutSession _unfinished(String id) => WorkoutSession(
  id: id,
  programName: 'Prog',
  workoutId: 'w',
  workoutName: 'Unfinished Day',
  startedAt: DateTime(2026, 1, 2, 9),
  exerciseLogs: [
    ExerciseLog.fromPlanned(testPlanned('p', 'leg_press'), 'Leg Press'),
  ],
);

/// Saves a whole set of data for one owner.
Future<void> _saveData(
  StorageScope scope, {
  required UserProfile profile,
  required TrainingProgram program,
  WorkoutSession? completed,
  WorkoutSession? unfinished,
}) async {
  await ProfileRepository(scope: scope).save(profile);
  await ProgramRepository(
    scope: scope,
  ).save(ProgramData(programs: [program], activeProgramId: program.id));
  await SessionRepository(
    scope: scope,
  ).save(SessionData(activeSession: unfinished, sessions: [?completed]));
}

Future<AuthController> _start(FakeAuthService service) async {
  final controller = AuthController(service: service);
  await controller.start();
  return controller;
}

Future<void> _signUp(AuthController c, String first, String email) => c.signUp(
  firstName: first,
  lastName: 'Lee',
  email: email,
  password: 's3cretPw',
);

void main() {
  // The exercise catalogue is an asset now, so it has to be loaded.
  useExerciseLibrary();

  // ---------------------------------------------------------------------
  group('form checks', () {
    test('first and last name are required', () {
      expect(validateName('', 'first name'), 'Enter your first name');
      expect(validateName('   ', 'last name'), 'Enter your last name');
      expect(validateName(null, 'first name'), isNotNull);
      expect(validateName('Ann', 'first name'), isNull);
    });

    test('email is required and must look like an email', () {
      expect(validateEmail(''), 'Enter your email');
      expect(validateEmail('   '), 'Enter your email');
      for (final bad in ['ann', 'ann@', '@x.com', 'ann@x', 'a nn@x.com']) {
        expect(validateEmail(bad), 'Enter a valid email address', reason: bad);
      }
      expect(validateEmail('ann@example.com'), isNull);
      expect(validateEmail('  ann@example.com '), isNull);
    });

    test('password is required and meets every rule', () {
      const weak = 'Password does not meet all the requirements';
      expect(validateNewPassword(''), 'Enter a password');
      expect(kMinPasswordLength, 8);
      for (final bad in [
        'Ab1!xyz', // 7 characters
        'abcdef1!', // no uppercase
        'ABCDEF1!', // no lowercase
        'Abcdefg!', // no number
        'Abcdefg1', // no special character
        'Abcdef 1', // a space is not special
      ]) {
        expect(validateNewPassword(bad), weak, reason: bad);
      }
      expect(validateNewPassword('Abcdef1!'), isNull);
      expect(validateNewPassword('S3cret_Pw'), isNull);
    });

    test('each password rule is checked on its own', () {
      final met = passwordRules.where((r) => r.isMetBy('abc1')).toList();
      expect(met.map((r) => r.label), ['One lowercase letter', 'One number']);
      expect(passwordRules.every((r) => r.isMetBy('Abcdef1!')), isTrue);
    });

    test('confirm password must match', () {
      expect(
        validatePasswordConfirmation('', 'abcdef'),
        'Confirm your password',
      );
      expect(
        validatePasswordConfirmation('abcdeX', 'abcdef'),
        'Passwords do not match',
      );
      expect(validatePasswordConfirmation('abcdef', 'abcdef'), isNull);
    });
  });

  group('friendly errors', () {
    test('every failure has short text and no raw Firebase wording', () {
      for (final code in AuthErrorCode.values) {
        final text = authErrorMessage(code);
        expect(text, isNotEmpty, reason: '$code');
        expect(
          text.toLowerCase(),
          isNot(contains('firebase')),
          reason: '$code',
        );
        expect(text, isNot(contains('[')), reason: '$code');
        expect(text, isNot(contains('Exception')), reason: '$code');
      }
      expect(
        authErrorMessage(AuthErrorCode.wrongCredentials),
        'Incorrect email or password.',
      );
      expect(
        authErrorMessage(AuthErrorCode.unknown),
        'Unable to sign in. Please try again.',
      );
      expect(
        authErrorMessage(AuthErrorCode.unknown, action: 'create your account'),
        'Unable to create your account. Please try again.',
      );
    });

    test('anything else becomes the generic message, never its own text', () {
      final text = describeAuthError(StateError('secret-token-abc123'));
      expect(text, 'Unable to sign in. Please try again.');
      expect(text, isNot(contains('abc123')));
    });
  });

  test(
    'names are read from Firebase\'s display name when there is no saved record',
    () {
      AccountInfo from(String? name) => AccountInfo.fromAuthUser(
        AuthUser(
          uid: 'u',
          email: 'a@x.com',
          displayName: name,
          emailVerified: true,
        ),
      );
      expect(from('Ann Lee').firstName, 'Ann');
      expect(from('Ann Lee').lastName, 'Lee');
      expect(from('Ann Marie Lee').lastName, 'Marie Lee');
      expect(from('Ann').lastName, '');
      expect(from(null).fullName, '');
      expect(from('Ann Lee').fullName, 'Ann Lee');
    },
  );

  // ---------------------------------------------------------------------
  group('storage is scoped by owner', () {
    test('keys: guest keeps the old keys, accounts get their own', () {
      expect(StorageScope.guest.key('user_profile'), 'user_profile');
      expect(
        StorageScope.user('abc').key('user_profile'),
        'u.abc.user_profile',
      );
      expect(StorageScope.user('abc').id, isNot(StorageScope.user('abd').id));
      expect(StorageScope.guest.isGuest, isTrue);
      expect(StorageScope.user('abc').isGuest, isFalse);
    });

    test(
      'profile, programs, active program and unfinished workout never mix',
      () async {
        seedFreshInstall();
        final a = StorageScope.user('A');
        final b = StorageScope.user('B');
        await _saveData(
          StorageScope.guest,
          profile: sampleProfile.copyWith(name: 'Guest'),
          program: _program('g', 'Guest Plan'),
          unfinished: _unfinished('sg'),
        );
        await _saveData(
          a,
          profile: sampleProfile.copyWith(name: 'Ann'),
          program: _program('a', 'A Plan'),
          completed: _completed('done-a'),
          unfinished: _unfinished('sa'),
        );

        // B has saved nothing: sees nothing of A or the guest.
        expect(await ProfileRepository(scope: b).load(), isNull);
        final bPrograms = await ProgramRepository(scope: b).load();
        expect(bPrograms.programs, isEmpty);
        expect(bPrograms.activeProgramId, isNull);
        final bSessions = await SessionRepository(scope: b).load();
        expect(bSessions.activeSession, isNull);
        expect(bSessions.sessions, isEmpty);

        // A and the guest each see only their own.
        expect((await ProfileRepository(scope: a).load())!.name, 'Ann');
        expect((await ProfileRepository().load())!.name, 'Guest');
        expect((await ProgramRepository(scope: a).load()).activeProgramId, 'a');
        expect((await ProgramRepository().load()).activeProgramId, 'g');
        expect(
          (await SessionRepository(scope: a).load()).activeSession!.id,
          'sa',
        );
        expect((await SessionRepository().load()).activeSession!.id, 'sg');
        expect(
          (await SessionRepository(scope: a).load()).sessions.single.id,
          'done-a',
        );
      },
    );
  });

  // ---------------------------------------------------------------------
  group('AuthController: starting up', () {
    test(
      'nothing chosen and nobody signed in -> signed out (Welcome)',
      () async {
        seedFreshInstall();
        final c = await _start(FakeAuthService());
        expect(c.status, AuthStatus.signedOut);
        expect(c.dataScope, isNull);
      },
    );

    test('guest mode is remembered across restarts', () async {
      seedFreshInstall();
      final first = await _start(FakeAuthService());
      await first.continueAsGuest();
      expect(first.status, AuthStatus.guest);
      expect(first.dataScope!.isGuest, isTrue);

      final again = await _start(FakeAuthService());
      expect(again.status, AuthStatus.guest);
    });

    test('guest mode never touches Firebase or creates an account', () async {
      seedFreshInstall();
      final service = FakeAuthService();
      final c = await _start(service);
      await c.continueAsGuest();
      expect(service.calls, isEmpty);
      expect(service.currentUser, isNull);
    });

    test('a signed-in, unverified user goes to verification', () async {
      seedFreshInstall();
      final service = FakeAuthService()
        ..addAccount('ann@example.com', 's3cretPw', verified: false)
        ..startSignedIn('ann@example.com');
      final c = await _start(service);
      expect(c.status, AuthStatus.unverified);
      expect(c.dataScope, isNull); // no data is loaded before verification
    });

    test('a signed-in, verified user gets their own data scope', () async {
      seedFreshInstall();
      final service = FakeAuthService()
        ..addAccount('ann@example.com', 's3cretPw', displayName: 'Ann Lee')
        ..startSignedIn('ann@example.com');
      final c = await _start(service);
      expect(c.status, AuthStatus.verified);
      expect(c.dataScope!.id, StorageScope.user('uid_ann').id);
      expect(c.account!.fullName, 'Ann Lee');
    });

    test('a signed-in user wins over a leftover guest marker', () async {
      seedNoProfile(); // guest marker is set
      final service = FakeAuthService()
        ..addAccount('ann@example.com', 's3cretPw')
        ..startSignedIn('ann@example.com');
      final c = await _start(service);
      expect(c.status, AuthStatus.verified);
    });

    test(
      'Firebase unavailable: signed out, but guest mode still works',
      () async {
        seedFreshInstall();
        final service = FakeAuthService(initializeFails: true);
        final c = await _start(service);
        expect(c.status, AuthStatus.signedOut);
        expect(c.accountsUnavailable, isTrue);
        await c.continueAsGuest();
        expect(c.status, AuthStatus.guest);
      },
    );
  });

  group('AuthController: sign up, verify, sign in, sign out', () {
    test(
      'sign up calls Firebase correctly and waits for verification',
      () async {
        seedFreshInstall();
        final service = FakeAuthService();
        final c = await _start(service);
        await c.signUp(
          firstName: ' Ann ',
          lastName: 'Lee',
          email: ' ann@example.com ',
          password: 's3cretPw',
        );

        expect(service.calls.first, 'signUp:ann@example.com:Ann:Lee');
        expect(service.calls, contains('sendVerificationEmail'));
        expect(service.verificationEmailsSent, 1);
        expect(c.status, AuthStatus.unverified);
        expect(c.user!.uid, 'uid_ann');
        expect(c.account!.firstName, 'Ann');
        expect(c.account!.lastName, 'Lee');
        expect(c.account!.email, 'ann@example.com');
        expect(c.dataScope, isNull);
      },
    );

    test(
      'names and email are remembered on the device, the password is not',
      () async {
        seedFreshInstall();
        final c = await _start(FakeAuthService());
        await _signUp(c, 'Ann', 'ann@example.com');

        final saved = await AccountStore().loadAccount('uid_ann');
        expect(saved!.firstName, 'Ann');
        expect(saved.lastName, 'Lee');
        expect(saved.email, 'ann@example.com');

        final prefs = await SharedPreferences.getInstance();
        for (final key in prefs.getKeys()) {
          expect('${prefs.get(key)}', isNot(contains('s3cretPw')), reason: key);
        }
      },
    );

    test('signing up ends guest mode and the guest marker', () async {
      seedFreshInstall();
      final c = await _start(FakeAuthService());
      await c.continueAsGuest();
      await _signUp(c, 'Ann', 'ann@example.com');
      expect(c.status, AuthStatus.unverified);
      expect(await AccountStore().isGuestChosen(), isFalse);
    });

    test(
      'sign-up errors are thrown as friendly codes and change nothing',
      () async {
        seedFreshInstall();
        final service = FakeAuthService()
          ..addAccount('ann@example.com', 'pw123456');
        final c = await _start(service);

        await expectLater(
          _signUp(c, 'Ann', 'ann@example.com'),
          throwsA(
            isA<AuthException>().having(
              (e) => e.code,
              'code',
              AuthErrorCode.emailInUse,
            ),
          ),
        );
        expect(c.status, AuthStatus.signedOut);

        await expectLater(
          c.signUp(
            firstName: 'B',
            lastName: 'L',
            email: 'b@example.com',
            password: '123',
          ),
          throwsA(
            isA<AuthException>().having(
              (e) => e.code,
              'code',
              AuthErrorCode.weakPassword,
            ),
          ),
        );
        expect(c.status, AuthStatus.signedOut);
      },
    );

    test(
      'if the verification email cannot be sent, the account still exists and the user can resend',
      () async {
        seedFreshInstall();
        final service = FakeAuthService()..failVerificationEmail = true;
        final c = await _start(service);
        await _signUp(c, 'Ann', 'ann@example.com');

        expect(c.status, AuthStatus.unverified); // not stuck on the form
        expect(service.verificationEmailsSent, 0);
        expect(
          c.notice,
          "We couldn't send the verification email. Tap Resend to try again.",
        );

        service.failVerificationEmail = false;
        await c.resendVerificationEmail();
        expect(service.verificationEmailsSent, 1);
      },
    );

    test(
      '"I\'ve verified" stays put until the email is really verified',
      () async {
        seedFreshInstall();
        final service = FakeAuthService();
        final c = await _start(service);
        await _signUp(c, 'Ann', 'ann@example.com');

        expect(await c.refreshVerification(), isFalse);
        expect(c.status, AuthStatus.unverified);

        service.markVerified('ann@example.com');
        expect(await c.refreshVerification(), isTrue);
        expect(c.status, AuthStatus.verified);
        expect(c.dataScope!.id, StorageScope.user('uid_ann').id);
      },
    );

    test(
      'sign in: verified goes in, unverified goes to verification',
      () async {
        seedFreshInstall();
        final service = FakeAuthService()
          ..addAccount('ok@example.com', 'pw123456', displayName: 'Oki Doe')
          ..addAccount('new@example.com', 'pw123456', verified: false);
        final c = await _start(service);

        await c.signIn(email: 'ok@example.com', password: 'pw123456');
        expect(c.status, AuthStatus.verified);
        expect(c.account!.fullName, 'Oki Doe');
        await c.signOut();

        await c.signIn(email: 'new@example.com', password: 'pw123456');
        expect(c.status, AuthStatus.unverified);
        expect(c.notice, 'Please verify your email before continuing.');
      },
    );

    test('sign in failures leave the user signed out', () async {
      seedFreshInstall();
      final service = FakeAuthService()
        ..addAccount('ok@example.com', 'pw123456');
      final c = await _start(service);

      await expectLater(
        c.signIn(email: 'ok@example.com', password: 'wrong'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.code,
            'code',
            AuthErrorCode.wrongCredentials,
          ),
        ),
      );
      await expectLater(
        c.signIn(email: 'nobody@example.com', password: 'pw123456'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.code,
            'code',
            AuthErrorCode.userNotFound,
          ),
        ),
      );
      service.nextError = const AuthException(AuthErrorCode.network);
      await expectLater(
        c.signIn(email: 'ok@example.com', password: 'pw123456'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.code,
            'code',
            AuthErrorCode.network,
          ),
        ),
      );
      expect(c.status, AuthStatus.signedOut);
    });

    test('sign out ends the session and returns to Welcome', () async {
      seedFreshInstall();
      final service = FakeAuthService()
        ..addAccount('ok@example.com', 'pw123456');
      final c = await _start(service);
      await c.signIn(email: 'ok@example.com', password: 'pw123456');
      await c.signOut();

      expect(c.status, AuthStatus.signedOut);
      expect(c.user, isNull);
      expect(c.dataScope, isNull);
      expect(service.currentUser, isNull);
      expect((await _start(service)).status, AuthStatus.signedOut);
    });

    test('a session Firebase remembers survives an app restart', () async {
      seedFreshInstall();
      final service = FakeAuthService()
        ..addAccount('ok@example.com', 'pw123456');
      final c = await _start(service);
      await c.signIn(email: 'ok@example.com', password: 'pw123456');

      final restarted = await _start(service); // same Firebase session
      expect(restarted.status, AuthStatus.verified);
      expect(restarted.user!.email, 'ok@example.com');
    });

    test(
      'password reset sends Firebase\'s email to the typed address',
      () async {
        seedFreshInstall();
        final service = FakeAuthService();
        final c = await _start(service);
        await c.sendPasswordReset(' ann@example.com ');
        expect(service.passwordResets, ['ann@example.com']);

        service.nextError = const AuthException(AuthErrorCode.network);
        await expectLater(
          c.sendPasswordReset('ann@example.com'),
          throwsA(isA<AuthException>()),
        );
      },
    );
  });

  // ---------------------------------------------------------------------
  group('guest data moving into a new account', () {
    Future<void> guestWithData() async {
      seedFreshInstall();
      await _saveData(
        StorageScope.guest,
        profile: sampleProfile.copyWith(name: 'Guest Gary'),
        program: _program('g', 'Guest Plan'),
        completed: _completed('done-g'),
        unfinished: _unfinished('sg'),
      );
    }

    Future<void> verifyNewAccount(
      AuthController c,
      FakeAuthService s,
      String email,
    ) async {
      await _signUp(c, 'Ann', email);
      s.markVerified(email);
      await c.refreshVerification();
    }

    test(
      'with guest data present, the user is asked before anything moves',
      () async {
        await guestWithData();
        final service = FakeAuthService();
        final controller = AuthController(service: service);
        await controller.start();
        await verifyNewAccount(controller, service, 'ann@example.com');

        expect(controller.status, AuthStatus.verified);
        expect(controller.migrationPending, isTrue);
        expect(controller.dataScope, isNull); // nothing is shown yet
        // Nothing was touched.
        expect(await AccountStore().scopeHasData(StorageScope.guest), isTrue);
        expect(
          await AccountStore().scopeHasData(StorageScope.user('uid_ann')),
          isFalse,
        );
      },
    );

    test('Keep My Data moves everything, once, with no duplicates', () async {
      await guestWithData();
      final service = FakeAuthService();
      final c = AuthController(service: service);
      await c.start();
      await verifyNewAccount(c, service, 'ann@example.com');
      await c.keepGuestData();

      expect(c.migrationPending, isFalse);
      final scope = StorageScope.user('uid_ann');
      expect(c.dataScope!.id, scope.id);

      expect(
        (await ProfileRepository(scope: scope).load())!.name,
        'Guest Gary',
      );
      final programs = await ProgramRepository(scope: scope).load();
      expect(programs.programs.length, 1);
      expect(programs.activeProgramId, 'g');
      final sessions = await SessionRepository(scope: scope).load();
      expect(sessions.sessions.length, 1);
      expect(sessions.sessions.single.id, 'done-g');
      expect(
        sessions.activeSession!.id,
        'sg',
      ); // the unfinished workout moved too

      // Moved, not copied: the guest area is now empty.
      expect(await AccountStore().scopeHasData(StorageScope.guest), isFalse);

      // Signing in again does not ask again or move anything twice.
      await c.signOut();
      await c.signIn(email: 'ann@example.com', password: 's3cretPw');
      expect(c.migrationPending, isFalse);
      expect((await ProgramRepository(scope: scope).load()).programs.length, 1);
    });

    test(
      'Start Fresh gives a clean account and leaves guest data alone',
      () async {
        await guestWithData();
        final service = FakeAuthService();
        final c = AuthController(service: service);
        await c.start();
        await verifyNewAccount(c, service, 'ann@example.com');
        await c.startFresh();

        final scope = StorageScope.user('uid_ann');
        expect(c.migrationPending, isFalse);
        expect(await ProfileRepository(scope: scope).load(), isNull);
        expect(
          (await ProgramRepository(scope: scope).load()).programs,
          isEmpty,
        );

        // The guest data is exactly where it was.
        expect((await ProfileRepository().load())!.name, 'Guest Gary');
        expect((await ProgramRepository().load()).programs.length, 1);
        expect((await SessionRepository().load()).activeSession!.id, 'sg');
      },
    );

    test('no question is asked when there is no guest data', () async {
      seedFreshInstall();
      final service = FakeAuthService();
      final c = AuthController(service: service);
      await c.start();
      await verifyNewAccount(c, service, 'ann@example.com');
      expect(c.migrationPending, isFalse);
      expect(c.dataScope!.id, StorageScope.user('uid_ann').id);
    });

    test('an account that already has its own data is not asked', () async {
      seedFreshInstall();
      await _saveData(
        StorageScope.guest,
        profile: sampleProfile.copyWith(name: 'Guest'),
        program: _program('g', 'Guest Plan'),
      );
      await _saveData(
        StorageScope.user('uid_bob'),
        profile: sampleProfile.copyWith(name: 'Bob'),
        program: _program('b', 'Bob Plan'),
      );
      final service = FakeAuthService()
        ..addAccount('bob@example.com', 'pw123456');
      final c = AuthController(service: service);
      await c.start();
      await c.signIn(email: 'bob@example.com', password: 'pw123456');

      expect(c.migrationPending, isFalse);
      expect(
        (await ProfileRepository(scope: c.dataScope!).load())!.name,
        'Bob',
      );
      expect((await ProfileRepository().load())!.name, 'Guest'); // untouched
    });

    test('moving never overwrites what the account already has', () async {
      seedFreshInstall();
      await _saveData(
        StorageScope.guest,
        profile: sampleProfile.copyWith(name: 'Guest'),
        program: _program('g', 'Guest Plan'),
      );
      final target = StorageScope.user('uid_x');
      // The target already has a profile, which must never be overwritten.
      await ProfileRepository(
        scope: target,
      ).save(sampleProfile.copyWith(name: 'Existing'));

      await AccountStore().moveGuestDataTo(target);

      expect((await ProfileRepository(scope: target).load())!.name, 'Existing');
      // That one item stays in the guest area; the rest moved.
      expect((await ProfileRepository().load())!.name, 'Guest');
      expect(
        (await ProgramRepository(scope: target).load()).programs.length,
        1,
      );
      expect((await ProgramRepository().load()).programs, isEmpty);
    });
  });

  // ---------------------------------------------------------------------
  test(
    'the exact isolation scenario: guest -> account A -> account B -> account A',
    () async {
      seedFreshInstall();
      final service = FakeAuthService();
      final c = AuthController(service: service);
      await c.start();

      // GUEST: profile, program, completed workout (history).
      await c.continueAsGuest();
      await _saveData(
        StorageScope.guest,
        profile: sampleProfile.copyWith(name: 'Guest Gary'),
        program: _program('g', 'Guest Plan'),
        completed: _completed('done-g'),
      );

      // Create account A and keep the guest data.
      await _signUp(c, 'Ann', 'ann@example.com');
      service.markVerified('ann@example.com');
      await c.refreshVerification();
      expect(c.migrationPending, isTrue);
      await c.keepGuestData();
      final aScope = c.dataScope!;

      // A starts an unfinished workout.
      final aSessions = await SessionRepository(scope: aScope).load();
      await SessionRepository(scope: aScope).save(
        SessionData(
          activeSession: _unfinished('a-active'),
          sessions: aSessions.sessions,
        ),
      );

      // Sign out. Create account B.
      await c.signOut();
      await _signUp(c, 'Bob', 'bob@example.com');
      service.markVerified('bob@example.com');
      await c.refreshVerification();
      expect(c.migrationPending, isFalse); // guest area is empty now
      final bScope = c.dataScope!;
      expect(bScope.id, isNot(aScope.id));

      // B sees none of A's data.
      expect(await ProfileRepository(scope: bScope).load(), isNull);
      expect((await ProgramRepository(scope: bScope).load()).programs, isEmpty);
      expect(
        (await ProgramRepository(scope: bScope).load()).activeProgramId,
        isNull,
      );
      final bSessions = await SessionRepository(scope: bScope).load();
      expect(bSessions.sessions, isEmpty); // no history, so no progress
      expect(bSessions.activeSession, isNull); // not A's unfinished workout

      // Sign out. Sign A back in: A sees A's data, including the unfinished workout.
      await c.signOut();
      await c.signIn(email: 'ann@example.com', password: 's3cretPw');
      expect(c.dataScope!.id, aScope.id);
      expect(
        (await ProfileRepository(scope: c.dataScope!).load())!.name,
        'Guest Gary',
      );
      expect(
        (await ProgramRepository(scope: c.dataScope!).load()).activeProgramId,
        'g',
      );
      final back = await SessionRepository(scope: c.dataScope!).load();
      expect(back.sessions.single.id, 'done-g');
      expect(back.activeSession!.id, 'a-active');

      // Signing out never deleted anyone's data.
      expect((await ProfileRepository(scope: aScope).load()), isNotNull);
    },
  );

  // ---------------------------------------------------------------------
  group('AuthController: delete account', () {
    final annScope = StorageScope.user('uid_ann');

    Future<(AuthController, FakeAuthService)> signedInAnn() async {
      seedFreshInstall();
      final service = FakeAuthService()
        ..addAccount('ann@example.com', 's3cretPw');
      final c = await _start(service);
      await c.signIn(email: 'ann@example.com', password: 's3cretPw');
      await _saveData(
        annScope,
        profile: sampleProfile,
        program: _program('a', 'Ann Plan'),
        completed: _completed('done-a'),
      );
      return (c, service);
    }

    test('a wrong password removes nothing', () async {
      final (c, service) = await signedInAnn();
      var erased = false;

      await expectLater(
        c.deleteAccount(
          password: 'wrong',
          eraseCloudData: (_) async => erased = true,
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.code,
            'code',
            AuthErrorCode.wrongCredentials,
          ),
        ),
      );
      expect(erased, isFalse);
      expect(service.hasAccount('ann@example.com'), isTrue);
      expect(c.status, AuthStatus.verified);
      expect(await ProfileRepository(scope: annScope).load(), isNotNull);
    });

    test('when the cloud data cannot be removed, the login stays', () async {
      final (c, service) = await signedInAnn();

      await expectLater(
        c.deleteAccount(
          password: 's3cretPw',
          eraseCloudData: (_) async => throw StateError('offline'),
        ),
        throwsStateError,
      );
      expect(service.calls, isNot(contains('deleteUser')));
      expect(service.hasAccount('ann@example.com'), isTrue);
      expect(c.status, AuthStatus.verified);
    });

    test('removes the cloud data, then the login, then this phone\'s data, '
        'and leaves other owners alone', () async {
      final (c, service) = await signedInAnn();
      await _saveData(
        StorageScope.guest,
        profile: sampleProfile,
        program: _program('g', 'Guest Plan'),
      );
      final erasedFor = <String>[];

      await c.deleteAccount(
        password: 's3cretPw',
        eraseCloudData: (uid) async {
          // The login must still exist while the cloud data goes.
          expect(service.hasAccount('ann@example.com'), isTrue);
          erasedFor.add(uid);
        },
      );

      expect(erasedFor, ['uid_ann']);
      expect(service.hasAccount('ann@example.com'), isFalse);
      expect(c.status, AuthStatus.signedOut);
      expect(c.user, isNull);
      expect(await ProfileRepository(scope: annScope).load(), isNull);
      expect(
        (await ProgramRepository(scope: annScope).load()).programs,
        isEmpty,
      );
      expect(await AccountStore().loadAccount('uid_ann'), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith('u.uid_ann.')), isEmpty);
      // The guest's data on the same phone is untouched.
      expect(
        (await ProgramRepository(scope: StorageScope.guest).load())
            .programs
            .single
            .name,
        'Guest Plan',
      );
    });

    test('this phone\'s files for the account go too: scan visuals, progress '
        'photos and avatar', () async {
      SharedPreferences.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('erase_account');
      addTearDown(() => dir.delete(recursive: true));
      Future<Directory> base() async => dir;
      final bytes = Uint8List.fromList([1, 2, 3]);

      await ProfileRepository(scope: annScope).save(
        sampleProfile.copyWith(
          compositionLog: [
            CompositionRecord(
              id: 'scan-1',
              takenAt: DateTime(2026, 10, 1),
              weightKg: 70,
              bodyFatPct: 20,
              bodyFatLow: 17,
              bodyFatHigh: 23,
              leanLimbKg: 24,
              fatFreeMassKg: 56,
              fatMassKg: 14,
              waistCm: 80,
              chestCm: 95,
              hipCm: 95,
              thighCm: 55,
              upperArmCm: 30,
              frameCount: 3,
            ),
          ],
        ),
      );
      final visuals = CompositionVisualStore(baseDirectory: base);
      await visuals.save('scan-1', CompositionVisuals(frontPhoto: bytes));
      final photos = ProgressPhotoStore(scope: annScope, baseDirectory: base);
      await photos.add(bytes, pose: PhotoPose.front);
      await AvatarStore(scope: annScope, baseDirectory: base).save(bytes);
      final guestAvatar = AvatarStore(
        scope: StorageScope.guest,
        baseDirectory: base,
      );
      await guestAvatar.save(bytes);

      await AccountStore().eraseLocalData('uid_ann', baseDirectory: base);

      expect((await visuals.load('scan-1')).hasPhotos, isFalse);
      expect(await photos.load(), isEmpty);
      expect(
        await AvatarStore(scope: annScope, baseDirectory: base).load(),
        isNull,
      );
      expect(await ProfileRepository(scope: annScope).load(), isNull);
      expect(await guestAvatar.load(), bytes);
    });
  });
}
