/// Whose saved data this is. Every saved item (profile, programs, sessions)
/// lives under a key made by its scope, so two owners can never see each
/// other's data.
///
///   Guest        -> the plain keys that existed before accounts ("user_profile", ...)
///                   so data from before Phase 11 simply IS the guest data.
///   Account `<uid>` -> the same keys with a `u.<uid>.` prefix.
class StorageScope {
  const StorageScope._(this.id, this._prefix);

  static const StorageScope guest = StorageScope._('guest', '');

  /// The scope for one Firebase account. [uid] is Firebase's user id.
  factory StorageScope.user(String uid) =>
      StorageScope._('user:$uid', 'u.$uid.');

  /// Stable identifier, used to tell scopes apart.
  final String id;
  final String _prefix;

  bool get isGuest => _prefix.isEmpty;

  /// The storage key for [base] (for example "user_profile") in this scope.
  String key(String base) => '$_prefix$base';
}
