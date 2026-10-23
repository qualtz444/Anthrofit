// The boundary between ANTHROFIT and whatever provides sign-in.
// Only firebase_auth_service.dart knows about Firebase. Everything else
// (state, screens, tests) uses this interface, so it can be tested without
// Firebase and Firebase's exceptions never reach the screens.

/// What went wrong, in terms the app understands. Never holds raw Firebase text.
enum AuthErrorCode {
  invalidEmail,
  wrongCredentials,
  userNotFound,
  emailInUse,
  weakPassword,
  tooManyRequests,
  userDisabled,
  network,
  unavailable,
  unknown,
}

class AuthException implements Exception {
  const AuthException(this.code);

  final AuthErrorCode code;

  @override
  String toString() => 'AuthException($code)';
}

/// The signed-in Firebase user, as far as the app cares.
class AuthUser {
  const AuthUser({
    required this.uid,
    required this.email,
    this.displayName,
    required this.emailVerified,
  });

  final String uid;
  final String email;
  final String? displayName;
  final bool emailVerified;
}

abstract class AuthService {
  /// Starts the service. Throws if accounts are not available (for example
  /// Firebase could not start). The app then works as guest-only.
  Future<void> initialize();

  /// The user whose session was restored or just created, or null.
  AuthUser? get currentUser;

  /// Creates the account and sets the display name to "firstName lastName".
  /// Does NOT send the verification email: call [sendVerificationEmail].
  Future<AuthUser> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  });

  Future<AuthUser> signIn({required String email, required String password});

  Future<void> signOut();

  Future<void> sendVerificationEmail();

  /// Re-reads the user from the server (to see if the email is now verified).
  /// Null if there is no signed-in user any more.
  Future<AuthUser?> reloadUser();

  Future<void> sendPasswordReset(String email);

  /// Checks [password] against the signed-in account. Deleting an account
  /// needs a recent sign-in, so this is called just before [deleteUser].
  /// Throws [AuthErrorCode.wrongCredentials] when the password is wrong.
  Future<void> confirmPassword(String password);

  /// Deletes the signed-in account's login. Its data must be removed first:
  /// once the login is gone, the cloud refuses every request for it.
  Future<void> deleteUser();
}
