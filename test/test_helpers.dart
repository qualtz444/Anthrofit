import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/auth/account.dart';
import 'package:anthrofit/auth/account_store.dart';
import 'package:anthrofit/auth/auth_service.dart';
import 'package:anthrofit/data/exercise_catalog_repository.dart';
import 'package:anthrofit/data/exercise_library.dart';
import 'package:anthrofit/data/profile_repository.dart';
import 'package:anthrofit/data/program_repository.dart';
import 'package:anthrofit/data/session_repository.dart';
import 'package:anthrofit/data/stored_json.dart';
import 'package:anthrofit/data/workout_templates.dart';
import 'package:anthrofit/models/models.dart';

/// Starts the workout from its detail/home entry point in the chosen mode.
Future<void> startWorkout(WidgetTester tester, {bool guided = false}) async {
  await tester.tap(find.text('Start workout'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(
      ValueKey(guided ? 'start-guided-workout' : 'start-manual-workout'),
    ),
  );
  await tester.pumpAndSettle();
}

const UserProfile sampleProfile = UserProfile(
  name: 'Test User',
  age: 25,
  sex: Sex.preferNotToSay,
  heightCm: 170,
  weightKg: 65.5,
  goal: TrainingGoal.buildMuscle,
  experience: ExperienceLevel.beginner,
  trainingFrequency: TrainingFrequency.four,
  sessionDuration: SessionDuration.min60,
  equipment: [EquipmentAccess.machines, EquipmentAccess.cables],
);

/// Pretend the user already finished setup on an earlier launch.
void seedSavedProfile() {
  SharedPreferences.setMockInitialValues({
    AccountStore.guestModeKey: 'guest',
    ProfileRepository.storageKey: jsonEncode(sampleProfile.toJson()),
  });
}

/// Pretend this is the very first launch.
void seedNoProfile() {
  SharedPreferences.setMockInitialValues({AccountStore.guestModeKey: 'guest'});
}

/// A brand-new install: no mode chosen, so the app shows Welcome.
void seedFreshInstall() {
  SharedPreferences.setMockInitialValues({});
}

/// Pretend setup is done and these programs were saved on an earlier launch.
void seedProfileAndPrograms(
  List<TrainingProgram> programs, {
  String? activeProgramId,
}) {
  SharedPreferences.setMockInitialValues({
    AccountStore.guestModeKey: 'guest',
    ProfileRepository.storageKey: jsonEncode(sampleProfile.toJson()),
    ProgramRepository.storageKey: jsonEncode({
      'activeProgramId': activeProgramId,
      'programs': programs.map((p) => p.toJson()).toList(),
    }),
  });
}

/// Pretend setup is done and this data was saved on an earlier launch.
void seedAppData({
  List<TrainingProgram> programs = const [],
  String? activeProgramId,
  List<WorkoutSession> sessions = const [],
  WorkoutSession? activeSession,
  UserProfile profile = sampleProfile,
}) {
  SharedPreferences.setMockInitialValues({
    AccountStore.guestModeKey: 'guest',
    ProfileRepository.storageKey: jsonEncode(profile.toJson()),
    ProgramRepository.storageKey: jsonEncode({
      'activeProgramId': activeProgramId,
      'programs': programs.map((p) => p.toJson()).toList(),
    }),
    SessionRepository.storageKey: jsonEncode({
      'activeSession': activeSession?.toJson(),
      'sessions': sessions.map((s) => s.toJson()).toList(),
    }),
  });
}

/// A PlannedExercise made of [sets] Working sets that all share the same reps
/// and rest, and have no target load.
PlannedExercise testPlanned(
  String id,
  String exerciseId, {
  int sets = 3,
  int repMin = 8,
  int repMax = 12,
  int rest = 90,
  String note = '',
}) {
  return PlannedExercise(
    id: id,
    exerciseId: exerciseId,
    plannedSets: List.generate(
      sets,
      (_) => PlannedSet(
        setType: SetType.working,
        targetRepMin: repMin,
        targetRepMax: repMax,
        restSeconds: rest,
      ),
    ),
    note: note,
  );
}

/// A finished exercise in a saved session. Each entry of [sets] is
/// (weight, reps). [types] gives each set's type (default: all Working).
/// The saved plan is 8-12 reps for every set except Failure sets (no target).
ExerciseLog testLog(
  String exerciseId,
  String name,
  List<(double?, int)> sets, {
  List<SetType>? types,
  int rest = 90,
}) {
  SetType typeAt(int i) => types == null ? SetType.working : types[i];
  return ExerciseLog(
    id: 'log-$exerciseId',
    exerciseId: exerciseId,
    plannedExerciseId: 'pe-$exerciseId',
    exerciseName: name,
    plannedSets: [
      for (var i = 0; i < sets.length; i++)
        PlannedSet(
          setType: typeAt(i),
          targetRepMin: typeAt(i) == SetType.failure ? null : 8,
          targetRepMax: typeAt(i) == SetType.failure ? null : 12,
          restSeconds: rest,
        ),
    ],
    sets: [
      for (var i = 0; i < sets.length; i++)
        SetLog(
          setNumber: i + 1,
          setType: typeAt(i),
          weightKg: sets[i].$1,
          reps: sets[i].$2,
          isCompleted: true,
          completedAt: DateTime(2026, 1, 1),
        ),
    ],
  );
}

// ---------------------------------------------------------------------------
// A stand-in for Firebase Authentication, so tests need no Firebase.
// ---------------------------------------------------------------------------

class _FakeAccount {
  _FakeAccount({
    required this.uid,
    required this.email,
    required this.password,
    required this.displayName,
    required this.verified,
    this.dateOfBirth,
  });

  final String uid;
  final String email;
  final String password;
  String displayName;
  bool verified;
  DateTime? dateOfBirth;
}

/// Works like Firebase for the cases the app handles. Accounts live in memory,
/// so pass the SAME instance to a restarted app to model a remembered session.
class FakeAuthService implements AuthService {
  FakeAuthService({this.initializeFails = false});

  /// Makes initialize() fail, like Firebase being unavailable.
  bool initializeFails;

  /// If set, the next call that can fail throws this once.
  AuthException? nextError;

  /// While true, sending the verification email fails (account creation works).
  bool failVerificationEmail = false;

  final Map<String, _FakeAccount> _accounts = {};
  String? _signedInEmail;

  /// What the app asked for, in order, for example "signUp:a@x.com:Ann:Lee".
  final List<String> calls = [];
  int verificationEmailsSent = 0;
  final List<String> passwordResets = [];

  static String uidFor(String email) => 'uid_${email.split('@').first}';

  void _maybeFail() {
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
  }

  /// An account that already exists (not signed in).
  void addAccount(
    String email,
    String password, {
    bool verified = true,
    String displayName = '',
    DateTime? dateOfBirth,
  }) {
    final uid = uidFor(email);
    final dob = dateOfBirth ?? DateTime(1998, 5, 20);
    _accounts[email.toLowerCase()] = _FakeAccount(
      uid: uid,
      email: email,
      password: password,
      displayName: displayName,
      verified: verified,
      dateOfBirth: dob,
    );
    final nameParts = displayName.split(' ');
    final firstName = nameParts.isNotEmpty ? nameParts.first : '';
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
    AccountStore().saveAccount(
      AccountInfo(
        uid: uid,
        email: email,
        firstName: firstName,
        lastName: lastName,
        dateOfBirth: dob,
      ),
    );
  }

  /// The user clicked the link in the verification email.
  void markVerified(String email) =>
      _accounts[email.toLowerCase()]!.verified = true;

  /// A session that is already signed in when the app starts.
  void startSignedIn(String email) => _signedInEmail = email.toLowerCase();

  AuthUser _toUser(_FakeAccount a) => AuthUser(
    uid: a.uid,
    email: a.email,
    displayName: a.displayName.isEmpty ? null : a.displayName,
    emailVerified: a.verified,
  );

  @override
  Future<void> initialize() async {
    if (initializeFails) throw const AuthException(AuthErrorCode.unavailable);
  }

  @override
  AuthUser? get currentUser {
    final email = _signedInEmail;
    final account = email == null ? null : _accounts[email];
    return account == null ? null : _toUser(account);
  }

  @override
  Future<AuthUser> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    calls.add('signUp:$email:$firstName:$lastName');
    _maybeFail();
    if (_accounts.containsKey(email.toLowerCase())) {
      throw const AuthException(AuthErrorCode.emailInUse);
    }
    if (password.length < 6) {
      throw const AuthException(AuthErrorCode.weakPassword);
    }
    addAccount(
      email,
      password,
      verified: false,
      displayName: '$firstName $lastName',
    );
    _signedInEmail = email.toLowerCase();
    return _toUser(_accounts[email.toLowerCase()]!);
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    calls.add('signIn:$email');
    _maybeFail();
    final account = _accounts[email.toLowerCase()];
    if (account == null) throw const AuthException(AuthErrorCode.userNotFound);
    if (account.password != password) {
      throw const AuthException(AuthErrorCode.wrongCredentials);
    }
    _signedInEmail = email.toLowerCase();
    return _toUser(account);
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    _signedInEmail = null;
  }

  @override
  Future<void> sendVerificationEmail() async {
    calls.add('sendVerificationEmail');
    _maybeFail();
    if (failVerificationEmail) throw const AuthException(AuthErrorCode.network);
    verificationEmailsSent++;
  }

  @override
  Future<AuthUser?> reloadUser() async {
    calls.add('reloadUser');
    _maybeFail();
    return currentUser;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    calls.add('sendPasswordReset:$email');
    _maybeFail();
    passwordResets.add(email);
  }
}

// ---------------------------------------------------------------------------
// Walking the program setup wizard.
//
// The wizard shows one question per page, so a test can never see two steps at
// once. These helpers drive it by the keys on its buttons and structure tiles,
// never by what happens to be on screen, so a test that only wants a program
// to exist does not have to know how many steps there are.
// ---------------------------------------------------------------------------

/// The wizard's Continue (or, on the last step, Generate program) button.
final Finder setupContinueButton = find.byKey(
  const ValueKey('wizard-continue'),
);

/// The wizard's Back button.
final Finder setupBackButton = find.byKey(const ValueKey('wizard-back'));

/// The focus chip for [focus], on the focus step. Long-press it to open the
/// muscle picker.
Finder setupFocusChip(TrainingFocus focus) =>
    find.byKey(ValueKey('focus-${focus.name}'));

/// The structure tile for [template], on the structure step.
Finder setupStructureTile(ProgramTemplate template) =>
    find.byKey(ValueKey('structure-${template.name}'));

/// Taps Continue once.
Future<void> tapSetupContinue(WidgetTester tester) async {
  await tester.tap(setupContinueButton);
  await tester.pumpAndSettle();
}

/// Taps Continue until [target] is on screen, so a test can jump to the step
/// it cares about without counting the ones before it.
/// Fails rather than looping forever if the wizard will not advance.
Future<void> advanceSetupTo(
  WidgetTester tester,
  Finder target, {
  int maxSteps = 12,
}) async {
  for (var step = 0; step < maxSteps; step++) {
    if (target.evaluate().isNotEmpty) return;
    expect(
      setupContinueButton,
      findsOneWidget,
      reason: 'the wizard stopped before reaching the step under test',
    );
    await tapSetupContinue(tester);
  }
  expect(
    target,
    findsOneWidget,
    reason: 'never reached the step under test after $maxSteps steps',
  );
}

/// Runs the whole wizard from its first step and leaves the planner open.
///
/// Every answer already has a value from the profile, so a test that only
/// needs a program can accept them all. Pass [name] to rename the program.
/// Call it with the setup screen already showing (after "Create program").
Future<void> completeProgramSetup(
  WidgetTester tester, {
  ProgramTemplate template = ProgramTemplate.custom,
  String? name,
}) async {
  expect(
    find.text('Set up program'),
    findsOneWidget,
    reason: 'completeProgramSetup starts on the setup screen',
  );

  await advanceSetupTo(tester, setupStructureTile(template));
  await tester.tap(setupStructureTile(template));
  await tester.pumpAndSettle();
  await tapSetupContinue(tester);

  if (name != null) {
    await tester.enterText(find.byKey(const ValueKey('program-name')), name);
    await tester.pump();
  }
  await tapSetupContinue(tester); // Generate program
}

/// Reads one raw saved object, for checking what sync cached on the device.
Future<Map<String, dynamic>?> readSavedObjectForTest(String key) =>
    readSavedObject(key);

/// Puts the exercise library back to the built-in catalogue.
///
/// The user's own exercises are installed statically, so a test that adds one
/// must not leak into the next. Call this from setUp in any test that touches
/// the library.
void resetExerciseLibrary() => ExerciseLibrary.reset();

/// Loads the built-in catalogue from the asset, once per test run.
///
/// The catalogue is data now, not Dart, so nothing is in the library until
/// it is read. The app does this at start-up; a test has to do it itself.
/// Call it from setUpAll, or use [useExerciseLibrary].
Future<void> loadExerciseCatalog() async {
  if (ExerciseLibrary.isLoaded) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  ExerciseLibrary.applyBuiltIn(await const AssetExerciseCatalog().load());
}

/// Loads the catalogue before every test in the file, and clears the user's
/// own exercises between them. One line in main() covers both.
void useExerciseLibrary() {
  setUp(() async {
    await loadExerciseCatalog();
    ExerciseLibrary.reset();
  });
}

/// Opens the date of birth calendar and accepts its starting date, which is
/// 25 years ago today. [key] is 'dob-field' in profile setup and
/// 'signup-dob-field' when creating an account.
Future<void> pickDateOfBirth(
  WidgetTester tester, {
  String key = 'dob-field',
}) async {
  final field = find.byKey(ValueKey(key));
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

/// Answers every page of first-time profile setup and stops on the last one,
/// so the caller taps Save profile. Height and weight keep their defaults.
Future<void> fillProfileSetup(
  WidgetTester tester, {
  String name = 'Test User',
}) async {
  Future<void> choose(String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
    await tapSetupContinue(tester);
  }

  await tester.enterText(find.byType(TextFormField).first, name);
  await tapSetupContinue(tester);
  // Asked only when the account did not give a date of birth.
  if (find.text('When were you born?').evaluate().isNotEmpty) {
    await pickDateOfBirth(tester);
    await tapSetupContinue(tester);
  }
  await choose('Male');
  await tapSetupContinue(tester); // height
  await tapSetupContinue(tester); // weight
  await choose('Build muscle');
  await choose('New to weight training');
  await choose('4');
  await choose('Machines');
  await choose('Mostly sitting');
  await choose('45–60 minutes');
  for (var i = 0; i < kParqQuestions.length; i++) {
    final no = find.descendant(
      of: find.byKey(ValueKey('parq-$i')),
      matching: find.text('No'),
    );
    await tester.ensureVisible(no);
    await tester.tap(no);
    await tester.pump();
  }
  await tapSetupContinue(tester); // health
  await tapSetupContinue(tester); // limitations: optional
  await tapSetupContinue(tester); // food: optional
  // Now on Review; the caller taps Save profile.
}

/// Closes the rest-and-coach pop-up that opens after a set is logged, if it
/// is open, so the workout screen underneath can be used again.
Future<void> closeRestSheet(WidgetTester tester) async {
  final done = find.byKey(const ValueKey('rest-sheet-done'));
  if (done.evaluate().isEmpty) return;
  await tester.ensureVisible(done);
  await tester.pumpAndSettle();
  await tester.tap(done, warnIfMissed: false);
  await tester.pumpAndSettle();
}
