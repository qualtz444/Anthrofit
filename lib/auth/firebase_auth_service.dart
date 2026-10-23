import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';

import 'auth_service.dart';

/// Firebase Authentication (email and password only).
///
/// Firebase manages the session, so no password or token is ever stored or
/// logged by the app. Every Firebase failure is converted to an
/// [AuthException]; Firebase's own messages are never passed on.
class FirebaseAuthService implements AuthService {
  fb.FirebaseAuth? _auth;

  @override
  Future<void> initialize() async {
    // If the app's main() already started Firebase, this does nothing extra.
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    _auth = fb.FirebaseAuth.instance;
  }

  fb.FirebaseAuth get _requireAuth {
    final auth = _auth;
    if (auth == null) throw const AuthException(AuthErrorCode.unavailable);
    return auth;
  }

  static AuthUser _toAuthUser(fb.User user) => AuthUser(
    uid: user.uid,
    email: user.email ?? '',
    displayName: user.displayName,
    emailVerified: user.emailVerified,
  );

  @override
  AuthUser? get currentUser {
    final user = _auth?.currentUser;
    return user == null ? null : _toAuthUser(user);
  }

  static AuthException _convert(Object error) {
    if (error is AuthException) return error;
    if (error is fb.FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return const AuthException(AuthErrorCode.invalidEmail);
        case 'wrong-password':
        case 'invalid-credential':
        case 'invalid-login-credentials':
          return const AuthException(AuthErrorCode.wrongCredentials);
        case 'user-not-found':
          return const AuthException(AuthErrorCode.userNotFound);
        case 'email-already-in-use':
          return const AuthException(AuthErrorCode.emailInUse);
        case 'weak-password':
          return const AuthException(AuthErrorCode.weakPassword);
        case 'too-many-requests':
          return const AuthException(AuthErrorCode.tooManyRequests);
        case 'user-disabled':
          return const AuthException(AuthErrorCode.userDisabled);
        case 'network-request-failed':
          return const AuthException(AuthErrorCode.network);
        case 'operation-not-allowed':
          return const AuthException(AuthErrorCode.unavailable);
      }
    }
    return const AuthException(AuthErrorCode.unknown);
  }

  @override
  Future<AuthUser> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    final auth = _requireAuth;
    try {
      final credential = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) throw const AuthException(AuthErrorCode.unknown);
      try {
        await user.updateDisplayName('$firstName $lastName'.trim());
        await user.reload();
      } catch (_) {
        // The account exists. The names are also kept on this device, so a
        // failure here must not make sign-up look like it failed.
      }
      return _toAuthUser(auth.currentUser ?? user);
    } catch (error) {
      throw _convert(error);
    }
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    final auth = _requireAuth;
    try {
      final credential = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) throw const AuthException(AuthErrorCode.unknown);
      return _toAuthUser(user);
    } catch (error) {
      throw _convert(error);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _requireAuth.signOut();
    } catch (error) {
      throw _convert(error);
    }
  }

  @override
  Future<void> sendVerificationEmail() async {
    final user = _requireAuth.currentUser;
    if (user == null) throw const AuthException(AuthErrorCode.unknown);
    try {
      await user.sendEmailVerification();
    } catch (error) {
      throw _convert(error);
    }
  }

  @override
  Future<AuthUser?> reloadUser() async {
    final auth = _requireAuth;
    final user = auth.currentUser;
    if (user == null) return null;
    try {
      await user.reload();
    } catch (error) {
      throw _convert(error);
    }
    final fresh = auth.currentUser;
    return fresh == null ? null : _toAuthUser(fresh);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _requireAuth.sendPasswordResetEmail(email: email);
    } catch (error) {
      throw _convert(error);
    }
  }
}
