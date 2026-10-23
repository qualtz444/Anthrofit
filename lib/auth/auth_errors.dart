import 'auth_service.dart';

/// Short, friendly text for each failure. [action] finishes the generic
/// message: "Unable to sign in. Please try again."
String authErrorMessage(AuthErrorCode code, {String action = 'sign in'}) {
  switch (code) {
    case AuthErrorCode.invalidEmail:
      return 'Enter a valid email address.';
    case AuthErrorCode.wrongCredentials:
    case AuthErrorCode.userNotFound:
      return 'Incorrect email or password.';
    case AuthErrorCode.emailInUse:
      return 'An account with this email already exists.';
    case AuthErrorCode.weakPassword:
      return 'Choose a stronger password (at least 6 characters).';
    case AuthErrorCode.tooManyRequests:
      return 'Too many attempts. Please wait a moment and try again.';
    case AuthErrorCode.userDisabled:
      return 'This account has been disabled.';
    case AuthErrorCode.network:
      return 'Check your internet connection and try again.';
    case AuthErrorCode.unavailable:
      return 'Accounts are unavailable right now. You can still use '
          'ANTHROFIT without an account.';
    case AuthErrorCode.unknown:
      return 'Unable to $action. Please try again.';
  }
}

/// Turns ANY error into text that is safe to show. Raw exception text, stack
/// traces and tokens are never shown.
String describeAuthError(Object error, {String action = 'sign in'}) {
  if (error is AuthException) {
    return authErrorMessage(error.code, action: action);
  }
  return 'Unable to $action. Please try again.';
}
