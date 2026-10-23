import 'package:flutter/foundation.dart';

import '../data/storage_scope.dart';
import 'account.dart';
import 'account_store.dart';
import 'auth_service.dart';

/// The one answer to "who is using the app?". Screens read this and never work
/// it out themselves.
enum AuthStatus {
  /// Still starting up. Show a loading screen.
  initializing,

  /// Using the app without an account (data stays on this device).
  guest,

  /// Not signed in and no mode chosen yet: show Welcome.
  signedOut,

  /// Signed in, email not verified yet.
  unverified,

  /// Signed in and verified.
  verified,
}

/// Owns authentication state and the actions that change it.
/// Account actions throw [AuthException] (friendly codes only) on failure.
class AuthController extends ChangeNotifier {
  AuthController({required this.service, AccountStore? store})
    : _store = store ?? AccountStore();

  final AuthService service;
  final AccountStore _store;

  AuthStatus _status = AuthStatus.initializing;
  AuthUser? _user;
  AccountInfo? _account;
  bool _accountsUnavailable = false;
  bool _migrationPending = false;
  String? _notice;

  AuthStatus get status => _status;

  /// The signed-in Firebase user (unverified or verified), or null.
  AuthUser? get user => _user;

  /// First name, last name and email of the signed-in account, or null.
  AccountInfo? get account => _account;

  /// True if Firebase could not start. Guest mode still works.
  bool get accountsUnavailable => _accountsUnavailable;

  /// True while a verified user must still answer "keep your guest data?".
  bool get migrationPending => _migrationPending;

  /// A one-time message for the next screen (for example "verify your email").
  String? get notice => _notice;

  bool get isGuest => _status == AuthStatus.guest;
  bool get isSignedIn =>
      _status == AuthStatus.unverified || _status == AuthStatus.verified;

  /// Where this person's saved data lives, or null when no data should be
  /// loaded (not signed in, email not verified, or the guest-data question is
  /// still open).
  StorageScope? get dataScope {
    if (_status == AuthStatus.guest) return StorageScope.guest;
    if (_status == AuthStatus.verified && !_migrationPending) {
      return StorageScope.user(_user!.uid);
    }
    return null;
  }

  void clearNotice() {
    if (_notice == null) return;
    _notice = null;
    notifyListeners();
  }

  /// App launch: start the service, then pick the right state in one step so
  /// the wrong screen is never shown first.
  Future<void> start() async {
    try {
      await service.initialize();
    } catch (_) {
      _accountsUnavailable = true;
    }

    final user = _accountsUnavailable ? null : service.currentUser;
    if (user != null) {
      await _enterAccount(user);
    } else if (await _store.isGuestChosen()) {
      _status = AuthStatus.guest;
    } else {
      _status = AuthStatus.signedOut;
    }
    notifyListeners();
  }

  /// Guest mode: no Firebase account is created.
  Future<void> continueAsGuest() async {
    await _store.setGuestChosen(true);
    _user = null;
    _account = null;
    _status = AuthStatus.guest;
    notifyListeners();
  }

  Future<void> signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    DateTime? dateOfBirth,
  }) async {
    final first = firstName.trim();
    final last = lastName.trim();
    final user = await service.signUp(
      email: email.trim(),
      password: password,
      firstName: first,
      lastName: last,
    );
    final account = AccountInfo(
      uid: user.uid,
      firstName: first,
      lastName: last,
      email: user.email.isEmpty ? email.trim() : user.email,
      dateOfBirth: dateOfBirth,
    );
    try {
      await _store.saveAccount(account);
    } catch (_) {
      // The names are also in Firebase's display name.
    }

    String? notice;
    try {
      await service.sendVerificationEmail();
    } catch (_) {
      notice =
          "We couldn't send the verification email. Tap Resend to try again.";
    }
    await _enterAccount(user, account: account);
    _notice = notice;
    notifyListeners();
  }

  Future<void> signIn({required String email, required String password}) async {
    final user = await service.signIn(email: email.trim(), password: password);
    await _enterAccount(user);
    if (_status == AuthStatus.unverified) {
      _notice = 'Please verify your email before continuing.';
    }
    notifyListeners();
  }

  /// Ends the Firebase session. Nothing is deleted: this person's data stays
  /// in their own scope for the next time they sign in.
  Future<void> signOut() async {
    try {
      await service.signOut();
    } catch (_) {
      // Fall through: the app still leaves the account screens.
    }
    _user = null;
    _account = null;
    _migrationPending = false;
    _notice = null;
    _status = AuthStatus.signedOut;
    notifyListeners();
  }

  Future<void> resendVerificationEmail() => service.sendVerificationEmail();

  /// "I've verified my email": re-read the user from Firebase.
  /// Returns true (and moves on) if the email is now verified.
  Future<bool> refreshVerification() async {
    final fresh = await service.reloadUser();
    if (fresh == null) {
      _user = null;
      _account = null;
      _status = AuthStatus.signedOut;
      notifyListeners();
      return false;
    }
    if (!fresh.emailVerified) {
      _user = fresh;
      notifyListeners();
      return false;
    }
    await _enterAccount(fresh);
    notifyListeners();
    return true;
  }

  Future<void> sendPasswordReset(String email) =>
      service.sendPasswordReset(email.trim());

  /// The user chose to keep the guest data: it is moved into this account.
  /// Throws if it could not be moved safely (the guest data is then untouched).
  Future<void> keepGuestData() async {
    final uid = _user!.uid;
    await _store.moveGuestDataTo(StorageScope.user(uid));
    await _store.setMigrationMarker(uid, 'kept');
    _migrationPending = false;
    notifyListeners();
  }

  /// The user chose a clean account. The guest data is left untouched.
  Future<void> startFresh() async {
    await _store.setMigrationMarker(_user!.uid, 'fresh');
    _migrationPending = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------

  Future<void> _enterAccount(AuthUser user, {AccountInfo? account}) async {
    _user = user;
    _account =
        account ??
        await _store.loadAccount(user.uid) ??
        AccountInfo.fromAuthUser(user);
    await _store.setGuestChosen(false);

    if (user.emailVerified) {
      _status = AuthStatus.verified;
      _migrationPending = await _needsMigrationChoice(user.uid);
    } else {
      _status = AuthStatus.unverified;
      _migrationPending = false;
    }
  }

  /// Ask "keep your guest data?" only when there is guest data, this account
  /// has none of its own, and the question has not been answered before.
  Future<bool> _needsMigrationChoice(String uid) async {
    if (await _store.migrationMarker(uid) != null) return false;
    if (await _store.scopeHasData(StorageScope.user(uid))) {
      await _store.setMigrationMarker(uid, 'existing');
      return false;
    }
    return _store.scopeHasData(StorageScope.guest);
  }
}
