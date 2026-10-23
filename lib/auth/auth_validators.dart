// Form checks for sign-up and sign-in. Each returns an error message, or null
// when the value is fine.

/// Stricter than Firebase's own minimum of 6.
const int kMinPasswordLength = 8;

/// One thing a new password must have. The sign-up checklist shows each one.
class PasswordRule {
  const PasswordRule(this.label, this._test);

  final String label;
  final bool Function(String) _test;

  bool isMetBy(String password) => _test(password);
}

final List<PasswordRule> passwordRules = [
  PasswordRule(
    'At least $kMinPasswordLength characters',
    (p) => p.length >= kMinPasswordLength,
  ),
  PasswordRule('One uppercase letter', (p) => p.contains(RegExp('[A-Z]'))),
  PasswordRule('One lowercase letter', (p) => p.contains(RegExp('[a-z]'))),
  PasswordRule('One number', (p) => p.contains(RegExp('[0-9]'))),
  // Anything that is not a letter, digit or space counts as special.
  PasswordRule(
    'One special character',
    (p) => p.contains(RegExp(r'[^A-Za-z0-9\s]')),
  ),
];

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// [label] is "first name" or "last name".
String? validateName(String? value, String label) =>
    (value == null || value.trim().isEmpty) ? 'Enter your $label' : null;

String? validateEmail(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Enter your email';
  if (!_emailPattern.hasMatch(text)) return 'Enter a valid email address';
  return null;
}

String? validateNewPassword(String? value) {
  final text = value ?? '';
  if (text.isEmpty) return 'Enter a password';
  // The checklist under the field says which rules are still missing.
  if (passwordRules.any((rule) => !rule.isMetBy(text))) {
    return 'Password does not meet all the requirements';
  }
  return null;
}

String? validatePasswordConfirmation(String? value, String password) {
  final text = value ?? '';
  if (text.isEmpty) return 'Confirm your password';
  if (text != password) return 'Passwords do not match';
  return null;
}

/// For sign-in the password only has to be present.
String? validateEnteredPassword(String? value) =>
    (value == null || value.isEmpty) ? 'Enter your password' : null;
