import '../core/json_utils.dart';
import 'auth_service.dart';

/// Who the account belongs to. This is ACCOUNT information, separate from the
/// training Profile (age, goal, equipment and so on). No password is stored.
///
/// Firebase holds only a single display name, so the first and last name are
/// also kept on this device, with the account's other data.
class AccountInfo {
  const AccountInfo({
    required this.uid,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.dateOfBirth,
  });

  final String uid;
  final String firstName;
  final String lastName;
  final String email;

  /// Asked when the account is created, and used to fill profile setup.
  /// Kept on this device with the names; Firebase does not hold it.
  final DateTime? dateOfBirth;

  /// "First Last", used to suggest the profile's display name.
  String get fullName =>
      [firstName, lastName].where((part) => part.isNotEmpty).join(' ');

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    if (dateOfBirth != null) 'dateOfBirth': dateOfBirth!.toIso8601String(),
  };

  factory AccountInfo.fromJson(Map<String, dynamic> json) => AccountInfo(
    uid: parseString(json['uid']),
    firstName: parseString(json['firstName']),
    lastName: parseString(json['lastName']),
    email: parseString(json['email']),
    dateOfBirth: parseDate(json['dateOfBirth']),
  );

  /// Best effort when there is no saved record (for example the first sign-in
  /// on a new device): the first word of Firebase's display name is the first
  /// name and the rest is the last name.
  factory AccountInfo.fromAuthUser(AuthUser user) {
    final parts = (user.displayName ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    return AccountInfo(
      uid: user.uid,
      firstName: parts.isEmpty ? '' : parts.first,
      lastName: parts.length > 1 ? parts.sublist(1).join(' ') : '',
      email: user.email,
    );
  }
}
